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
}
