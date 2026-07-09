import Foundation

/// Presses an actionable element that the last `read_screen` surfaced, by its id.
/// Delegates to the routing surface, which performs the AX press (native app) or a
/// trusted CDP click with a risky-action confirmation (browser page).
struct ClickTool: AgentTool {
    let name = "click"
    let risk: RiskTier = .risky
    let surface: CommandActing

    func execute(_ arguments: [String: String]) async throws -> ToolResult {
        guard let id = arguments["element_id"] ?? arguments["id"], !id.isEmpty else {
            throw CommandModeError.malformedToolCall("click needs 'element_id'")
        }
        return await surface.click(id: id)
    }
}

/// Moves keyboard focus to an element (e.g. a text field) before typing.
struct FocusTool: AgentTool {
    let name = "focus"
    let risk: RiskTier = .benign
    let surface: CommandActing

    func execute(_ arguments: [String: String]) async throws -> ToolResult {
        guard let id = arguments["element_id"] ?? arguments["id"], !id.isEmpty else {
            throw CommandModeError.malformedToolCall("focus needs 'element_id'")
        }
        return await surface.focus(id: id)
    }
}
