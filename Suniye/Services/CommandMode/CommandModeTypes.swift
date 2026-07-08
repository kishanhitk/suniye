import Foundation

/// One action the agent chooses to perform this step.
struct ToolCall: Equatable {
    let name: String
    let arguments: [String: String]
}

/// The outcome of running a tool. `isTerminal` ends the agent loop (e.g. `finish`).
struct ToolResult: Equatable {
    let output: String
    let isTerminal: Bool
}

/// How dangerous an action is — drives the confirmation gates in a later increment.
enum RiskTier {
    case read    // reads state only
    case benign  // reversible / low-impact (open app, type in a field)
    case risky   // irreversible or high-impact (send, delete, run script)
}

/// A capability the agent can invoke. The registered set is the entire surface of
/// what the agent can do — nothing outside it is possible.
protocol AgentTool {
    var name: String { get }
    var risk: RiskTier { get }
    func execute(_ arguments: [String: String]) async throws -> ToolResult
}

enum CommandModeError: Error, Equatable {
    case unknownTool(String)
    case malformedToolCall(String)
    case stepLimitReached
    case cancelled
    case noProgress
}
