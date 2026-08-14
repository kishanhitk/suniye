import Foundation

/// Shape of one completed Computer Use run. Every field is a closed vocabulary,
/// a count, or a sanitized label: the target app is reported as a category, never
/// as a bundle identifier, so no record of which app the user drove leaves the Mac.
public struct ComputerUseRunMetrics: Sendable, Equatable {
    public var outcome: ComputerUseOutcome
    public var steps: Int
    public var toolFailures: Int
    public var durationMs: Int
    public var model: SafeLabel
    public var target: TargetCategory

    public init(
        outcome: ComputerUseOutcome,
        steps: Int,
        toolFailures: Int,
        durationMs: Int,
        model: SafeLabel,
        target: TargetCategory
    ) {
        self.outcome = outcome
        self.steps = steps
        self.toolFailures = toolFailures
        self.durationMs = durationMs
        self.model = model
        self.target = target
    }

    var props: [String: AnalyticsValue] {
        [
            "outcome": .label(outcome),
            "steps": .int(steps),
            "tool_failures": .int(toolFailures),
            "duration_ms": .int(durationMs),
            "model": .label(model),
            "target_category": .label(target),
        ]
    }
}
