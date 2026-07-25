import Foundation

/// Returns the current screen as text. Also auto-invoked by the loop each turn;
/// exposed as a tool so the model can re-read on demand.
struct ReadScreenTool: AgentTool {
    let name = "read_screen"
    let risk: RiskTier = .read
    let reader: ScreenReading

    func execute(_ arguments: [String: String]) async throws -> ToolResult {
        ToolResult(output: await reader.readScreen(), isTerminal: false)
    }
}
