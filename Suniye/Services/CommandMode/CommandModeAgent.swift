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

/// Why the loop ended. Mapped to the analytics `CommandOutcome` in AppState so
/// the agent stays free of the telemetry vocabulary.
enum AgentOutcome: Equatable {
    /// A terminal tool (e.g. `finish`) ran.
    case completed
    /// Repeat-guard fired — the model re-issued an action instead of finishing.
    case stalled
    /// Ran out of steps.
    case stepLimit
    /// `cancel()` was called (Esc kill-switch).
    case cancelled
    /// The model never returned a valid, parseable action.
    case brainFailure
}

/// The result of one agent run: the human-readable summary plus the counts and
/// terminal state the caller emits as `CommandMetrics`.
struct AgentRunResult: Equatable {
    let summary: String
    let outcome: AgentOutcome
    /// Loop turns executed (perceive → decide → act cycles).
    let stepCount: Int
    /// Tools that actually executed (successful `execute` calls).
    let toolInvocations: Int
    /// Times the brain returned an unparseable / unknown action.
    let invalidActions: Int
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
    /// How many times to ask the brain for one step before giving up. Transient
    /// failures — a dropped API connection, a timeout, or the model replying in
    /// prose (no tool) — shouldn't abort a whole task, so we retry.
    private let maxBrainAttempts: Int
    /// Backoff between brain attempts (0 in tests).
    private let brainRetryDelay: TimeInterval
    private let onStep: ((AgentStep) -> Void)?
    private var cancelled = false

    init(brain: AgentBrain,
         registry: AgentToolRegistry,
         screenReader: ScreenReading,
         maxSteps: Int = 50,
         maxBrainAttempts: Int = 3,
         brainRetryDelay: TimeInterval = 0.4,
         onStep: ((AgentStep) -> Void)? = nil) {
        self.brain = brain
        self.registry = registry
        self.screenReader = screenReader
        self.maxSteps = maxSteps
        self.maxBrainAttempts = max(1, maxBrainAttempts)
        self.brainRetryDelay = brainRetryDelay
        self.onStep = onStep
    }

    func cancel() { cancelled = true }

    /// Ask the brain for the next tool call, retrying transient failures (network
    /// drop, timeout, or a non-tool/malformed reply) with a short backoff. Throws
    /// the last error only after every attempt is exhausted.
    private func nextToolCallWithRetries(task: String, observation: String, history: [String]) async throws -> ToolCall {
        var lastError: Error?
        for attempt in 1...maxBrainAttempts {
            if cancelled { break }
            if attempt > 1, brainRetryDelay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(brainRetryDelay * 1_000_000_000))
            }
            do {
                return try await brain.nextToolCall(
                    task: task, observation: observation,
                    history: history, toolNames: registry.toolNames
                )
            } catch {
                lastError = error
                AppLogger.shared.log(.warning, "command brain attempt \(attempt)/\(maxBrainAttempts) failed: \(error)")
            }
        }
        throw lastError ?? CommandModeError.malformedToolCall("no response from the model")
    }

    /// Drives the loop to a terminal state and returns the summary + metrics.
    func run(task: String) async -> AgentRunResult {
        var history: [String] = []
        var lastCall: ToolCall?
        var lastOutcome = ""
        var stepCount = 0
        var toolInvocations = 0
        var invalidActions = 0

        func done(_ summary: String, _ outcome: AgentOutcome) -> AgentRunResult {
            AgentRunResult(
                summary: summary, outcome: outcome, stepCount: stepCount,
                toolInvocations: toolInvocations, invalidActions: invalidActions
            )
        }

        for _ in 0..<maxSteps {
            if cancelled { return done("Cancelled.", .cancelled) }
            stepCount += 1

            let observation = await screenReader.readScreen()

            let call: ToolCall
            do {
                call = try await nextToolCallWithRetries(task: task, observation: observation, history: history)
            } catch {
                // Esc during the retries reads as a cancel, not a model failure.
                if cancelled { return done("Cancelled.", .cancelled) }
                invalidActions += 1
                onStep?(AgentStep(toolCall: ToolCall(name: "?", arguments: [:]), result: nil, error: String(describing: error)))
                return done("Stopped: the model didn't return a valid action.", .brainFailure)
            }

            // Repeat-guard: small models re-issue the SAME call instead of calling
            // finish. Treat an identical consecutive call as completion, and report
            // the previous outcome honestly (success or the failure message).
            if let last = lastCall, last == call, call.name != "finish" {
                return done(lastOutcome.isEmpty ? "Done." : lastOutcome, .stalled)
            }
            lastCall = call

            guard let tool = registry.tool(named: call.name) else {
                invalidActions += 1
                onStep?(AgentStep(toolCall: call, result: nil, error: "unknown tool"))
                history.append("tried unknown tool \(call.name)")
                continue
            }

            do {
                let result = try await tool.execute(call.arguments)
                toolInvocations += 1
                onStep?(AgentStep(toolCall: call, result: result, error: nil))
                history.append("\(call.name) → \(result.output)")
                lastOutcome = result.output
                if result.isTerminal { return done(result.output, .completed) }
            } catch {
                onStep?(AgentStep(toolCall: call, result: nil, error: String(describing: error)))
                history.append("\(call.name) failed: \(error)")
                lastOutcome = String(describing: error)
            }
        }
        return done(lastOutcome.isEmpty ? "Stopped: reached the step limit." : lastOutcome, .stepLimit)
    }
}
