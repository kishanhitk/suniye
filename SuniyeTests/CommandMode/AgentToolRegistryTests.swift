import XCTest
@testable import Suniye

final class AgentToolRegistryTests: XCTestCase {
    private struct StubTool: AgentTool {
        let name: String
        let risk: RiskTier
        func execute(_ arguments: [String: String]) async throws -> ToolResult {
            ToolResult(output: "ok", isTerminal: false)
        }
    }

    func testLooksUpRegisteredToolByName() {
        let registry = AgentToolRegistry(tools: [StubTool(name: "open_app", risk: .benign)])
        XCTAssertEqual(registry.tool(named: "open_app")?.name, "open_app")
        XCTAssertNil(registry.tool(named: "nope"))
    }

    func testValidateThrowsOnUnknownTool() {
        let registry = AgentToolRegistry(tools: [StubTool(name: "finish", risk: .benign)])
        XCTAssertThrowsError(try registry.validate(ToolCall(name: "open_app", arguments: [:]))) { error in
            XCTAssertEqual(error as? CommandModeError, .unknownTool("open_app"))
        }
    }

    func testValidatePassesForKnownTool() {
        let registry = AgentToolRegistry(tools: [StubTool(name: "finish", risk: .benign)])
        XCTAssertNoThrow(try registry.validate(ToolCall(name: "finish", arguments: [:])))
    }
}
