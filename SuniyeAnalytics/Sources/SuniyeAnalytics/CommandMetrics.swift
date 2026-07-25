import Foundation

/// Everything measured about one Command Mode run, folded into a SINGLE
/// analytics event (one Analytics Engine data point), mirroring `DictationMetrics`.
/// Counts, enums, and durations only — never the spoken command, the tool
/// arguments, the on-screen text, or the target app's identity.
public struct CommandMetrics: Sendable, Equatable {
    /// Terminal state of the agent loop.
    public var outcome: CommandOutcome
    /// Loop turns the agent took (perceive → decide → act cycles).
    public var stepCount: Int
    /// Tools that actually executed (successful `execute` calls).
    public var toolInvocations: Int
    /// Times the brain returned an unparseable or unknown action — a direct
    /// model-quality signal that informs dedicated-model selection.
    public var invalidActions: Int
    /// Which brain ran. Reuses the cleanup-provider vocabulary because Command
    /// Mode shares the Magic Format provider stack until a dedicated brain lands.
    public var brainProvider: CleanupProvider
    /// The brain model id, when known (e.g. the local GGUF). Sanitized.
    public var brainModel: SafeLabel?
    /// Coarse category of the app that was frontmost when the command started.
    public var targetCategory: TargetCategory
    /// Length of the spoken command (audio), milliseconds.
    public var spokenDurationMs: Int
    /// Wall-clock the agent loop took, milliseconds.
    public var agentRuntimeMs: Int

    public init(
        outcome: CommandOutcome,
        stepCount: Int,
        toolInvocations: Int,
        invalidActions: Int,
        brainProvider: CleanupProvider,
        brainModel: SafeLabel? = nil,
        targetCategory: TargetCategory,
        spokenDurationMs: Int,
        agentRuntimeMs: Int
    ) {
        self.outcome = outcome
        self.stepCount = stepCount
        self.toolInvocations = toolInvocations
        self.invalidActions = invalidActions
        self.brainProvider = brainProvider
        self.brainModel = brainModel
        self.targetCategory = targetCategory
        self.spokenDurationMs = spokenDurationMs
        self.agentRuntimeMs = agentRuntimeMs
    }

    var props: [String: AnalyticsValue] {
        var out: [String: AnalyticsValue] = [
            "outcome": .label(outcome),
            "step_count": .int(stepCount),
            "tool_invocations": .int(toolInvocations),
            "invalid_actions": .int(invalidActions),
            "brain_provider": .label(brainProvider),
            "target_category": .label(targetCategory),
            "spoken_duration_ms": .int(spokenDurationMs),
            "agent_runtime_ms": .int(agentRuntimeMs),
        ]
        if let brainModel { out["brain_model"] = .label(brainModel) }
        return out
    }
}
