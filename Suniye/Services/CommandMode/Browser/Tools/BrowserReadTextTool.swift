import Foundation

/// Reads the rendered, visible text of the active browser tab (the page's
/// `innerText`) via the connected extension — the capability the OS accessibility
/// tree can't provide on React/SPA sites, and the fix for "check my order / price
/// on this site". Read-only.
struct BrowserReadTextTool: AgentTool {
    let name = "browser_read_text"
    let risk: RiskTier = .read
    let transport: BrowserTransport

    func execute(_ arguments: [String: String]) async throws -> ToolResult {
        var args: [String: String] = [:]
        if let ref = arguments["ref"], !ref.isEmpty { args["ref"] = ref }
        do {
            let response = try await transport.send(tool: "read_text", args: args)
            guard response.ok else {
                // Soft failure — the agent can retry or finish, not abort the run.
                return ToolResult(output: response.errorMessage ?? "couldn't read the page", isTerminal: false)
            }
            let text = response.result["text"] ?? ""
            return ToolResult(output: text.isEmpty ? "the page had no readable text" : text, isTerminal: false)
        } catch {
            return ToolResult(output: "browser not connected", isTerminal: false)
        }
    }
}
