import XCTest
@testable import Suniye

/// Response-shape tolerance for the OpenAI-compatible transport. Reasoning models
/// and native function-calling replies send `"content": null`, which used to sink
/// the whole decode as `malformedResponse` — the exact failure seen when driving
/// Command Mode with a remote smart model.
final class ChatCompletionResponseTests: XCTestCase {
    private func extract(_ json: String) throws -> String {
        try ChatCompletionResponse.extractText(from: Data(json.utf8))
    }

    private func assertMalformed(_ error: Error, file: StaticString = #filePath, line: UInt = #line) {
        if case LLMPostProcessorError.malformedResponse = error { return }
        XCTFail("expected malformedResponse, got \(error)", file: file, line: line)
    }

    func testPlainStringContent() throws {
        let text = try extract(#"{"choices":[{"message":{"content":"hello"}}]}"#)
        XCTAssertEqual(text, "hello")
    }

    func testNullContentWithToolCallReconstructsJSON() throws {
        // Model function-called instead of emitting text: content is null, the call
        // lives in tool_calls. We rebuild the {"tool","arguments"} the parser reads.
        let json = #"""
        {"choices":[{"message":{"content":null,"tool_calls":[
          {"function":{"name":"click","arguments":"{\"element_id\":\"e1\"}"}}
        ]}}]}
        """#
        let text = try extract(json)
        XCTAssertEqual(text, #"{"tool":"click","arguments":{"element_id":"e1"}}"#)

        // And it round-trips through the real parser to the right ToolCall.
        let call = try ToolCallParser.parse(text)
        XCTAssertEqual(call, ToolCall(name: "click", arguments: ["element_id": "e1"]))
    }

    func testNullContentNoToolCallStillThrows() {
        XCTAssertThrowsError(try extract(#"{"choices":[{"message":{"content":null}}]}"#)) { assertMalformed($0) }
    }

    func testContentPartsArrayIsJoined() throws {
        let text = try extract(#"{"choices":[{"message":{"content":[{"text":"a"},{"text":"b"}]}}]}"#)
        XCTAssertEqual(text, "a\nb")
    }

    func testMissingChoicesThrows() {
        XCTAssertThrowsError(try extract(#"{"choices":[]}"#)) { assertMalformed($0) }
    }

    func testToolCallWithMissingArgumentsDefaultsToEmptyObject() throws {
        let json = #"{"choices":[{"message":{"content":null,"tool_calls":[{"function":{"name":"read_screen"}}]}}]}"#
        XCTAssertEqual(try extract(json), #"{"tool":"read_screen","arguments":{}}"#)
    }
}
