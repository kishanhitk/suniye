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

    // MARK: response stringify (rich results survive)

    func testStringifyDisambiguatesScalars() {
        XCTAssertEqual(BrowserBridge.stringify("hi"), "hi")
        XCTAssertEqual(BrowserBridge.stringify(true), "true")
        XCTAssertEqual(BrowserBridge.stringify(false), "false")
        XCTAssertEqual(BrowserBridge.stringify(42), "42")
        XCTAssertEqual(BrowserBridge.stringify(["a", "b"]), #"["a","b"]"#)
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
