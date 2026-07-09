import AppKit
import XCTest
@testable import Suniye

/// End-to-end Command Mode: the REAL agent loop + REAL brain (a live LLM) + REAL
/// tools + REAL accessibility perception — only ASR is skipped (the task is fed
/// as text). This is an integration harness, NOT a unit test: it launches real
/// apps and talks to a real model, so it is OFF unless `SUNIYE_CMD_E2E=1` and a
/// model is configured. Driven by `scripts/e2e_command_mode.sh`.
///
/// Two tiers:
///  • launch tier (default) — asserts on `NSWorkspace.frontmostApplication`, which
///    needs no TCC grant, so CI-style runs and `scripts/e2e_command_mode.sh` can
///    verify the brain → loop → open_app → settle path unattended.
///  • AX tier (`SUNIYE_CMD_E2E_AX=1`) — clicks/types/navigates and asserts via the
///    accessibility tree / AppleScript. Needs Accessibility (and Automation) granted
///    to the test runner, so it only runs when explicitly opted in.
///
/// LLM comes from the environment (any OpenAI-compatible endpoint — local
/// llama-server or a remote API):
///   SUNIYE_E2E_LLM_URL   base url, e.g. http://127.0.0.1:8080   (required)
///   SUNIYE_E2E_LLM_MODEL model id                               (default "local")
///   SUNIYE_E2E_LLM_KEY   bearer token                           (optional)
@MainActor
final class CommandModeE2ETests: XCTestCase {
    private var config: E2EConfig!
    private var llm: LiveLLM!

    override func setUpWithError() throws {
        guard let loaded = Self.loadConfig() else {
            throw XCTSkip("Command Mode E2E is off. Run via scripts/e2e_command_mode.sh (writes ~/.suniye-cmd-e2e.json).")
        }
        config = loaded
        llm = LiveLLM(base: loaded.url, model: loaded.model, key: loaded.key)
    }

    private struct E2EConfig {
        let url: String
        let model: String
        let key: String?
        let ax: Bool
    }

    /// Config comes from a file the runner writes (a macOS test host does NOT
    /// inherit xcodebuild's env, so a file is the reliable channel); env vars are
    /// honored too for direct/manual runs.
    private static func loadConfig() -> E2EConfig? {
        let env = ProcessInfo.processInfo.environment
        if env["SUNIYE_CMD_E2E"] == "1", let url = env["SUNIYE_E2E_LLM_URL"], !url.isEmpty {
            return E2EConfig(url: url, model: env["SUNIYE_E2E_LLM_MODEL"] ?? "local",
                             key: env["SUNIYE_E2E_LLM_KEY"], ax: env["SUNIYE_CMD_E2E_AX"] == "1")
        }
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".suniye-cmd-e2e.json")
        guard let data = try? Data(contentsOf: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["enabled"] as? Bool == true,
              let url = json["url"] as? String, !url.isEmpty else { return nil }
        return E2EConfig(url: url, model: json["model"] as? String ?? "local",
                         key: json["key"] as? String, ax: json["ax"] as? Bool ?? false)
    }

    // MARK: launch tier (no TCC — runnable unattended)

    func testOpensAppByName() async throws {
        try await assertOpened("TextEdit", context: await run(task: "open TextEdit"))
    }

    func testActivatesAlreadyRunningApp() async throws {
        try await assertOpened("Finder", context: await run(task: "switch to Finder"))
    }

    // MARK: AX tier (needs Accessibility + Automation — opt in with SUNIYE_CMD_E2E_AX=1)

    func testOpensSafariAndNavigates() async throws {
        try requireAXTier()
        try resetSafariToBlank() // start clean so a leftover page can't mask the result
        let target = "example.com"
        let outcome = await run(task: "go to \(target)")
        print("=== Safari navigate trace ===\n\(outcome.trace)\n=============================")
        // Give the page a moment to commit the address, then read Safari's URL.
        try await Task.sleep(nanoseconds: 3_000_000_000)
        let url = try safariCurrentURL()
        XCTAssertTrue(url.localizedCaseInsensitiveContains(target),
                      "Safari URL was \"\(url)\", expected to contain \(target). trace:\n\(outcome.trace)")
    }

    private func resetSafariToBlank() throws {
        let source = """
        tell application "Safari"
          activate
          if (count of windows) = 0 then make new document
          set URL of current tab of front window to "about:blank"
        end tell
        """
        guard let script = NSAppleScript(source: source) else { throw XCTSkip("could not build reset script") }
        var err: NSDictionary?
        script.executeAndReturnError(&err)
        if let err { throw XCTSkip("Safari reset needs Automation permission: \(err)") }
    }

    // MARK: harness

    private struct Outcome {
        let result: AgentRunResult
        let steps: [AgentStep]
        var trace: String {
            steps.map { "  \($0.toolCall.name) \($0.toolCall.arguments) -> \($0.result?.output ?? $0.error ?? "-")" }
                .joined(separator: "\n") + "\n  => \(result.outcome) (\(result.summary))"
        }
        func reachedTool(_ name: String) -> Bool { steps.contains { $0.toolCall.name == name } }
    }

    private func run(task: String) async -> Outcome {
        let reader = AXTreeReader()
        let recorder = StepRecorder()
        let registry = AgentToolRegistry(tools: [
            ReadScreenTool(reader: reader),
            OpenAppTool(launcher: SystemAppLauncher()),
            ClickTool(resolver: reader),
            FocusTool(resolver: reader),
            TypeTextTool(typer: CGEventTyper()),
            PressKeysTool(poster: SystemKeyChordPoster()),
            RunAppleScriptTool(),
            FinishTool(),
        ])
        let agent = CommandModeAgent(
            brain: LocalLLMAgentBrain(generator: llm),
            registry: registry,
            screenReader: reader,
            maxSteps: 50,
            onStep: { recorder.add($0) }
        )
        let result = await agent.run(task: task)
        return Outcome(result: result, steps: recorder.steps)
    }

    /// Robust launch assertion for headless runs: the brain must have chosen
    /// open_app for the right app AND the app must end up running. Frontmost is
    /// reported, not required — a background test host can't steal focus (macOS
    /// focus-stealing prevention), unlike a real user-initiated command.
    private func assertOpened(_ name: String, context: Outcome) async throws {
        XCTAssertTrue(context.reachedTool("open_app"), "brain never chose open_app. trace:\n\(context.trace)")
        let openArg = context.steps.first { $0.toolCall.name == "open_app" }?.toolCall.arguments["name"] ?? ""
        XCTAssertTrue(openArg.localizedCaseInsensitiveContains(name) || name.localizedCaseInsensitiveContains(openArg),
                      "open_app targeted \"\(openArg)\", expected \(name). trace:\n\(context.trace)")
        func running() -> Bool {
            NSWorkspace.shared.runningApplications.contains { $0.localizedName?.localizedCaseInsensitiveContains(name) == true }
        }
        for _ in 0..<20 where !running() { try await Task.sleep(nanoseconds: 150_000_000) }
        XCTAssertTrue(running(), "\(name) is not running after the task. trace:\n\(context.trace)")
        let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
        if front.localizedCaseInsensitiveContains(name) == false {
            print("note: \(name) launched but frontmost=\(front) — headless focus-stealing prevention (expected).")
        }
    }

    private func requireAXTier() throws {
        guard config.ax else {
            throw XCTSkip("AX tier off — needs Accessibility+Automation granted to the runner. Re-run with --ax.")
        }
    }

    private func safariCurrentURL() throws -> String {
        guard let script = NSAppleScript(source: "tell application \"Safari\" to return URL of current tab of front window") else {
            throw XCTSkip("could not build AppleScript")
        }
        var err: NSDictionary?
        let out = script.executeAndReturnError(&err)
        if let err { throw XCTSkip("Safari AppleScript needs Automation permission: \(err)") }
        return out.stringValue ?? ""
    }

    // MARK: - test doubles

    /// Thread-safe step log (onStep may be invoked across suspension points).
    private final class StepRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [AgentStep] = []
        func add(_ step: AgentStep) { lock.lock(); storage.append(step); lock.unlock() }
        var steps: [AgentStep] { lock.lock(); defer { lock.unlock() }; return storage }
    }

    /// Real brain over a live OpenAI-compatible endpoint. Reuses the app's tolerant
    /// response parser (`ChatCompletionResponse.extractText`) so the harness sees
    /// exactly what the shipped transport sees.
    private struct LiveLLM: AgentTextGenerator {
        let base: String
        let model: String
        let key: String?

        func generate(instructions: String, userText: String) async throws -> String {
            var request = URLRequest(url: URL(string: "\(base)/v1/chat/completions")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let key, !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
            let body: [String: Any] = [
                "model": model,
                "messages": [["role": "user", "content": "\(instructions)\n\n<task>\n\(userText)\n</task>"]],
                "temperature": 0, "top_p": 1, "max_tokens": 512, "stream": false,
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            return try ChatCompletionResponse.extractText(from: data)
        }
    }

    /// Types unicode via CGEvent (AX tier only; needs Accessibility).
    private struct CGEventTyper: TextTyping {
        func type(_ text: String) {
            let source = CGEventSource(stateID: .hidSystemState)
            for unit in text.utf16 {
                var chunk = unit
                for down in [true, false] {
                    let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
                    event?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &chunk)
                    event?.post(tap: .cghidEventTap)
                }
            }
        }
    }
}
