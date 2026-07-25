import Foundation

/// Looks up tools by name and validates a model's `ToolCall` against the
/// registered set. The registry is the closed action surface of the agent.
struct AgentToolRegistry {
    private let byName: [String: AgentTool]

    init(tools: [AgentTool]) {
        byName = Dictionary(tools.map { ($0.name, $0) }) { first, _ in first }
    }

    /// Sorted for a stable prompt/tool listing.
    var toolNames: [String] { byName.keys.sorted() }

    func tool(named name: String) -> AgentTool? { byName[name] }

    func validate(_ call: ToolCall) throws {
        guard byName[call.name] != nil else { throw CommandModeError.unknownTool(call.name) }
    }
}
