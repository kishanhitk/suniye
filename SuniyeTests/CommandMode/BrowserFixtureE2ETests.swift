import AppKit
import XCTest
@testable import Suniye

/// AUTONOMOUS end-to-end tests for browser control: the REAL BrowserBridge + the
/// REAL Chrome extension (already loaded + paired) acting on a local fixture page
/// — no human in the loop. Driven by `scripts/e2e_browser_command.sh`, which quits
/// Suniye Preview (frees the bridge port; the extension then reconnects to the
/// test's bridge within seconds), writes the gate file, and relaunches after.
///
/// Requirements when the gate is on: Chrome running with the paired extension
/// loaded from ~/Library/Application Support/Suniye/BrowserExtension.
@MainActor
final class BrowserFixtureE2ETests: XCTestCase {
    private static let gateURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".suniye-browser-e2e.json")

    private var bridge: BrowserBridge!
    private var fixtureServer: Process?
    private var fixtureURL: String = ""
    private var confirmations: [String] = []
    private var confirmAnswer = true
    private var gateConfig: [String: Any] = [:]

    // MARK: - Boot / teardown

    override func setUp() async throws {
        guard let gateData = try? Data(contentsOf: Self.gateURL),
              let gate = try? JSONSerialization.jsonObject(with: gateData) as? [String: Any],
              gate["enabled"] as? Bool == true else {
            throw XCTSkip("Browser E2E is off. Run via scripts/e2e_browser_command.sh.")
        }
        gateConfig = gate
        // Pairing (port + token) comes from the extension the user already loaded.
        let pairingURL = BrowserExtensionInstaller.installedURL.appendingPathComponent("pairing.json")
        guard let data = try? Data(contentsOf: pairingURL),
              let pairing = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let port = (pairing["port"] as? Int).map(UInt16.init),
              let token = pairing["token"] as? String else {
            throw XCTSkip("No paired extension (missing pairing.json). Launch Suniye Preview once and load the extension.")
        }

        // Local fixture server (python3 http.server) on a free port.
        let fixturesDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()            // CommandMode/
            .deletingLastPathComponent()            // SuniyeTests/
            .appendingPathComponent("Fixtures")
        let httpPort = Self.freePort()
        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = ["-m", "http.server", String(httpPort), "--bind", "127.0.0.1", "--directory", fixturesDir.path]
        server.standardOutput = FileHandle.nullDevice
        server.standardError = FileHandle.nullDevice
        try server.run()
        fixtureServer = server
        fixtureURL = "http://127.0.0.1:\(httpPort)/browser_fixture.html"

        // The bridge on the PAIRED port — Suniye Preview must not be running.
        bridge = BrowserBridge(config: BrowserBridgeConfig(portCandidates: [port], token: token))
        do {
            try await bridge.start()
        } catch {
            throw XCTSkip("Could not bind port \(port) — quit Suniye Preview first (the script does this). \(error)")
        }

        // Wait for the extension to (re)connect: ws-close retry ≈2s,
        // service-worker-eviction alarm ≤30s. (Chrome is launched below if needed.)
        let prelaunch = Process()
        prelaunch.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        prelaunch.arguments = ["-a", "Google Chrome"]
        try prelaunch.run()
        prelaunch.waitUntilExit()

        let connected = await waitUntil(45) { await self.bridge.isConnected }
        guard connected else {
            throw XCTSkip("Extension never connected — is Chrome running with the Suniye extension loaded?")
        }

        // Self-heal stale service-worker code: Chrome caches unpacked SW scripts
        // until an explicit extension reload — and getManifest() can report a
        // fresh manifest over stale code, so compare against the CODE_VERSION
        // constant baked into the repo's background.js.
        let repoWorker = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Suniye/BrowserExtension/background.js")
        let expected: String? = {
            guard let source = try? String(contentsOf: repoWorker, encoding: .utf8),
                  let range = source.range(of: #"CODE_VERSION = "([^"]+)""#, options: .regularExpression) else { return nil }
            return String(source[range])
                .replacingOccurrences(of: #"CODE_VERSION = ""#, with: "")
                .replacingOccurrences(of: "\"", with: "")
        }()
        if let expected,
           let diag = try? await bridge.send(tool: "diag", args: [:], timeout: 5),
           diag.result["v"] != expected {
            _ = try? await bridge.send(tool: "reload", args: [:], timeout: 5)
            _ = await waitUntil(15) { await !self.bridge.isConnected }
            let back = await waitUntil(45) { await self.bridge.isConnected }
            guard back,
                  let recheck = try? await bridge.send(tool: "diag", args: [:], timeout: 5),
                  recheck.result["v"] == expected else {
                throw XCTSkip("Extension is running stale code (want \(expected)) and couldn't self-reload — reload it once in chrome://extensions.")
            }
        }

        // Only now open the fixture tab — AFTER any self-heal reload, so the tab
        // and the (possibly restarted) service worker start from a clean slate.
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-a", "Google Chrome", fixtureURL]
        try open.run()
        open.waitUntilExit()
        try? await Task.sleep(nanoseconds: 700_000_000) // let the tab become active
    }

    override func tearDown() async throws {
        // Close this test's fixture tab — leftover tabs + the SW's pinned-tab
        // state are what made back-to-back tests interfere.
        _ = try? await bridge?.send(tool: "close_tab", args: [:], timeout: 5)
        await bridge?.stop()
        bridge = nil
        fixtureServer?.terminate()
        fixtureServer = nil
    }

    // MARK: - The scenario suite (one sequential run over one page)

    func testBrowserControlEndToEnd() async throws {
        let surface = makeSurface()

        // 1. navigate — fresh load, also proves load-complete waiting.
        let nav = try await bridge.send(tool: "navigate", args: ["url": fixtureURL + "?run=e2e"], timeout: 30)
        XCTAssertTrue(nav.ok, "navigate failed: \(nav.errorMessage ?? "?")")

        // 2. snapshot shape + control prioritization past 70 filler links.
        let observation = await surface.readScreen()
        XCTAssertEqual(surface.activeKind, .browser)
        XCTAssertTrue(observation.contains("Actionable elements — reference an id with click/focus:"), observation)
        XCTAssertTrue(observation.contains(#"button "Add to cart""#),
                      "Add to cart must survive the 60-element cap despite 70 links:\n\(observation)")
        XCTAssertTrue(observation.contains(#"searchfield "Search products""#), observation)
        let cartRef = try XCTUnwrap(ref(in: observation, labelled: #"button "Add to cart""#))
        let searchRef = try XCTUnwrap(ref(in: observation, labelled: "Search products"))
        let linkRef = try XCTUnwrap(ref(in: observation, labelled: "More information"))
        let rerenderRef = try XCTUnwrap(ref(in: observation, labelled: "Start rerender"))
        let focusPwRef = try XCTUnwrap(ref(in: observation, labelled: "Focus password"))

        // 3. benign link click — no confirmation, real trusted click mutates the DOM.
        confirmations = []
        let linked = await surface.click(id: linkRef)
        XCTAssertEqual(linked.output, "clicked \(linkRef)")
        try await expectStatus("LINKED")
        XCTAssertTrue(confirmations.isEmpty, "a plain link must not require confirmation")

        // 4. focus + type into the page (echo proves real input events fired).
        _ = await surface.focus(id: searchRef)
        let typed = await surface.typeText("iphone 17")
        XCTAssertEqual(typed.output, "typed 9 chars")
        try await expectPage(contains: "ECHO:iphone 17")

        // 5. Enter submits the form via trusted CDP key events.
        let pressed = await surface.pressKeys("Return")
        XCTAssertEqual(pressed.output, "pressed enter")
        try await expectStatus("SUBMITTED:iphone 17")

        // 6. consequential click DECLINED — must never reach the page.
        confirmAnswer = false
        confirmations = []
        let declined = await surface.click(id: cartRef)
        XCTAssertTrue(declined.output.contains("declined"), declined.output)
        XCTAssertEqual(confirmations.count, 1)
        XCTAssertTrue(confirmations[0].contains("Add to cart"))
        try await expectStatus("SUBMITTED:iphone 17") // unchanged

        // 7. consequential click ALLOWED — confirm gate then real click.
        confirmAnswer = true
        let carted = await surface.click(id: cartRef)
        XCTAssertEqual(carted.output, "clicked \(cartRef)")
        try await expectStatus("CARTED")

        // 8. SPA re-render strips our tag — identity-verified self-heal recovers.
        _ = await surface.click(id: rerenderRef)
        try await expectStatus("RERENDER-ARMED")
        try await Task.sleep(nanoseconds: 800_000_000) // let the node get replaced
        let healed = await surface.click(id: cartRef)
        XCTAssertEqual(healed.output, "clicked \(cartRef)", "self-heal should recover the re-rendered button")
        try await expectStatus("CARTED-AFTER-RERENDER")

        // 9. sensitive-field refusal: focus the password via the page's own button,
        // then try to type — the extension must refuse.
        _ = await surface.click(id: focusPwRef)
        let refused = await surface.typeText("hunter2")
        XCTAssertTrue(refused.output.contains("password") || refused.output.contains("can't"),
                      "typing into a password field must be refused, got: \(refused.output)")
        let page = try await readPage()
        XCTAssertFalse(page.contains("hunter2"), "the secret must never reach the page")
    }

    /// The exact shape that stalled in dogfooding: an "Account → My orders"
    /// dropdown where the menu item is display:none until the toggle is clicked.
    /// Proves the item is ABSENT before and PRESENT after — i.e. that a re-read
    /// after a click surfaces newly-revealed controls (so the model has a fresh
    /// ref to click, rather than re-clicking the toggle and stalling).
    func testRevealedDropdownMenuAppearsInSnapshotAfterClick() async throws {
        let surface = makeSurface()
        confirmAnswer = true

        let nav = try await bridge.send(tool: "navigate", args: ["url": fixtureURL + "?run=menu"], timeout: 30)
        XCTAssertTrue(nav.ok)

        let before = await surface.readScreen()
        XCTAssertTrue(before.contains(#"button "Account""#), before)
        XCTAssertFalse(before.contains(#""My orders""#), "the hidden menu item must not be snapshotted yet")
        let accountRef = try XCTUnwrap(ref(in: before, labelled: #"button "Account""#))

        _ = await surface.click(id: accountRef)
        try await expectStatus("MENU-OPEN")

        // A fresh read after the click MUST surface the revealed item.
        let after = await surface.readScreen()
        XCTAssertTrue(after.contains(#""My orders""#),
                      "the revealed menu item must appear after the toggle click:\n\(after)")
        let ordersRef = try XCTUnwrap(ref(in: after, labelled: "My orders"))
        _ = await surface.click(id: ordersRef)
        try await expectStatus("ORDERS-OPENED")
    }

    /// The full agent machinery (loop + registry + surface + real extension) driven
    /// by a deterministic brain — proves the wiring end-to-end without LLM variance.
    func testScriptedAgentClicksAddToCart() async throws {
        let surface = makeSurface()
        confirmAnswer = true
        confirmations = []

        let nav = try await bridge.send(tool: "navigate", args: ["url": fixtureURL + "?run=agent"], timeout: 30)
        XCTAssertTrue(nav.ok)

        let registry = AgentToolRegistry(tools: [
            ReadScreenTool(reader: surface),
            ClickTool(surface: surface),
            FinishTool(),
        ])
        let agent = CommandModeAgent(
            brain: LabelSeekingBrain(targetLine: #"button "Add to cart""#),
            registry: registry,
            screenReader: surface,
            maxSteps: 6
        )
        let result = await agent.run(task: "add the item to my cart")
        XCTAssertEqual(result.outcome, .completed, result.summary)
        XCTAssertEqual(confirmations.count, 1, "the risky click must pass through the confirm gate")
        try await expectStatus("CARTED")
    }

    /// FULL pipeline with a REAL LLM: the production brain + prompt + parser +
    /// loop + routing surface + real extension + real page, only ASR skipped.
    /// Armed by scripts/e2e_browser_command.sh --llm (spawns a local llama-server).
    func testRealLLMAgentAddsToCart() async throws {
        let result = try await runLLMAgent(task: "add the item to my cart", run: "llm-cart")
        try await expectStatus("CARTED", timeout: 8)
        XCTAssertGreaterThanOrEqual(confirmations.count, 1, "the risky click must pass the confirm gate")
        XCTAssertEqual(result.invalidActions, 0, "the model should emit only valid tool calls")
    }

    /// The dogfood shape the earlier LLM test MISSED: a menu item that only exists
    /// after a click, buried among many links. The model must click "Account",
    /// re-read (now the revealed "My orders" is snapshotted), and click it —
    /// instead of re-clicking the toggle and stalling.
    func testRealLLMNavigatesAccountDropdown() async throws {
        let result = try await runLLMAgent(task: "open the account menu, then open my orders", run: "llm-menu")
        try await expectStatus("ORDERS-OPENED", timeout: 8)
        XCTAssertEqual(result.invalidActions, 0, "the model should emit only valid tool calls")
    }

    // MARK: - Complex LLM scenarios on the deterministic fixture (smart model)

    func testLLMSearchSubmitsQuery() async throws {
        let result = try await runLLMAgent(task: "search for wireless headphones", run: "llm-search")
        XCTAssertEqual(result.invalidActions, 0)
        try await expectPage(contains: "SUBMITTED:wireless headphones", timeout: 8)
    }

    func testLLMFillsMultiFieldSettingsForm() async throws {
        let result = try await runLLMAgent(
            task: "in settings, set full name to Alice Smith, set email to alice@example.com, turn ON the newsletter subscription, then save",
            run: "llm-form", maxSteps: 16)
        XCTAssertEqual(result.invalidActions, 0)
        let page = try await pollPage { $0.contains("SAVED:") }
        XCTAssertTrue(page.contains("Alice Smith"), "name not saved: \(saved(page))")
        XCTAssertTrue(page.contains("alice@example.com"), "email not saved: \(saved(page))")
        XCTAssertTrue(saved(page).hasSuffix("|true"), "subscribe checkbox not enabled: \(saved(page))")
    }

    func testLLMPaginationLoadsMoreTwice() async throws {
        // Repeated identical "Load more" clicks — legitimate because each changes
        // the snapshot; the observation-aware repeat-guard must allow them.
        let result = try await runLLMAgent(task: "click Load more two times", run: "llm-page", maxSteps: 10)
        XCTAssertEqual(result.invalidActions, 0)
        try await expectPage(contains: "LOADED:2", timeout: 8)
    }

    func testLLMDeleteRequiresConfirmation() async throws {
        let result = try await runLLMAgent(task: "delete my account", run: "llm-delete")
        XCTAssertEqual(result.invalidActions, 0)
        XCTAssertGreaterThanOrEqual(confirmations.count, 1, "a destructive action must pass the confirm gate")
        try await expectPage(contains: "DELETED", timeout: 8)
    }

    func testLLMReadsPageAndAnswers() async throws {
        // The answer lives in a non-actionable <div>, so the model must read the
        // page text (not the element snapshot) and report via finish.
        let result = try await runLLMAgent(task: "when is order A1042 arriving?", run: "llm-read")
        XCTAssertEqual(result.outcome, .completed)
        XCTAssertTrue(result.summary.lowercased().contains("jul 14") || result.summary.contains("14"),
                      "should have read + reported the arrival date, got: \(result.summary)")
    }

    private func saved(_ page: String) -> String {
        page.split(separator: "\n").first(where: { $0.hasPrefix("SAVED:") }).map(String.init) ?? page
    }

    private func pollPage(_ predicate: (String) -> Bool, timeout: TimeInterval = 8) async throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var last = ""
        while Date() < deadline {
            last = (try? await readPage()) ?? last
            if predicate(last) { return last }
            try await Task.sleep(nanoseconds: 150_000_000)
        }
        return last
    }

    @discardableResult
    private func runLLMAgent(task: String, run: String, maxSteps: Int = 12) async throws -> AgentRunResult {
        guard let llmURL = gateConfig["llm_url"] as? String, !llmURL.isEmpty else {
            throw XCTSkip("LLM tier off — run scripts/e2e_browser_command.sh --llm")
        }
        let surface = makeSurface()
        confirmAnswer = true
        confirmations = []

        let nav = try await bridge.send(tool: "navigate", args: ["url": fixtureURL + "?run=\(run)"], timeout: 30)
        XCTAssertTrue(nav.ok)

        let generator = FixtureLiveLLM(base: llmURL, model: gateConfig["llm_model"] as? String ?? "local",
                                       key: gateConfig["llm_key"] as? String)
        // Mirror the PRODUCTION registry (finishCommandModeSession): the model has
        // open_app + run_applescript available, so it can be tempted to control the
        // web via AppleScript/JS — which Chrome blocks. The scenario status
        // assertions verify it took the reliable read_screen→click path instead.
        let registry = AgentToolRegistry(tools: [
            ReadScreenTool(reader: surface),
            OpenAppTool(launcher: SystemAppLauncher()),
            ClickTool(surface: surface),
            FocusTool(surface: surface),
            TypeTextTool(surface: surface),
            PressKeysTool(surface: surface),
            RunAppleScriptTool(),
            BrowserReadTextTool(transport: bridge),
            BrowserNavigateTool(transport: bridge),
            FinishTool(),
        ])
        let trace = TraceRecorder()
        let agent = CommandModeAgent(
            brain: LocalLLMAgentBrain(generator: generator),
            registry: registry,
            screenReader: surface,
            maxSteps: maxSteps,
            onStep: { step in
                trace.add("\(step.toolCall.name) \(step.toolCall.arguments) -> \(step.result?.output.prefix(200) ?? Substring(step.error ?? "-"))")
            }
        )
        let result = await agent.run(task: task)
        trace.add("=> \(result.outcome) steps=\(result.stepCount) tools=\(result.toolInvocations) invalid=\(result.invalidActions) summary=\(result.summary.prefix(160))")
        try? trace.dump().write(toFile: "/tmp/suniye-llm-trace-\(run).txt", atomically: true, encoding: .utf8)
        return result
    }

    private final class TraceRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [String] = []
        func add(_ line: String) { lock.lock(); lines.append(line); lock.unlock() }
        func dump() -> String { lock.lock(); defer { lock.unlock() }; return lines.joined(separator: "\n") }
    }

    /// Same OpenAI-compatible transport shape as the app's; kept local to the test.
    private struct FixtureLiveLLM: AgentTextGenerator {
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
                "temperature": 0, "top_p": 1, "max_tokens": 256, "stream": false,
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            return try ChatCompletionResponse.extractText(from: data)
        }
    }

    // MARK: - Helpers

    private func makeSurface() -> RoutingCommandSurface {
        RoutingCommandSurface(
            native: AXTreeReader(),
            browser: BrowserSnapshotReader(transport: bridge),
            transport: bridge,
            nativeTyper: NoopTyper(),
            keyPoster: NoopKeyPoster(),
            frontmostBundleID: { "com.google.Chrome" }, // decouple from real app focus
            isBrowser: { _ in true },
            confirmRisky: { [weak self] description in
                self?.confirmations.append(description)
                return self?.confirmAnswer ?? false
            }
        )
    }

    private func ref(in observation: String, labelled label: String) -> String? {
        for line in observation.split(separator: "\n") where line.contains(label) {
            if let head = line.split(separator: ":").first, head.hasPrefix("e") {
                return String(head)
            }
        }
        return nil
    }

    private func readPage() async throws -> String {
        let response = try await bridge.send(tool: "read_text", args: [:], timeout: 10)
        guard response.ok else {
            // Surface the failure INTO the polled text so expectPage's failure
            // message shows why reads are failing instead of an empty page.
            return "[read_text error \(response.errorCode ?? "?"): \(response.errorMessage ?? "?")] url=\(response.result["url"] ?? "?")"
        }
        let text = response.result["text"] ?? ""
        if text.isEmpty {
            return "[empty read] url=\(response.result["url"] ?? "?") href=\(response.result["href"] ?? "?") tc=\(response.result["tc"] ?? "?") vis=\(response.result["vis"] ?? "?")"
        }
        return text
    }

    private func expectStatus(_ status: String, timeout: TimeInterval = 4,
                              file: StaticString = #filePath, line: UInt = #line) async throws {
        try await expectPage(contains: status, timeout: timeout, file: file, line: line)
    }

    private func expectPage(contains needle: String, timeout: TimeInterval = 4,
                            file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        var last = ""
        while Date() < deadline {
            do {
                last = try await readPage()
            } catch {
                last = "[send threw: \(error)]"
            }
            if last.contains(needle) { return }
            try await Task.sleep(nanoseconds: 150_000_000)
        }
        XCTFail("page never showed \"\(needle)\"; last page text:\n\(last.prefix(600))", file: file, line: line)
    }

    private func waitUntil(_ timeout: TimeInterval, _ condition: @escaping () async -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return await condition()
    }

    private static func freePort() -> UInt16 {
        let sock = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        defer { close(sock) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        let bound = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.bind(sock, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { return 8971 }
        var assigned = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &assigned) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                _ = Darwin.getsockname(sock, sa, &length)
            }
        }
        return UInt16(bigEndian: assigned.sin_port)
    }

    private struct NoopTyper: TextTyping { func type(_ text: String) {} }
    private struct NoopKeyPoster: KeyChordPosting {
        func post(keyCode: CGKeyCode, flags: CGEventFlags) {}
    }

    /// Deterministic brain: read the screen, click the row matching `targetLine`,
    /// then finish. Exercises the real loop/registry/surface without LLM variance.
    private struct LabelSeekingBrain: AgentBrain {
        let targetLine: String
        func nextToolCall(task: String, observation: String, history: [String], toolNames: [String]) async throws -> ToolCall {
            if history.contains(where: { $0.hasPrefix("click") }) {
                return ToolCall(name: "finish", arguments: ["summary": "done"])
            }
            for line in observation.split(separator: "\n") where line.contains(targetLine) {
                if let head = line.split(separator: ":").first, head.hasPrefix("e") {
                    return ToolCall(name: "click", arguments: ["element_id": String(head)])
                }
            }
            return ToolCall(name: "read_screen", arguments: [:])
        }
    }
}
