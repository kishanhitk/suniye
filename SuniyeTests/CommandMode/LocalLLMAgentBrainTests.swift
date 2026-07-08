import XCTest
@testable import Suniye

@MainActor
final class LocalLLMAgentBrainTests: XCTestCase {
    private final class StringSink: @unchecked Sendable {
        var value = ""
    }

    private struct FakeGen: AgentTextGenerator {
        let sink: StringSink
        func generate(instructions: String, userText: String) async throws -> String {
            sink.value = instructions
            return #"{"tool":"open_app","arguments":{"name":"Safari"}}"#
        }
    }

    func testBuildsPromptAndParsesToolCall() async throws {
        let sink = StringSink()
        let brain = LocalLLMAgentBrain(generator: FakeGen(sink: sink))
        let call = try await brain.nextToolCall(
            task: "open safari", observation: "Frontmost app: Finder",
            history: [], toolNames: ["open_app", "finish"]
        )
        XCTAssertEqual(call, ToolCall(name: "open_app", arguments: ["name": "Safari"]))
        XCTAssertTrue(sink.value.contains("open_app"))       // tool list is in the prompt
        XCTAssertTrue(sink.value.lowercased().contains("json"))
    }
}
