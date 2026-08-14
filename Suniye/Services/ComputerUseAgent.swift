import Foundation
import SuniyeAnalytics

enum ComputerUseAgentOutcome: Equatable, Sendable {
    case completed
    case cancelled
    case failed
}

enum ComputerUseAgentError: LocalizedError, Equatable, Sendable {
    case stepLimitExceeded(Int)
    case timeLimitExceeded

    var errorDescription: String? {
        switch self {
        case let .stepLimitExceeded(limit):
            "Computer Use stopped after \(limit) steps without finishing the task. "
                + "Try a smaller task or run it again."
        case .timeLimitExceeded:
            "Computer Use stopped after running too long without finishing the task. "
                + "Try a smaller task or run it again."
        }
    }
}

struct ComputerUseDebugSessionID: Equatable, Sendable {
    let rawValue: String

    static func generate(uuid: UUID = UUID()) -> ComputerUseDebugSessionID {
        let compactUUID = uuid.uuidString.replacingOccurrences(of: "-", with: "")
        return ComputerUseDebugSessionID(
            rawValue: "CU-\(compactUUID.prefix(12).uppercased())"
        )
    }
}

struct ComputerUseAgentTask: Sendable {
    let instruction: String
    let conversation: [ComputerUseConversationMessage]
    let debugSessionID: ComputerUseDebugSessionID
    let interventions: ComputerUseInterventionChannel

    init(
        instruction: String,
        conversation: [ComputerUseConversationMessage] = [],
        debugSessionID: ComputerUseDebugSessionID = .generate(),
        interventions: ComputerUseInterventionChannel = ComputerUseInterventionChannel()
    ) {
        self.instruction = instruction
        self.conversation = conversation
        self.debugSessionID = debugSessionID
        self.interventions = interventions
    }
}

struct ComputerUseConversationMessage: Codable, Identifiable, Equatable, Sendable {
    enum Role: String, Codable, Equatable, Sendable {
        case user
        case assistant
        case activity
    }

    let id: UUID
    let role: Role
    let text: String
    let activity: ComputerUseActivity?

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        activity: ComputerUseActivity? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.activity = activity
    }

    init(id: UUID = UUID(), activity: ComputerUseActivity) {
        self.init(
            id: id,
            role: .activity,
            text: "\(activity.toolName)  \(activity.arguments)",
            activity: activity
        )
    }
}

struct ComputerUseAgentResult: Equatable, Sendable {
    let outcome: ComputerUseAgentOutcome
    let message: String
}

protocol ComputerUseAgentRunning: Sendable {
    func run(task: ComputerUseAgentTask) async -> ComputerUseAgentResult
}

protocol ComputerUseLogging: Sendable {
    func log(_ level: AppLogger.Level, _ message: String)
}

struct SystemComputerUseLogger: ComputerUseLogging {
    func log(_ level: AppLogger.Level, _ message: String) {
        AppLogger.shared.log(level, message)
    }
}

actor ComputerUseAgent: ComputerUseAgentRunning {
    private let model: ComputerUseModelServing
    private let tools: any ComputerUseToolServing
    private let screenshots: ComputerUseScreenshotLoading
    private let logger: ComputerUseLogging
    private let activitySink: ComputerUseActivitySink
    private let contextBuilder: ComputerUseModelContextBuilder
    private let maximumSteps: Int
    private let maximumRunDuration: Duration
    private let now: @Sendable () -> ContinuousClock.Instant
    private let analytics: any Analytics
    private let modelID: String
    private var toolFailureCount = 0

    /// Scratch for the script currently executing; reset at the start of each
    /// node_repl call. `performSkyCall` (invoked from the JS bridge) fills these
    /// and `runScript` reads them once the script settles.
    private var scriptExecutions: [ComputerUseExecutedToolCall] = []
    private var scriptObservations: [ScriptObservation] = []
    private var scriptLastTargetApp: String?

    init(
        model: ComputerUseModelServing,
        tools: any ComputerUseToolServing,
        screenshots: ComputerUseScreenshotLoading = SystemComputerUseScreenshotLoader(),
        logger: ComputerUseLogging = SystemComputerUseLogger(),
        activitySink: ComputerUseActivitySink = .disabled,
        analytics: any Analytics = NoopAnalytics(),
        modelID: String = "",
        contextPolicy: ComputerUseModelContextPolicy = .referenceAligned(modelID: ""),
        maximumSteps: Int = 60,
        maximumRunDuration: Duration = .seconds(300),
        now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock().now }
    ) {
        self.model = model
        self.tools = tools
        self.screenshots = screenshots
        self.logger = logger
        self.activitySink = activitySink
        contextBuilder = ComputerUseModelContextBuilder(policy: contextPolicy)
        self.maximumSteps = maximumSteps
        self.maximumRunDuration = maximumRunDuration
        self.now = now
        self.analytics = analytics
        self.modelID = modelID
    }

    func run(task: ComputerUseAgentTask) async -> ComputerUseAgentResult {
        let instruction = task.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else {
            return ComputerUseAgentResult(
                outcome: .failed,
                message: "Enter a Computer Use task."
            )
        }

        let debugSessionID = task.debugSessionID
        var messages = await contextBuilder.initialMessages(
            conversation: task.conversation,
            instruction: instruction,
            screenshots: screenshots
        )
        var step = 0
        var lastTargetApp: String?
        var audits = RunAuditState()
        let deadline = now().advanced(by: maximumRunDuration)
        let startedAt = now()
        toolFailureCount = 0
        log(.info, "computer use run started", session: debugSessionID)
        do {
            while true {
                try Task.checkCancellation()
                try enforceRunLimits(step: step, deadline: deadline)
                if try await applyInterventions(
                    task.interventions.takeAll(),
                    lastTargetApp: lastTargetApp,
                    debugSessionID: debugSessionID,
                    messages: &messages
                ) {
                    audits.noteInterventionObserved()
                }
                messages = contextBuilder.compact(
                    messages,
                    currentInstruction: instruction
                )
                let response = try await model.respond(to: messages)
                let interveningInstructions = task.interventions.takeAll()
                if !interveningInstructions.isEmpty {
                    if try await applyInterventions(
                        interveningInstructions,
                        lastTargetApp: lastTargetApp,
                        debugSessionID: debugSessionID,
                        messages: &messages
                    ) {
                        audits.noteInterventionObserved()
                    }
                    continue
                }
                switch response {
                case let .text(text):
                    if let audit = audits.auditForCompletionAttempt() {
                        messages.append(.text(role: .assistant, text: text))
                        messages.append(.text(role: .user, text: audit))
                        continue
                    }
                    log(
                        .info,
                        "computer use run completed steps=\(step)",
                        session: debugSessionID
                    )
                    recordRun(
                        .completed,
                        steps: step,
                        startedAt: startedAt,
                        targetApp: lastTargetApp
                    )
                    return ComputerUseAgentResult(outcome: .completed, message: text)
                case let .toolCall(id, name, arguments):
                    guard name == ComputerUseToolName.nodeRepl.rawValue else {
                        // Only node_repl is advertised; anything else is a model
                        // error surfaced back as a tool result it can recover from.
                        messages.append(.toolCall(id: id, name: name, arguments: arguments))
                        messages.append(.toolResult(
                            id: id,
                            content: "Unknown tool \(name). Use node_repl and drive computer.* from JavaScript."
                        ))
                        continue
                    }
                    let scriptOutcome = try await runScript(
                        id: id,
                        arguments: arguments,
                        debugSessionID: debugSessionID,
                        messages: &messages
                    )
                    step += scriptOutcome.executedCalls
                    if let app = scriptOutcome.lastTargetApp {
                        lastTargetApp = app
                    }
                    for execution in scriptOutcome.executions {
                        if let recovery = audits.noteExecuted(execution) {
                            messages.append(.text(role: .user, text: recovery))
                        }
                    }
                }
            }
        } catch is CancellationError {
            log(
                .info,
                "computer use run cancelled reason=requested",
                session: debugSessionID
            )
            recordRun(.cancelled, steps: step, startedAt: startedAt, targetApp: lastTargetApp)
            return ComputerUseAgentResult(outcome: .cancelled, message: "Stopped.")
        } catch let error as ComputerUseAgentError {
            log(
                .warning,
                "computer use run stopped reason=\(error) steps=\(step)",
                session: debugSessionID
            )
            recordRun(.failed, steps: step, startedAt: startedAt, targetApp: lastTargetApp)
            return ComputerUseAgentResult(
                outcome: .failed,
                message: localizedMessage(error)
            )
        } catch {
            log(
                .warning,
                "computer use run failed error_type=\(String(describing: type(of: error)))",
                session: debugSessionID
            )
            recordRun(.failed, steps: step, startedAt: startedAt, targetApp: lastTargetApp)
            return ComputerUseAgentResult(
                outcome: .failed,
                message: localizedMessage(error)
            )
        }
    }

    /// Which tool failed and why, in closed vocabularies. Error associated
    /// values carry app names and user text, so only the case is reported.
    private func recordToolFailure(name: String, error: Error, targetApp: String?) {
        toolFailureCount += 1
        guard let tool = ComputerUseToolName(rawValue: name) else {
            analytics.track(
                .computerUseToolFailed(
                    tool: .unknown,
                    target: TargetCategoryMapper.category(for: targetApp),
                    reason: ComputerUseAnalyticsMapping.computerUseFailureReason(error)
                )
            )
            return
        }
        analytics.track(
            .computerUseToolFailed(
                tool: ComputerUseAnalyticsMapping.computerUseTool(tool),
                target: TargetCategoryMapper.category(for: targetApp),
                reason: ComputerUseAnalyticsMapping.computerUseFailureReason(error)
            )
        )
    }

    /// One record per finished run. The target app is reported as a category,
    /// never as an identifier, and no instruction or screen content is included.
    private func recordRun(
        _ outcome: ComputerUseAgentOutcome,
        steps: Int,
        startedAt: ContinuousClock.Instant,
        targetApp: String?
    ) {
        let elapsed = startedAt.duration(to: now())
        analytics.track(
            .computerUseRun(
                ComputerUseRunMetrics(
                    outcome: ComputerUseAnalyticsMapping.computerUseOutcome(outcome),
                    steps: steps,
                    toolFailures: toolFailureCount,
                    durationMs: Int(elapsed / .milliseconds(1)),
                    model: SafeLabel(modelID),
                    target: TargetCategoryMapper.category(for: targetApp)
                )
            )
        )
    }

    /// Runs one model-authored node_repl script. Each `computer.*` call inside
    /// drives `performSkyCall`; the script's text output becomes one tool
    /// result, and observations made during the script attach their screenshots.
    private func runScript(
        id: String,
        arguments: String,
        debugSessionID: ComputerUseDebugSessionID,
        messages: inout [ComputerUseModelMessage]
    ) async throws -> ScriptOutcome {
        messages.append(.toolCall(id: id, name: ComputerUseToolName.nodeRepl.rawValue, arguments: arguments))

        guard let code = decodeScriptCode(arguments) else {
            messages.append(.toolResult(
                id: id,
                content: "node_repl requires a JSON object with a string 'code' field."
            ))
            return ScriptOutcome(executions: [], executedCalls: 0, lastTargetApp: nil)
        }

        scriptExecutions = []
        scriptObservations = []
        scriptLastTargetApp = nil

        let startActivity = ComputerUseActivity(
            toolName: ComputerUseToolName.nodeRepl.rawValue,
            arguments: arguments
        )
        await activitySink.emit(startActivity)
        log(.debug, "computer use script started", session: debugSessionID)

        let runtime = ComputerUseScriptRuntime { [weak self] call in
            guard let self else {
                return .failure(CancellationError())
            }
            return await self.performSkyCall(call)
        }
        let scriptResult = await runtime.run(script: code)
        try Task.checkCancellation()

        let output = composeOutput(scriptResult)
        let modelOutput = ComputerUseTokenTruncator.truncateMiddle(
            output,
            maximumTokens: contextBuilder.policy.maximumToolOutputTokens
        )
        messages.append(.toolResult(
            id: id,
            content: modelOutput.isEmpty ? "(script produced no output)" : modelOutput
        ))

        let attachedObservations = scriptObservations
            .filter { $0.dataURL != nil }
            .suffix(contextBuilder.policy.maximumScreenshots)
        for observation in attachedObservations {
            guard let dataURL = observation.dataURL else { continue }
            messages.append(.screenshot(app: observation.app, dataURL: dataURL))
        }

        let lastObservation = scriptObservations.last
        await activitySink.emit(startActivity.completed(
            output: output,
            observedApp: lastObservation?.app,
            observedScreenshotURL: lastObservation?.url
        ))
        log(
            .debug,
            "computer use script completed calls=\(scriptExecutions.count) "
                + "failures=\(scriptResult.error == nil ? 0 : 1)",
            session: debugSessionID
        )
        return ScriptOutcome(
            executions: scriptExecutions,
            executedCalls: scriptExecutions.count,
            lastTargetApp: scriptLastTargetApp
        )
    }

    /// Executes one decoded `computer.*` call from a running script, recording
    /// the observation, audit signal, and target app into the script scratch.
    /// Returns the result to resolve the JS promise, or a failure to reject it.
    private func performSkyCall(
        _ call: ComputerUseToolCall
    ) async -> Result<ComputerUseToolResult, Error> {
        if let app = call.targetApp {
            scriptLastTargetApp = app
        }
        do {
            let result = try await tools.execute(call)
            var observationWasUnchanged = false
            if case let .appState(state) = result {
                observationWasUnchanged = state.text.hasPrefix(
                    "There has been no change in the accessibility tree"
                )
                if let screenshot = state.screenshot {
                    // The URL persists for replay even when the file cannot be
                    // loaded right now; only the model attachment needs the data.
                    scriptObservations.append(ScriptObservation(
                        app: state.app,
                        url: screenshot,
                        dataURL: try? await screenshots.dataURL(for: screenshot)
                    ))
                }
            }
            scriptExecutions.append(
                ComputerUseExecutedToolCall(call: call, observationWasUnchanged: observationWasUnchanged)
            )
            return .success(result)
        } catch is CancellationError {
            return .failure(CancellationError())
        } catch {
            recordToolFailure(name: call.name.rawValue, error: error, targetApp: call.targetApp)
            return .failure(error)
        }
    }

    private func decodeScriptCode(_ arguments: String) -> String? {
        struct ScriptArguments: Decodable {
            let code: String
        }
        guard let data = arguments.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(ScriptArguments.self, from: data),
              !decoded.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return decoded.code
    }

    private func composeOutput(_ result: ComputerUseScriptResult) -> String {
        guard let error = result.error else {
            return result.output
        }
        return result.output.isEmpty ? "Error: \(error)" : "\(result.output)\nError: \(error)"
    }

    /// Bounds a run that the model never completes. Without these an agent can
    /// act on the machine indefinitely and keep billing the provider.
    private func enforceRunLimits(
        step: Int,
        deadline: ContinuousClock.Instant
    ) throws {
        if step >= maximumSteps {
            throw ComputerUseAgentError.stepLimitExceeded(maximumSteps)
        }
        if now() >= deadline {
            throw ComputerUseAgentError.timeLimitExceeded
        }
    }

    private func applyInterventions(
        _ interventions: [String],
        lastTargetApp: String?,
        debugSessionID: ComputerUseDebugSessionID,
        messages: inout [ComputerUseModelMessage]
    ) async throws -> Bool {
        guard !interventions.isEmpty else { return false }
        for intervention in interventions {
            messages.append(.text(role: .user, text: intervention))
        }
        log(
            .info,
            "computer use intervention received count=\(interventions.count)",
            session: debugSessionID
        )
        guard let lastTargetApp else { return false }
        await observeForIntervention(app: lastTargetApp, messages: &messages)
        return true
    }

    /// Fresh observation seeded after an intervention. The advertised tool is
    /// node_repl, so the observation enters context as a user message with its
    /// screenshot rather than a get_app_state tool call the model never made.
    private func observeForIntervention(
        app: String,
        messages: inout [ComputerUseModelMessage]
    ) async {
        guard let result = try? await tools.execute(.getAppState(app: app, disableDiff: false)),
              case let .appState(state) = result else {
            return
        }
        let text = (try? ComputerUseModelToolOutput.encode(
            result,
            maximumTokens: contextBuilder.policy.maximumToolOutputTokens
        )) ?? state.text
        messages.append(.text(role: .user, text: "Current state of \(state.app) after your input:\n\(text)"))
        if let screenshot = state.screenshot,
           let dataURL = try? await screenshots.dataURL(for: screenshot) {
            messages.append(.screenshot(app: state.app, dataURL: dataURL))
        }
    }

    private func localizedMessage(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private func log(
        _ level: AppLogger.Level,
        _ message: String,
        session debugSessionID: ComputerUseDebugSessionID
    ) {
        logger.log(level, "\(message) session=\(debugSessionID.rawValue)")
    }

    /// Cross-iteration audit bookkeeping for the run loop. Every flag
    /// transition lives here, so the loop body cannot drift per branch.
    private struct RunAuditState {
        private var hasSuccessfulObservation = false
        private var hasPerformedAction = false
        private var needsPostActionObservation = false
        private var requestedCompletionAudit = false
        private var unchangedObservationStreak = 0

        /// An intervention forces a fresh observation into the transcript.
        mutating func noteInterventionObserved() {
            hasSuccessfulObservation = true
            needsPostActionObservation = false
        }

        /// The audit prompt to inject instead of accepting a text completion,
        /// or nil when the completion may stand.
        mutating func auditForCompletionAttempt() -> String? {
            if needsPostActionObservation {
                return ComputerUseAgent.postActionObservationAudit
            }
            if hasSuccessfulObservation, !hasPerformedAction, !requestedCompletionAudit {
                requestedCompletionAudit = true
                return ComputerUseAgent.completionAudit
            }
            return nil
        }

        /// Records an executed tool call. Returns the recovery prompt when
        /// post-action observations keep reporting an unchanged state.
        mutating func noteExecuted(_ execution: ComputerUseExecutedToolCall) -> String? {
            if execution.call.isObservation {
                if needsPostActionObservation, execution.observationWasUnchanged {
                    unchangedObservationStreak += 1
                } else {
                    unchangedObservationStreak = 0
                }
                hasSuccessfulObservation = true
                needsPostActionObservation = false
                if unchangedObservationStreak >= 2 {
                    unchangedObservationStreak = 0
                    return ComputerUseAgent.unchangedStateRecovery
                }
            } else if execution.call.isAction {
                hasPerformedAction = true
                needsPostActionObservation = true
            }
            return nil
        }
    }

    private static let completionAudit = """
    Internal completion audit: Compare the current user request with the tool history. If the \
    request asks to change the UI and the exact requested end state was not already present, \
    continue with the required action tool instead of reporting success. An item appearing in a \
    list, search result, menu, or tree is not evidence that it was opened or activated. If the \
    task is read-only and the current observation is sufficient, return the concise final answer.
    """

    private static let postActionObservationAudit = """
    Internal completion audit: An action was performed, but its result has not been observed. \
    Call get_app_state for the target app now. Report success only if that fresh observation \
    proves the requested end state; otherwise continue with the next appropriate action.
    """

    private static let unchangedStateRecovery = """
    Repeated unchanged-state recovery: Two actions were each followed by an observation that \
    showed no UI change. Those action attempts did not work. Reassess the latest state and use a \
    different supported strategy. If the recent attempts were coordinate clicks, do not make \
    another coordinate click until another interaction changes the state. Prefer a fresh full \
    observation, an indexed Accessibility action, or keyboard activation such as Return when the \
    intended control is focused. Do not report success from the unchanged state.
    """
}

private struct ComputerUseExecutedToolCall {
    let call: ComputerUseToolCall
    let observationWasUnchanged: Bool
}

/// A `get_app_state` observation made inside a script, retained so its
/// screenshot can attach to the tool result and seed a later run. `dataURL`
/// is nil when the file could not be loaded; the URL still persists.
private struct ScriptObservation {
    let app: String
    let url: URL
    let dataURL: String?
}

private struct ScriptOutcome {
    let executions: [ComputerUseExecutedToolCall]
    let executedCalls: Int
    let lastTargetApp: String?
}

private extension ComputerUseToolCall {
    var targetApp: String? {
        switch self {
        case .listApps:
            nil
        case let .getAppState(app, _),
             let .performSecondaryAction(app, _, _),
             let .setValue(app, _, _),
             let .selectText(app, _, _, _, _, _),
             let .scroll(app, _, _, _),
             let .drag(app, _, _, _, _),
             let .pressKey(app, _),
             let .typeText(app, _):
            app
        case let .click(request):
            request.app
        case .setVoiceActivation:
            nil
        }
    }

    var isObservation: Bool {
        if case .getAppState = self {
            return true
        }
        return false
    }

    var isAction: Bool {
        switch self {
        case .listApps, .getAppState, .setVoiceActivation:
            false
        case .click, .performSecondaryAction, .setValue, .selectText,
             .scroll, .drag, .pressKey, .typeText:
            true
        }
    }
}

private extension ComputerUseToolResult {
    var logValue: String {
        switch self {
        case let .applications(applications):
            "applications count=\(applications.count)"
        case let .appState(state):
            "app_state text_chars=\(state.text.count) screenshot=\(state.screenshot != nil)"
        case .actionCompleted:
            "action_completed"
        }
    }
}
