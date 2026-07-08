import Foundation

/// Text-in/text-out seam over the existing on-device LLM (adapts
/// `MagicFormatCoordinator.rewrite` / a provider's `generate`).
@MainActor
protocol AgentTextGenerator {
    func generate(instructions: String, userText: String) async throws -> String
}

/// Increment-1 brain: reuses the already-local LLM as a tool-caller by prompting
/// for a single JSON tool call and parsing it. A later increment swaps this for a
/// dedicated agent model with native tool-calling.
struct LocalLLMAgentBrain: AgentBrain {
    let generator: AgentTextGenerator

    func nextToolCall(task: String, observation: String, history: [String], toolNames: [String]) async throws -> ToolCall {
        let instructions = """
        You operate a Mac by emitting exactly ONE tool call as a JSON object, and nothing else:
        {"tool":"<name>","arguments":{...}}
        Tools — use these EXACT argument keys:
        - open_app {"name":"<app name>"}   launch or focus an app (e.g. "Safari", "System Settings")
        - type_text {"text":"<text>"}      type into the focused field
        - read_screen {}                   look at the current screen
        - finish {"summary":"<result>"}    call this THE MOMENT the task is complete
        Rules:
        - Do the task in the FEWEST steps. Most tasks are ONE action, then finish.
        - After an action succeeds, your NEXT call MUST be finish. NEVER repeat an action.
        - "Current screen" is context only — never type its text back.
        Recent steps (oldest first, most recent last):
        \(history.suffix(6).joined(separator: "\n"))
        Current screen:
        \(observation)
        """
        let raw = try await generator.generate(instructions: instructions, userText: task)
        return try ToolCallParser.parse(raw)
    }
}
