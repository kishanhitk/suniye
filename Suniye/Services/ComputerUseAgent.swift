import Foundation

actor ComputerUseAgent {
    private let modelClient: ComputerUseModelClient
    private let approvalService: ComputerUseApprovalRequesting
    private let approvalAuthorizer: ComputerUseApprovalAuthorizing?
    private let observationService: ComputerUseObservationServicing
    private let actionService: ComputerUseActionServicing
    private let interventionMonitor: ComputerUseInterventionMonitoring
    private let limits: ComputerUseAgentLimits
    private let dateProvider: () -> Date
    private let sleep: (TimeInterval) async throws -> Void

    init(
        modelClient: ComputerUseModelClient,
        approvalService: ComputerUseApprovalRequesting = DenyAllComputerUseApprovalService(),
        approvalAuthorizer: ComputerUseApprovalAuthorizing? = nil,
        observationService: ComputerUseObservationServicing,
        actionService: ComputerUseActionServicing,
        interventionMonitor: ComputerUseInterventionMonitoring = SystemComputerUseInterventionMonitor(),
        limits: ComputerUseAgentLimits = ComputerUseAgentLimits(),
        dateProvider: @escaping () -> Date = Date.init,
        sleep: @escaping (TimeInterval) async throws -> Void = { delay in
            guard delay > 0 else {
                return
            }
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    ) {
        self.modelClient = modelClient
        self.approvalService = approvalService
        self.approvalAuthorizer = approvalAuthorizer
        self.observationService = observationService
        self.actionService = actionService
        self.interventionMonitor = interventionMonitor
        self.limits = limits
        self.dateProvider = dateProvider
        self.sleep = sleep
    }

    func run(
        task: ComputerUseAgentTask,
        cancellation: ComputerUseCancellationToken = ComputerUseCancellationToken()
    ) async -> ComputerUseAgentResult {
        if isCancelled(cancellation) {
            return cancelledResult(observation: nil, actionResults: [], failureCount: 0)
        }
        guard !task.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return result(
                phase: .failed,
                message: "The Computer Use instruction cannot be empty.",
                question: nil,
                observation: nil,
                actionResults: [],
                failureCount: 0
            )
        }
        guard !task.applicationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return result(
                phase: .failed,
                message: "A target application is required.",
                question: nil,
                observation: nil,
                actionResults: [],
                failureCount: 0
            )
        }
        if let limitsError = limits.validationMessage {
            return result(
                phase: .failed,
                message: "Invalid Computer Use limits: \(limitsError).",
                question: nil,
                observation: nil,
                actionResults: [],
                failureCount: 0
            )
        }

        var state = RunState(startedAt: dateProvider())
        while true {
            switch await advance(
                task: task,
                state: state,
                cancellation: cancellation
            ) {
            case let .continueWith(nextState):
                state = nextState
            case let .finish(finalResult):
                return finalResult
            }
        }
    }

    private struct RunState {
        let startedAt: Date
        var latestObservation: ComputerUseObservation?
        var actionResults: [ComputerUseActionResult] = []
        var failureMessages: [String] = []
        var failureCount = 0
        var iteration = 0

        mutating func recordFailure(_ message: String) {
            failureCount += 1
            failureMessages.append(message)
            if failureMessages.count > 3 {
                failureMessages.removeFirst(failureMessages.count - 3)
            }
        }
    }

    private enum LoopResult {
        case continueWith(RunState)
        case finish(ComputerUseAgentResult)
    }

    private enum ActionAttemptResult {
        case succeeded(ComputerUseActionResult)
        case retryableFailure(String)
        case blocked(String)
        case denied
        case stopped
        case userIntervened(String)
        case cancelled
    }

    private func advance(
        task: ComputerUseAgentTask,
        state: RunState,
        cancellation: ComputerUseCancellationToken
    ) async -> LoopResult {
        var state = state

        if isCancelled(cancellation) {
            return .finish(
                cancelledResult(
                    observation: state.latestObservation,
                    actionResults: state.actionResults,
                    failureCount: state.failureCount
                )
            )
        }
        if dateProvider().timeIntervalSince(state.startedAt) >= limits.maxDuration {
            return .finish(
                result(
                    phase: .failed,
                    message: "The Computer Use time limit was reached.",
                    question: nil,
                    observation: state.latestObservation,
                    actionResults: state.actionResults,
                    failureCount: state.failureCount
                )
            )
        }
        state.iteration += 1
        let observation: ComputerUseObservation
        do {
            var observationConfiguration = ComputerUseObservationConfiguration.default
            observationConfiguration.preferredWindowID = task.windowID
            observation = try observationService.observe(
                applicationID: task.applicationID,
                includeScreenshot: task.includeScreenshot,
                configuration: observationConfiguration,
                cancellation: cancellation
            )
            state.latestObservation = observation
        } catch {
            if isCancelled(cancellation) || isCancellation(error) {
                return .finish(
                    cancelledResult(
                        observation: state.latestObservation,
                        actionResults: state.actionResults,
                        failureCount: state.failureCount
                    )
                )
            }
            return .finish(
                result(
                    phase: .failed,
                    message: localizedMessage(error),
                    question: nil,
                    observation: state.latestObservation,
                    actionResults: state.actionResults,
                    failureCount: state.failureCount
                )
            )
        }

        if let intervention = interventionMonitor.check(target: observation.target) {
            return .finish(
                result(
                    phase: .userIntervened,
                    message: intervention.message,
                    question: nil,
                    observation: observation,
                    actionResults: state.actionResults,
                    failureCount: state.failureCount
                )
            )
        }

        let request = ComputerUseModelRequest(
            instruction: task.instruction,
            observation: observation,
            recentActionResults: state.actionResults,
            recentFailureMessages: state.failureMessages,
            iteration: state.iteration
        )
        let decision: ComputerUseModelDecision
        do {
            decision = try await modelClient.decide(
                request: request,
                cancellation: cancellation
            )
        } catch {
            if isCancelled(cancellation) || isCancellation(error) {
                return .finish(
                    cancelledResult(
                        observation: observation,
                        actionResults: state.actionResults,
                        failureCount: state.failureCount
                    )
                )
            }
            if let modelError = error as? ComputerUseModelError,
               modelError == .notConfigured {
                return .finish(
                    result(
                        phase: .failed,
                        message: localizedMessage(error),
                        question: nil,
                        observation: observation,
                        actionResults: state.actionResults,
                        failureCount: state.failureCount
                    )
                )
            }

            let message = localizedMessage(error)
            return retryAfterFailure(
                message: message,
                state: &state,
                observation: observation
            )
        }

        if isCancelled(cancellation) {
            return .finish(
                cancelledResult(
                    observation: observation,
                    actionResults: state.actionResults,
                    failureCount: state.failureCount
                )
            )
        }

        return await handle(
            decision: decision,
            observation: observation,
            state: state,
            cancellation: cancellation,
            sessionID: task.sessionID
        )
    }

    private func handle(
        decision: ComputerUseModelDecision,
        observation: ComputerUseObservation,
        state: RunState,
        cancellation: ComputerUseCancellationToken,
        sessionID: UUID
    ) async -> LoopResult {
        var state = state

        if let validationMessage = decision.validationMessage {
            return retryAfterFailure(
                message: validationMessage,
                state: &state,
                observation: observation
            )
        }

        switch decision {
        case let .completed(message):
            return .finish(
                result(
                    phase: .completed,
                    message: message,
                    question: nil,
                    observation: observation,
                    actionResults: state.actionResults,
                    failureCount: state.failureCount
                )
            )
        case let .askUser(question):
            return .finish(
                result(
                    phase: .askingUser,
                    message: "The Computer Use model needs user input.",
                    question: question,
                    observation: observation,
                    actionResults: state.actionResults,
                    failureCount: state.failureCount
                )
            )
        case let .blocked(reason):
            return .finish(
                result(
                    phase: .blocked,
                    message: reason,
                    question: nil,
                    observation: observation,
                    actionResults: state.actionResults,
                    failureCount: state.failureCount
                )
            )
        case let .retryableFailure(reason):
            return retryAfterFailure(
                message: reason,
                state: &state,
                observation: observation
            )
        case let .action(action):
            switch await attemptAction(
                action: action,
                observation: observation,
                cancellation: cancellation,
                sessionID: sessionID
            ) {
            case let .blocked(message):
                return .finish(
                    result(
                        phase: .blocked,
                        message: message,
                        question: nil,
                        observation: observation,
                        actionResults: state.actionResults,
                        failureCount: state.failureCount
                    )
                )
            case let .retryableFailure(message):
                return retryAfterFailure(
                    message: message,
                    state: &state,
                    observation: observation
                )
            case .denied:
                return .finish(
                    result(
                        phase: .blocked,
                        message: "The user denied the proposed action.",
                        question: nil,
                        observation: observation,
                        actionResults: state.actionResults,
                        failureCount: state.failureCount
                    )
                )
            case .stopped:
                return .finish(
                    result(
                        phase: .cancelled,
                        message: ComputerUseIntervention.userStopped.message,
                        question: nil,
                        observation: observation,
                        actionResults: state.actionResults,
                        failureCount: state.failureCount
                    )
                )
            case let .userIntervened(message):
                return .finish(
                    result(
                        phase: .userIntervened,
                        message: message,
                        question: nil,
                        observation: observation,
                        actionResults: state.actionResults,
                        failureCount: state.failureCount
                    )
                )
            case .cancelled:
                return .finish(
                    cancelledResult(
                        observation: observation,
                        actionResults: state.actionResults,
                        failureCount: state.failureCount
                    )
                )
            case let .succeeded(actionResult):
                state.actionResults.append(actionResult)
                if state.actionResults.count >= limits.maxActions {
                    return .finish(
                        result(
                            phase: .failed,
                            message: "The Computer Use action limit was reached.",
                            question: nil,
                            observation: observation,
                            actionResults: state.actionResults,
                            failureCount: state.failureCount
                        )
                    )
                }
                if dateProvider().timeIntervalSince(state.startedAt) >= limits.maxDuration {
                    return .finish(
                        result(
                            phase: .failed,
                            message: "The Computer Use time limit was reached.",
                            question: nil,
                            observation: observation,
                            actionResults: state.actionResults,
                            failureCount: state.failureCount
                        )
                    )
                }
                do {
                    try await sleep(limits.settleDelay)
                } catch {
                    if isCancelled(cancellation) || isCancellation(error) {
                        return .finish(
                            cancelledResult(
                                observation: observation,
                                actionResults: state.actionResults,
                                failureCount: state.failureCount
                            )
                        )
                    }
                    let message = localizedMessage(error)
                    return retryAfterFailure(
                        message: message,
                        state: &state,
                        observation: observation
                    )
                }
                return .continueWith(state)
            }
        }
    }

    private func retryAfterFailure(
        message: String,
        state: inout RunState,
        observation: ComputerUseObservation
    ) -> LoopResult {
        state.recordFailure(message)
        guard state.failureCount < limits.maxFailures else {
            return .finish(
                failureLimitResult(
                    message: message,
                    observation: observation,
                    actionResults: state.actionResults,
                    failureCount: state.failureCount
                )
            )
        }
        return .continueWith(state)
    }

    private func attemptAction(
        action: ComputerUseAction,
        observation: ComputerUseObservation,
        cancellation: ComputerUseCancellationToken,
        sessionID: UUID
    ) async -> ActionAttemptResult {
        do {
            try ComputerUseActionPolicy.validate(action: action, observation: observation)
        } catch {
            return .retryableFailure(localizedMessage(error))
        }

        let approvalRequest = ComputerUseApprovalRequest(
            id: UUID(),
            action: action,
            target: observation.target,
            risk: action.risk,
            reason: "The Computer Use model proposed this action for the current task.",
            sessionID: sessionID,
            observationGeneration: observation.generation
        )
        let preparedRequest: ComputerUseApprovalRequest
        if let approvalAuthorizer {
            do {
                preparedRequest = try await approvalAuthorizer.prepare(approvalRequest)
                if let rememberedScope = try await approvalAuthorizer.rememberedScope(
                    for: preparedRequest
                ) {
                    return await executeApprovedAction(
                        action: action,
                        observation: observation,
                        approvalRequest: preparedRequest,
                        scope: rememberedScope,
                        cancellation: cancellation
                    )
                }
            } catch {
                return .blocked(localizedMessage(error))
            }
        } else {
            preparedRequest = approvalRequest
        }

        let approval = await approvalService.requestApproval(
            preparedRequest,
            cancellation: cancellation
        )
        if isCancelled(cancellation) {
            return .cancelled
        }

        switch approval {
        case .deny:
            return .denied
        case .stopSession:
            return .stopped
        case .allowOnce, .allowForSession, .allowAlways:
            guard let scope = approval.scope,
                  preparedRequest.allowedScopes.contains(scope) else {
                return .retryableFailure(
                    ComputerUsePolicyError.approvalScopeNotAllowed.localizedDescription
                )
            }
            return await executeApprovedAction(
                action: action,
                observation: observation,
                approvalRequest: preparedRequest,
                scope: scope,
                cancellation: cancellation
            )
        }
    }

    private func executeApprovedAction(
        action: ComputerUseAction,
        observation: ComputerUseObservation,
        approvalRequest: ComputerUseApprovalRequest,
        scope: ComputerUseApprovalScope,
        cancellation: ComputerUseCancellationToken
    ) async -> ActionAttemptResult {
        guard !isCancelled(cancellation) else {
            return .cancelled
        }
        if let intervention = interventionMonitor.check(target: observation.target) {
            return .userIntervened(intervention.message)
        }

        let grant: ComputerUseApprovalGrant
        if let approvalAuthorizer {
            do {
                grant = try await approvalAuthorizer.grant(
                    for: approvalRequest,
                    scope: scope
                )
            } catch {
                return .blocked(localizedMessage(error))
            }
        } else {
            grant = ComputerUseApprovalGrant(
                requestID: approvalRequest.id,
                scope: scope,
                applicationID: observation.target.application.id,
                windowID: observation.target.window.id,
                observationGeneration: observation.generation,
                action: action,
                sessionID: approvalRequest.sessionID
            )
        }

        do {
            let actionResult = try actionService.execute(
                action: action,
                observation: observation,
                approval: grant,
                requestID: approvalRequest.id,
                cancellation: cancellation
            )
            return .succeeded(actionResult)
        } catch {
            if isCancelled(cancellation) || isCancellation(error) {
                return .cancelled
            }
            if let actionError = error as? ComputerUseActionError,
               actionError == .targetNotFrontmost {
                return .userIntervened(actionError.localizedDescription)
            }
            return .retryableFailure(localizedMessage(error))
        }
    }

    private func isCancelled(_ cancellation: ComputerUseCancellationToken) -> Bool {
        cancellation.isCancelled || Task.isCancelled
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let observationError = error as? ComputerUseObservationError {
            return observationError == .cancelled
        }
        if let actionError = error as? ComputerUseActionError {
            return actionError == .cancelled
        }
        return false
    }

    private func localizedMessage(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private func failureLimitResult(
        message: String,
        observation: ComputerUseObservation,
        actionResults: [ComputerUseActionResult],
        failureCount: Int
    ) -> ComputerUseAgentResult {
        return result(
            phase: .failed,
            message: "\(message) The Computer Use failure limit was reached.",
            question: nil,
            observation: observation,
            actionResults: actionResults,
            failureCount: failureCount
        )
    }

    private func cancelledResult(
        observation: ComputerUseObservation?,
        actionResults: [ComputerUseActionResult],
        failureCount: Int
    ) -> ComputerUseAgentResult {
        result(
            phase: .cancelled,
            message: "The Computer Use session was canceled.",
            question: nil,
            observation: observation,
            actionResults: actionResults,
            failureCount: failureCount
        )
    }

    private func result(
        phase: ComputerUseAgentPhase,
        message: String,
        question: String?,
        observation: ComputerUseObservation?,
        actionResults: [ComputerUseActionResult],
        failureCount: Int
    ) -> ComputerUseAgentResult {
        ComputerUseAgentResult(
            phase: phase,
            message: message,
            question: question,
            latestObservation: observation,
            actionResults: actionResults,
            failureCount: failureCount
        )
    }
}
