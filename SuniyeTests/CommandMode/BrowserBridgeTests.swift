import XCTest
@testable import Suniye

@MainActor
final class BrowserBridgeTests: XCTestCase {
    // MARK: doubles

    private struct FakeBrowserTransport: BrowserTransport {
        let connected: Bool
        let result: BrowserResponse?   // nil → throw notConnected
        var isConnected: Bool { get async { connected } }
        func send(tool: String, args: [String: String], timeout: TimeInterval) async throws -> BrowserResponse {
            guard let result else { throw BrowserBridgeError.notConnected }
            return result
        }
    }

    private final class CapturingGenerator: AgentTextGenerator {
        private(set) var captured = ""
        let response: String
        init(response: String) { self.response = response }
        func generate(instructions: String, userText: String) async throws -> String {
            captured = instructions
            return response
        }
    }

    // MARK: browser_read_text tool

    func testReadTextReturnsPageText() async throws {
        let transport = FakeBrowserTransport(connected: true, result: .success(["text": "Order delivered on Tuesday."]))
        let result = try await BrowserReadTextTool(transport: transport).execute([:])
        XCTAssertEqual(result.output, "Order delivered on Tuesday.")
        XCTAssertFalse(result.isTerminal)
    }

    func testReadTextSoftFailsWhenDisconnected() async throws {
        let transport = FakeBrowserTransport(connected: false, result: nil)
        let result = try await BrowserReadTextTool(transport: transport).execute([:])
        XCTAssertEqual(result.output, "browser not connected")
        XCTAssertFalse(result.isTerminal, "a disconnected browser must not abort the run")
    }

    func testReadTextSoftFailsOnToolError() async throws {
        let transport = FakeBrowserTransport(
            connected: true,
            result: BrowserResponse(ok: false, result: [:], errorCode: "no_tab", errorMessage: "no active browser tab")
        )
        let result = try await BrowserReadTextTool(transport: transport).execute([:])
        XCTAssertEqual(result.output, "no active browser tab")
    }

    func testReadTextForwardsRefArgument() async throws {
        // A `ref` arg is forwarded; empty text yields a clear message, not "".
        let transport = FakeBrowserTransport(connected: true, result: .success(["text": ""]))
        let result = try await BrowserReadTextTool(transport: transport).execute(["ref": "e3"])
        XCTAssertEqual(result.output, "the page had no readable text")
    }

    // MARK: browser_navigate tool

    func testNavigateForwardsUrl() async throws {
        let transport = FakeBrowserTransport(connected: true, result: .success(["output": "navigated to https://example.com"]))
        let result = try await BrowserNavigateTool(transport: transport).execute(["url": "example.com"])
        XCTAssertEqual(result.output, "navigated to https://example.com")
        XCTAssertFalse(result.isTerminal)
    }

    func testNavigateRejectsMissingUrl() async {
        let transport = FakeBrowserTransport(connected: true, result: .success([:]))
        do {
            _ = try await BrowserNavigateTool(transport: transport).execute([:])
            XCTFail("expected malformedToolCall")
        } catch {
            XCTAssertEqual(error as? CommandModeError, .malformedToolCall("browser_navigate needs 'url'"))
        }
    }

    func testNavigateSoftFailsWhenDisconnected() async throws {
        let transport = FakeBrowserTransport(connected: false, result: nil)
        let result = try await BrowserNavigateTool(transport: transport).execute(["url": "example.com"])
        XCTAssertEqual(result.output, "browser not connected")
    }

    // MARK: response stringify (rich results survive)

    func testStringifyDisambiguatesScalars() {
        XCTAssertEqual(BrowserBridge.stringify("hi"), "hi")
        XCTAssertEqual(BrowserBridge.stringify(true), "true")
        XCTAssertEqual(BrowserBridge.stringify(false), "false")
        XCTAssertEqual(BrowserBridge.stringify(42), "42")
        XCTAssertEqual(BrowserBridge.stringify(["a", "b"]), #"["a","b"]"#)
    }

    // MARK: snapshot render + routing surface (Phase C)

    private final class ScriptedBrowserTransport: BrowserTransport, @unchecked Sendable {
        var connected = true
        var responses: [String: BrowserResponse] = [:]
        private(set) var sent: [(tool: String, args: [String: String])] = []
        var isConnected: Bool { get async { connected } }
        func send(tool: String, args: [String: String], timeout: TimeInterval) async throws -> BrowserResponse {
            sent.append((tool, args))
            return responses[tool] ?? BrowserResponse.success([:])
        }
    }

    private struct NoopTyper: TextTyping { func type(_ text: String) {} }

    func testSnapshotSummaryMatchesNativeShape() {
        let text = BrowserSnapshotReader.summary(url: "https://x.com", title: "Cart",
                                                 rows: ["e0: button \"Buy\"", "e1: link \"Home\""])
        XCTAssertTrue(text.hasPrefix("Frontmost app: Google Chrome — Cart"))
        XCTAssertTrue(text.contains("URL: https://x.com"))
        XCTAssertTrue(text.contains("Actionable elements — reference an id with click/focus:"))
        XCTAssertTrue(text.contains("e0: button \"Buy\""))
    }

    private struct RecordingKeyPoster: KeyChordPosting {
        let sink: KeySink
        func post(keyCode: CGKeyCode, flags: CGEventFlags) { sink.codes.append(keyCode) }
    }
    final class KeySink: @unchecked Sendable { var codes: [CGKeyCode] = [] }

    private func browserSurface(_ transport: ScriptedBrowserTransport,
                                keySink: KeySink = KeySink(),
                                confirm: @escaping @MainActor (String) async -> Bool) -> RoutingCommandSurface {
        RoutingCommandSurface(
            native: AXTreeReader(), browser: BrowserSnapshotReader(transport: transport), transport: transport,
            nativeTyper: NoopTyper(), keyPoster: RecordingKeyPoster(sink: keySink),
            frontmostBundleID: { "com.google.Chrome" },
            isBrowser: { _ in true }, confirmRisky: confirm
        )
    }

    func testRoutesToBrowserAndConfirmsConsequentialClick() async {
        let transport = ScriptedBrowserTransport()
        transport.responses["snapshot"] = .success(["rows": #"[{"ref":"e0","role":"button","label":"Add to cart"}]"#, "url": "https://x", "title": "X"])
        transport.responses["click"] = .success(["output": "clicked e0"])
        var confirmed: [String] = []
        let surface = browserSurface(transport) { description in confirmed.append(description); return true }

        let observation = await surface.readScreen()
        XCTAssertEqual(surface.activeKind, .browser)
        XCTAssertTrue(observation.contains(#"e0: button "Add to cart""#))

        let result = await surface.click(id: "e0")
        XCTAssertEqual(result.output, "clicked e0")
        XCTAssertEqual(confirmed.count, 1, "\"Add to cart\" is consequential → must confirm")
        XCTAssertTrue(transport.sent.contains { $0.tool == "click" && $0.args["ref"] == "e0" })
    }

    func testConsequentialClickCancelledWhenUserDeclines() async {
        let transport = ScriptedBrowserTransport()
        transport.responses["snapshot"] = .success(["rows": #"[{"ref":"e0","role":"button","label":"Place order"}]"#])
        let surface = browserSurface(transport) { _ in false } // user declines
        _ = await surface.readScreen()
        let result = await surface.click(id: "e0")
        XCTAssertTrue(result.output.contains("declined"))
        XCTAssertFalse(transport.sent.contains { $0.tool == "click" }, "a declined action must not reach the page")
    }

    func testPressKeysRoutesPageKeysToBrowserAndChordsNative() async {
        let transport = ScriptedBrowserTransport()
        transport.responses["snapshot"] = .success(["rows": #"[{"ref":"e0","role":"searchfield","label":"Search"}]"#])
        transport.responses["press"] = .success(["output": "pressed enter"])
        let sink = KeySink()
        let surface = browserSurface(transport, keySink: sink) { _ in true }
        _ = await surface.readScreen() // activate browser surface

        // Enter acts on the PAGE → trusted CDP key via the extension.
        let enter = await surface.pressKeys("Return")
        XCTAssertEqual(enter.output, "pressed enter")
        XCTAssertTrue(transport.sent.contains { $0.tool == "press" && $0.args["keys"] == "enter" })

        // cmd+t targets the browser APP → native CGEvent path.
        _ = await surface.pressKeys("cmd+t")
        XCTAssertEqual(sink.codes, [17])
        XCTAssertFalse(transport.sent.contains { $0.tool == "press" && $0.args["keys"] == "cmd+t" })
    }

    // MARK: prompt history rendering (large tool outputs must not ride every prompt)

    func testRenderHistoryTruncatesOlderEntriesKeepsLatest() {
        let bigOld = "read: " + String(repeating: "x", count: 1000)
        let bigNew = "page: " + String(repeating: "y", count: 1000)
        let rendered = LocalLLMAgentBrain.renderHistory([bigOld, "clicked e1", bigNew], keep: 6, olderCap: 50, latestCap: 2000)
        let lines = rendered.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 3)
        XCTAssertLessThanOrEqual(lines[0].count, 52, "older entries are truncated")
        XCTAssertTrue(lines[0].hasSuffix("…"))
        XCTAssertEqual(lines[1], "clicked e1")
        XCTAssertEqual(lines[2], bigNew, "the latest entry is kept whole (the model may need to quote it)")
    }

    func testPlainLinkClickSkipsConfirmation() async {
        let transport = ScriptedBrowserTransport()
        transport.responses["snapshot"] = .success(["rows": #"[{"ref":"e0","role":"link","label":"Home"}]"#])
        transport.responses["click"] = .success(["output": "clicked e0"])
        var confirmCount = 0
        let surface = browserSurface(transport) { _ in confirmCount += 1; return true }
        _ = await surface.readScreen()
        _ = await surface.click(id: "e0")
        XCTAssertEqual(confirmCount, 0, "navigating a link is not a risky action")
    }

    // MARK: toolNames-driven prompt

    func testPromptIncludesBrowserToolOnlyWhenRegistered() async throws {
        let generator = CapturingGenerator(response: #"{"tool":"finish","arguments":{}}"#)
        let brain = LocalLLMAgentBrain(generator: generator)

        _ = try await brain.nextToolCall(task: "x", observation: "obs", history: [], toolNames: ["read_screen", "finish"])
        XCTAssertFalse(generator.captured.contains("browser_read_text"))
        XCTAssertFalse(generator.captured.contains("A web browser is connected"))

        _ = try await brain.nextToolCall(task: "x", observation: "obs", history: [],
                                         toolNames: ["read_screen", "browser_read_text", "finish"])
        XCTAssertTrue(generator.captured.contains("browser_read_text"))
        XCTAssertTrue(generator.captured.contains("A web browser is connected"))
    }
}
