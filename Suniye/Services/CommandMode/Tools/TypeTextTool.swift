import Foundation

/// Types text into the focused field. Seam adapts to `TextInsertionService`.
protocol TextTyping {
    func type(_ text: String)
}

struct TypeTextTool: AgentTool {
    let name = "type_text"
    let risk: RiskTier = .benign
    let typer: TextTyping

    func execute(_ arguments: [String: String]) async throws -> ToolResult {
        guard let text = arguments["text"] else {
            throw CommandModeError.malformedToolCall("type_text needs 'text'")
        }
        typer.type(text)
        return ToolResult(output: "typed \(text.count) chars", isTerminal: false)
    }
}
