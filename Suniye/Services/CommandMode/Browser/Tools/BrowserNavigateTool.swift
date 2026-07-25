import Foundation

/// Navigates the active browser tab to a URL via the extension (`chrome.tabs.update`)
/// and waits for the page to finish loading. Reliable, unlike typing a URL into
/// whatever field happens to be focused — the failure mode that sent the agent to
/// a search page instead of the destination. Benign (a navigation, not a submit).
struct BrowserNavigateTool: AgentTool {
    let name = "browser_navigate"
    let risk: RiskTier = .benign
    let transport: BrowserTransport

    func execute(_ arguments: [String: String]) async throws -> ToolResult {
        guard let url = arguments["url"], !url.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw CommandModeError.malformedToolCall("browser_navigate needs 'url'")
        }
        do {
            // Page loads can take a while — allow more than the default timeout.
            let response = try await transport.send(tool: "navigate", args: ["url": url], timeout: 30)
            guard response.ok else {
                return ToolResult(output: response.errorMessage ?? "couldn't navigate", isTerminal: false)
            }
            return ToolResult(output: response.result["output"] ?? "navigated to \(url)", isTerminal: false)
        } catch {
            return ToolResult(output: "browser not connected", isTerminal: false)
        }
    }
}
