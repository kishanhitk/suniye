import Foundation

/// Bridges the agent's `AgentTextGenerator` seam to any main-actor async text
/// call (e.g. `MagicFormatCoordinator.rewrite`). Runs on the main actor.
struct ClosureAgentTextGenerator: AgentTextGenerator {
    let run: (String, String) async throws -> String
    func generate(instructions: String, userText: String) async throws -> String {
        try await run(instructions, userText)
    }
}

/// Bridges the `TextTyping` seam to a main-actor text-insertion call.
struct ClosureTextTyping: TextTyping {
    let run: (String) -> Void
    func type(_ text: String) { run(text) }
}
