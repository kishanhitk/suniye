import ApplicationServices

/// Presses an actionable element that the last `read_screen` surfaced, by its id.
struct ClickTool: AgentTool {
    let name = "click"
    let risk: RiskTier = .risky
    let resolver: ElementResolving

    func execute(_ arguments: [String: String]) async throws -> ToolResult {
        guard let id = arguments["element_id"] ?? arguments["id"], !id.isEmpty else {
            throw CommandModeError.malformedToolCall("click needs 'element_id'")
        }
        guard let element = resolver.element(forId: id) else {
            return ToolResult(output: "no element \(id) — call read_screen first", isTerminal: false)
        }
        let status = AXUIElementPerformAction(element, kAXPressAction as CFString)
        return ToolResult(output: status == .success ? "clicked \(id)" : "click \(id) failed (ax \(status.rawValue))", isTerminal: false)
    }
}

/// Moves keyboard focus to an element (e.g. a text field) before typing.
struct FocusTool: AgentTool {
    let name = "focus"
    let risk: RiskTier = .benign
    let resolver: ElementResolving

    func execute(_ arguments: [String: String]) async throws -> ToolResult {
        guard let id = arguments["element_id"] ?? arguments["id"], !id.isEmpty else {
            throw CommandModeError.malformedToolCall("focus needs 'element_id'")
        }
        guard let element = resolver.element(forId: id) else {
            return ToolResult(output: "no element \(id) — call read_screen first", isTerminal: false)
        }
        let status = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        return ToolResult(output: status == .success ? "focused \(id)" : "focus \(id) failed", isTerminal: false)
    }
}
