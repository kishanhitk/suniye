import Foundation

/// Terminal tool: the agent calls this when the task is complete.
struct FinishTool: AgentTool {
    let name = "finish"
    let risk: RiskTier = .benign

    func execute(_ arguments: [String: String]) async throws -> ToolResult {
        ToolResult(output: arguments["summary"] ?? "done", isTerminal: true)
    }
}
