import Foundation

/// Escape hatch for scriptable apps. Runs an AppleScript source string. Requires
/// the Automation permission — macOS prompts per target app on the first Apple
/// Event (Info.plist carries NSAppleEventsUsageDescription). High-risk.
struct RunAppleScriptTool: AgentTool {
    let name = "run_applescript"
    let risk: RiskTier = .risky

    func execute(_ arguments: [String: String]) async throws -> ToolResult {
        guard let source = arguments["script"], !source.isEmpty else {
            throw CommandModeError.malformedToolCall("run_applescript needs 'script'")
        }
        guard let script = NSAppleScript(source: source) else {
            return ToolResult(output: "invalid AppleScript", isTerminal: false)
        }
        var errorInfo: NSDictionary?
        let output = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "AppleScript error"
            return ToolResult(output: "script error: \(message)", isTerminal: false)
        }
        let text = output.stringValue ?? "ran script"
        return ToolResult(output: String(text.prefix(200)), isTerminal: false)
    }
}
