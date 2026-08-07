import Foundation

actor ComputerUseAgent {
    private let modelClient: ComputerUseModelClient
    private let approvalAuthorizer: ComputerUseApprovalAuthorizing
    private let applicationCatalog: ComputerUseApplicationCatalog
    private let observationService: ComputerUseObservationServicing
    private let actionService: ComputerUseActionServicing
    private let sleep: (TimeInterval) async throws -> Void

    init(
        modelClient: ComputerUseModelClient,
        approvalAuthorizer: ComputerUseApprovalAuthorizing = ComputerUseAutomaticApprovalAuthorizer(),
        applicationCatalog: ComputerUseApplicationCatalog = SystemComputerUseApplicationCatalog(),
        observationService: ComputerUseObservationServicing,
        actionService: ComputerUseActionServicing,
        sleep: @escaping (TimeInterval) async throws -> Void = { delay in
            guard delay > 0 else {
                return
            }
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    ) {
        self.modelClient = modelClient
        self.approvalAuthorizer = approvalAuthorizer
        self.applicationCatalog = applicationCatalog
        self.observationService = observationService
        self.actionService = actionService
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
        if let applicationID = task.applicationID,
           applicationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return result(
                phase: .failed,
                message: "The target application identifier cannot be empty.",
                question: nil,
                observation: nil,
                actionResults: [],
                failureCount: 0
            )
        }
        let requestedApplication = task.applicationID.flatMap {
            applicationCatalog.resolveApplication(identifier: $0)
        }
        let initialApplicationID = requestedApplication?.id ?? task.applicationID
        let initialTargetDescription = requestedApplication?.bundleIdentifier
            ?? initialApplicationID
            ?? "frontmost"

        AppLogger.shared.log(
            .info,
            "computer_use agent start target=\(initialTargetDescription)"
        )

        var state = RunState(
            applicationID: initialApplicationID
        )
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
        var applicationID: String?
        var latestObservation: ComputerUseObservation?
        var actionResults: [ComputerUseActionResult] = []
        var failureMessages: [String] = []
        var failureCount = 0
        var iteration = 0

        init(applicationID: String?) {
            self.applicationID = applicationID
        }

        mutating func recordFailure(_ message: String) {
            failureCount += 1
            failureMessages.append(message)
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
        state.iteration += 1
        let observation: ComputerUseObservation
        do {
            var observationConfiguration = ComputerUseObservationConfiguration.default
            observationConfiguration.activateTarget = true
            observation = try await observationService.observeTarget(
                applicationIdentifier: state.applicationID,
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
            if let observationError = error as? ComputerUseObservationError,
               case .noWindow = observationError,
               let latestObservation = state.latestObservation {
                state.recordFailure(localizedMessage(error))
                observation = latestObservation
            } else {
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
        }

        let request = ComputerUseModelRequest(
            instruction: task.instruction,
            observation: observation,
            availableApplications: applicationCatalog.listAvailableApplications(),
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
        case let .target(application):
            state.applicationID = application.trimmingCharacters(in: .whitespacesAndNewlines)
            return .continueWith(state)
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
                do {
                    try await sleep(0.15)
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
        return .continueWith(state)
    }

    private func attemptAction(
        action: ComputerUseAction,
        observation: ComputerUseObservation,
        cancellation: ComputerUseCancellationToken,
        sessionID: UUID
    ) async -> ActionAttemptResult {
        let approvalRequest = ComputerUseApprovalRequest(
            id: UUID(),
            action: action,
            target: observation.target,
            risk: action.risk,
            sessionID: sessionID,
            observationGeneration: observation.generation
        )
        let approval: ComputerUseApprovalGrant
        do {
            approval = try await approvalAuthorizer.authorize(approvalRequest)
        } catch {
            return .blocked(localizedMessage(error))
        }

        guard !isCancelled(cancellation) else {
            return .cancelled
        }

        do {
            let actionResult = try actionService.execute(
                action: action,
                observation: observation,
                approval: approval,
                requestID: approvalRequest.id,
                cancellation: cancellation
            )
            return .succeeded(actionResult)
        } catch {
            if isCancelled(cancellation) || isCancellation(error) {
                return .cancelled
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
