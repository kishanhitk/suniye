import AppKit
import XCTest
@testable import Suniye

/// LIVE-SITE end-to-end tests against real websites (Flipkart), using the user's
/// already-logged-in Chrome via the real extension + BrowserBridge. Opt-in only
/// (`scripts/e2e_browser_command.sh --flipkart`) — never part of the default
/// green suite: real sites are non-deterministic (A/B layouts, login walls, bot
/// checks), so the hard assertion is PERCEPTION (our DOM snapshot surfaces the
/// real page — the whole reason the extension exists), and the multi-step orders
/// flow is a tolerant, TRACED run recorded to /tmp for inspection.
///
/// Safety: risky clicks are DECLINED here (never auto-approved on a live site),
/// and the agent never types — so it can navigate and read, never buy.
@MainActor
final class BrowserLiveSiteE2ETests: XCTestCase {
    private static let gateURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".suniye-browser-e2e.json")

    private var bridge: BrowserBridge!
    private var gate: [String: Any] = [:]
    private var declinedRisky: [String] = []

    override func setUp() async throws {
        guard let data = try? Data(contentsOf: Self.gateURL),
              let cfg = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              cfg["enabled"] as? Bool == true else {
            throw XCTSkip("Browser E2E is off.")
        }
        gate = cfg
        guard cfg["site"] != nil else {
            throw XCTSkip("Live-site tier off — run scripts/e2e_browser_command.sh --flipkart")
        }

        let pairingURL = BrowserExtensionInstaller.installedURL.appendingPathComponent("pairing.json")
        guard let pdata = try? Data(contentsOf: pairingURL),
              let pairing = try? JSONSerialization.jsonObject(with: pdata) as? [String: Any],
              let port = (pairing["port"] as? Int).map(UInt16.init),
              let token = pairing["token"] as? String else {
            throw XCTSkip("No paired extension.")
        }
        bridge = BrowserBridge(config: BrowserBridgeConfig(portCandidates: [port], token: token))
        do { try await bridge.start() } catch { throw XCTSkip("Quit Suniye Preview first. \(error)") }

        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-a", "Google Chrome"]
        try open.run(); open.waitUntilExit()
        guard await waitUntil(45, { await self.bridge.isConnected }) else {
            throw XCTSkip("Extension never connected.")
        }
    }

    override func tearDown() async throws {
        await bridge?.stop()
        bridge = nil
    }

    // MARK: - example.com — deterministic real-site actuation (the 100% anchor).

    func testExampleDotComReadAndClick() async throws {
        let surface = makeSurface()
        let nav = try await bridge.send(tool: "navigate", args: ["url": "https://example.com"], timeout: 30)
        XCTAssertTrue(nav.ok)

        let text = ((try? await bridge.send(tool: "read_text", args: [:], timeout: 12))?.result["text"] ?? "")
        XCTAssertTrue(text.contains("Example Domain"), "read_text must return the page content, got: \(text.prefix(200))")

        let observation = await surface.readScreen()
        XCTAssertEqual(surface.activeKind, .browser)
        // example.com has exactly one actionable element — a link (currently
        // "Learn more"; historically "More information…"). Take the sole link so
        // the test survives IANA's copy changes.
        let linkRef = try XCTUnwrap(ref(in: observation, role: "link"),
                                    "example.com's link must be snapshotted:\n\(observation)")
        let clicked = await surface.click(id: linkRef)
        XCTAssertEqual(clicked.output, "clicked \(linkRef)")

        // The link navigates off example.com (to iana.org) — confirm via tab URL.
        var landed = false
        for _ in 0..<24 {
            let url = (try? await bridge.send(tool: "read_text", args: [:], timeout: 10))?.result["url"] ?? ""
            if url.contains("iana.org") || (!url.contains("example.com") && url.hasPrefix("http")) { landed = true; break }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        XCTAssertTrue(landed, "clicking the link must navigate away from example.com")
    }

    // MARK: - Wikipedia — real multi-step search actuation (smart model).

    func testWikipediaSearchOpensArticle() async throws {
        guard let llmURL = gate["llm_url"] as? String, !llmURL.isEmpty else {
            throw XCTSkip("needs the LLM tier — add --llm")
        }
        let surface = makeSurface()
        let nav = try await bridge.send(tool: "navigate", args: ["url": "https://en.wikipedia.org/wiki/Main_Page"], timeout: 30)
        XCTAssertTrue(nav.ok)

        let (result, trace) = await runAgent(surface, task: "search Wikipedia for Claude Shannon and open his article", maxSteps: 12)
        try? trace.write(toFile: "/tmp/suniye-wikipedia.txt", atomically: true, encoding: .utf8)

        let text = ((try? await bridge.send(tool: "read_text", args: [:], timeout: 12))?.result["text"] ?? "").lowercased()
        XCTAssertEqual(result.invalidActions, 0, "loop/parser must stay valid on live Wikipedia")
        XCTAssertTrue(text.contains("information theory") || text.contains("shannon"),
                      "should have opened the Claude Shannon article:\n\(text.prefix(300))")
    }

    // MARK: - Perception (HARD assertion): the real Flipkart DOM is snapshottable.

    func testFlipkartHomepageIsPerceivable() async throws {
        let surface = makeSurface()
        let nav = try await bridge.send(tool: "navigate", args: ["url": "https://www.flipkart.com"], timeout: 30)
        XCTAssertTrue(nav.ok, "navigate failed: \(nav.errorMessage ?? "?")")

        let observation = await surface.readScreen()
        XCTAssertEqual(surface.activeKind, .browser)
        // This is the whole point of the extension: the OS accessibility tree saw
        // almost nothing on Flipkart's SPA; the DOM snapshot must see a real page.
        XCTAssertTrue(observation.contains("Actionable elements"), observation)
        XCTAssertTrue(observation.lowercased().contains("search"),
                      "the Flipkart search field must be surfaced:\n\(observation.prefix(800))")
        let rowCount = observation.split(separator: "\n").filter { $0.hasPrefix("e") }.count
        XCTAssertGreaterThan(rowCount, 10, "a real page should surface many actionable elements, got \(rowCount)")
        try? observation.write(toFile: "/tmp/suniye-flipkart-home.txt", atomically: true, encoding: .utf8)
    }

    // MARK: - Orders navigation (tolerant + TRACED): the real account→orders flow.

    func testFlipkartOrdersNavigation() async throws {
        guard let llmURL = gate["llm_url"] as? String, !llmURL.isEmpty else {
            throw XCTSkip("orders flow needs the LLM tier — add --llm")
        }
        let surface = makeSurface()
        let nav = try await bridge.send(tool: "navigate", args: ["url": "https://www.flipkart.com"], timeout: 30)
        XCTAssertTrue(nav.ok)

        let generator = FixtureLiveLLM(base: llmURL, model: gate["llm_model"] as? String ?? "local",
                                       key: gate["llm_key"] as? String)
        let trace = TraceRecorder()
        let registry = AgentToolRegistry(tools: [
            ReadScreenTool(reader: surface),
            ClickTool(surface: surface),
            FocusTool(surface: surface),
            PressKeysTool(surface: surface),
            BrowserReadTextTool(transport: bridge),
            BrowserNavigateTool(transport: bridge),
            FinishTool(),
        ])
        let agent = CommandModeAgent(
            brain: LocalLLMAgentBrain(generator: generator),
            registry: registry, screenReader: surface, maxSteps: 14,
            onStep: { step in
                trace.add("\(step.toolCall.name) \(step.toolCall.arguments) -> \(step.result?.output.prefix(160) ?? Substring(step.error ?? "-"))")
            }
        )
        let result = await agent.run(task: "open my orders and tell me the status of my most recent order")
        trace.add("=> \(result.outcome) steps=\(result.stepCount) invalid=\(result.invalidActions) summary=\(result.summary.prefix(200))")

        let finalText = ((try? await bridge.send(tool: "read_text", args: [:], timeout: 12))?.result["text"] ?? "").lowercased()
        trace.add("final-url-text: \(finalText.prefix(200))")
        try? trace.dump().write(toFile: "/tmp/suniye-flipkart-orders.txt", atomically: true, encoding: .utf8)

        // A login wall (logged out on Chrome) is an environment condition, not a
        // failure — skip so the tier stays meaningful.
        if finalText.contains("enter email") || finalText.contains("login") && finalText.contains("otp") {
            throw XCTSkip("Flipkart showed a login wall on Chrome — log in there to exercise the orders flow.")
        }
        // Meaningful invariants that DON'T depend on the 2B nailing the whole flow:
        XCTAssertEqual(result.invalidActions, 0, "the loop/parser must stay valid on real page content")
        XCTAssertTrue(declinedRisky.allSatisfy { !$0.lowercased().contains("buy") && !$0.lowercased().contains("pay") },
                      "must never have proposed a purchase")
        // Best-effort success signal (logged, not a hard gate given model limits):
        let reachedOrders = finalText.contains("order") || result.summary.lowercased().contains("order")
        trace.add("reachedOrders=\(reachedOrders)")
        try? trace.dump().write(toFile: "/tmp/suniye-flipkart-orders.txt", atomically: true, encoding: .utf8)
        print("FLIPKART-ORDERS outcome=\(result.outcome) reachedOrders=\(reachedOrders) invalid=\(result.invalidActions) — trace: /tmp/suniye-flipkart-orders.txt")
    }

    // MARK: - Helpers

    private func ref(in observation: String, labelledContaining needle: String) -> String? {
        for line in observation.split(separator: "\n") where line.contains(needle) {
            if let head = line.split(separator: ":").first, head.hasPrefix("e") { return String(head) }
        }
        return nil
    }

    private func ref(in observation: String, role: String) -> String? {
        for line in observation.split(separator: "\n") where line.contains(": \(role) ") {
            if let head = line.split(separator: ":").first, head.hasPrefix("e") { return String(head) }
        }
        return nil
    }

    private func runAgent(_ surface: RoutingCommandSurface, task: String, maxSteps: Int) async -> (AgentRunResult, String) {
        let generator = FixtureLiveLLM(base: gate["llm_url"] as? String ?? "", model: gate["llm_model"] as? String ?? "local",
                                       key: gate["llm_key"] as? String)
        let trace = TraceRecorder()
        let registry = AgentToolRegistry(tools: [
            ReadScreenTool(reader: surface), ClickTool(surface: surface), FocusTool(surface: surface),
            TypeTextTool(surface: surface), PressKeysTool(surface: surface),
            BrowserReadTextTool(transport: bridge), BrowserNavigateTool(transport: bridge), FinishTool(),
        ])
        let agent = CommandModeAgent(
            brain: LocalLLMAgentBrain(generator: generator), registry: registry,
            screenReader: surface, maxSteps: maxSteps,
            onStep: { step in trace.add("\(step.toolCall.name) \(step.toolCall.arguments) -> \(step.result?.output.prefix(160) ?? Substring(step.error ?? "-"))") }
        )
        let result = await agent.run(task: task)
        trace.add("=> \(result.outcome) steps=\(result.stepCount) invalid=\(result.invalidActions) summary=\(result.summary.prefix(200))")
        return (result, trace.dump())
    }

    private func makeSurface() -> RoutingCommandSurface {
        RoutingCommandSurface(
            native: AXTreeReader(),
            browser: BrowserSnapshotReader(transport: bridge),
            transport: bridge,
            nativeTyper: NoopTyper(),
            keyPoster: NoopKeyPoster(),
            frontmostBundleID: { "com.google.Chrome" },
            isBrowser: { _ in true },
            confirmRisky: { [weak self] description in
                self?.declinedRisky.append(description); return false // never auto-approve on a live site
            }
        )
    }

    private func waitUntil(_ timeout: TimeInterval, _ condition: @escaping () async -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return await condition()
    }

    private struct NoopTyper: TextTyping { func type(_ text: String) {} }
    private struct NoopKeyPoster: KeyChordPosting { func post(keyCode: CGKeyCode, flags: CGEventFlags) {} }

    private final class TraceRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [String] = []
        func add(_ line: String) { lock.lock(); lines.append(line); lock.unlock() }
        func dump() -> String { lock.lock(); defer { lock.unlock() }; return lines.joined(separator: "\n") }
    }

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
}
