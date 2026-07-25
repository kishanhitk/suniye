import XCTest
@testable import Suniye

final class AgentBrainParsingTests: XCTestCase {
    func testParsesCleanJSON() throws {
        let call = try ToolCallParser.parse(#"{"tool":"open_app","arguments":{"name":"Safari"}}"#)
        XCTAssertEqual(call, ToolCall(name: "open_app", arguments: ["name": "Safari"]))
    }

    func testParsesJSONWrappedInProseAndFences() throws {
        let raw = "Sure!\n```json\n{\"tool\":\"finish\",\"arguments\":{}}\n```\n"
        XCTAssertEqual(try ToolCallParser.parse(raw), ToolCall(name: "finish", arguments: [:]))
    }

    func testThrowsOnNoJSON() {
        XCTAssertThrowsError(try ToolCallParser.parse("I don't know")) { error in
            XCTAssertEqual(error as? CommandModeError, .malformedToolCall("no JSON object found"))
        }
    }

    /// Small models sometimes drop the `arguments` wrapper and put the arg at the
    /// top level. The parser recovers the intent (observed in the command eval).
    func testParsesFlattenedTopLevelArguments() throws {
        let call = try ToolCallParser.parse(#"{"tool":"focus","element_id":"e1"}"#)
        XCTAssertEqual(call, ToolCall(name: "focus", arguments: ["element_id": "e1"]))
    }

    /// A `}` inside a string value must not close the object early.
    func testBraceInsideStringDoesNotTruncate() throws {
        let call = try ToolCallParser.parse(#"{"tool":"type_text","arguments":{"text":"meet at 3} today"}}"#)
        XCTAssertEqual(call, ToolCall(name: "type_text", arguments: ["text": "meet at 3} today"]))
    }
}
