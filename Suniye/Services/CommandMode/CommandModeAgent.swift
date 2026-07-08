import Foundation

/// The agent's perception: the current screen rendered as text.
@MainActor
protocol ScreenReading {
    func readScreen() async -> String
}

/// One completed turn of the loop, surfaced to the UI (live log) and tests.
struct AgentStep {
    let toolCall: ToolCall
    let result: ToolResult?
    let error: String?
}

/// Drives see → decide → act → observe until a terminal tool, the step cap, a
/// stall (identical screen with no progress), or cancellation. Main-actor isolated
/// so it drives the app's @MainActor services (LLM, text insertion, indicator)
/// without cross-actor hops; awaits inside the loop yield the main actor, so the
/// UI stays responsive. The kill switch (`cancel`) is race-free on the main actor.
@MainActor
final class CommandModeAgent {
    private let brain: AgentBrain
    private let registry: AgentToolRegistry
    private let screenReader: ScreenReading
    private let maxSteps: Int
    private let onStep: ((AgentStep) -> Void)?
    private var cancelled = false

    init(brain: AgentBrain,
         registry: AgentToolRegistry,
         screenReader: ScreenReading,
         maxSteps: Int = 12,
         onStep: ((AgentStep) -> Void)? = nil) {
        self.brain = brain
        self.registry = registry
        self.screenReader = screenReader
        self.maxSteps = maxSteps
        self.onStep = onStep
    }

    func cancel() { cancelled = true }

    /// Returns a human-readable final summary.
    func run(task: String) async -> String {
        var history: [String] = []
        var lastObservation = ""

        for _ in 0..<maxSteps {
            if cancelled { return "Cancelled." }

            let observation = await screenReader.readScreen()
            let stalled = observation == lastObservation && !history.isEmpty
            lastObservation = observation

            let call: ToolCall
            do {
                call = try await brain.nextToolCall(
                    task: task, observation: observation,
                    history: history, toolNames: registry.toolNames
                )
            } catch {
                onStep?(AgentStep(toolCall: ToolCall(name: "?", arguments: [:]), result: nil, error: String(describing: error)))
                return "Stopped: the model didn't return a valid action."
            }

            guard let tool = registry.tool(named: call.name) else {
                onStep?(AgentStep(toolCall: call, result: nil, error: "unknown tool"))
                history.append("tried unknown tool \(call.name)")
                if stalled { return "Stopped: stuck." }
                continue
            }

            do {
                let result = try await tool.execute(call.arguments)
                onStep?(AgentStep(toolCall: call, result: result, error: nil))
                history.append("\(call.name) → \(result.output)")
                if result.isTerminal { return result.output }
            } catch {
                onStep?(AgentStep(toolCall: call, result: nil, error: String(describing: error)))
                history.append("\(call.name) failed: \(error)")
            }
        }
        return "Stopped: reached the step limit."
    }
}
