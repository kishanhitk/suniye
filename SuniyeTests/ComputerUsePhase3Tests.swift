import Foundation
import XCTest
@testable import Suniye

final class ComputerUsePhase3ModelTests: XCTestCase {
    func testModelDecisionAndAgentValuesRoundTripThroughCodable() throws {
        let observation = makePhase3Observation(generation: 1)
        let request = ComputerUseModelRequest(
            instruction: "Open the item",
            observation: observation,
            recentActionResults: [],
            recentFailureMessages: ["A previous action failed."],
            iteration: 2
        )
        let decisions: [ComputerUseModelDecision] = [
            .action(.click(point: ComputerUsePoint(x: 50, y: 50))),
            .completed(message: "Done"),
            .askUser(question: "Which item should I choose?"),
            .blocked(reason: "The task requires a payment."),
            .retryableFailure(reason: "The target was not visible."),
        ]

        for decision in decisions {
            let data = try JSONEncoder().encode(decision)
            XCTAssertEqual(try JSONDecoder().decode(ComputerUseModelDecision.self, from: data), decision)
        }

        XCTAssertEqual(
            try JSONDecoder().decode(
                ComputerUseModelRequest.self,
                from: JSONEncoder().encode(request)
            ),
            request
        )

        let task = ComputerUseAgentTask(instruction: "Open the item", applicationID: "target#42")
        let limits = ComputerUseAgentLimits(maxActions: 4, maxFailures: 2, maxDuration: 12, settleDelay: 0.2)
        let result = ComputerUseAgentResult(
            phase: .completed,
            message: "Done",
            question: nil,
            latestObservation: observation,
            actionResults: [],
            failureCount: 0
        )
        XCTAssertEqual(try JSONDecoder().decode(ComputerUseAgentTask.self, from: JSONEncoder().encode(task)), task)
        XCTAssertEqual(try JSONDecoder().decode(ComputerUseAgentLimits.self, from: JSONEncoder().encode(limits)), limits)
        XCTAssertEqual(try JSONDecoder().decode(ComputerUseAgentResult.self, from: JSONEncoder().encode(result)), result)
    }

    func testAgentLimitValidationAndInterventionMessages() {
        XCTAssertNil(ComputerUseAgentLimits().validationMessage)
        XCTAssertEqual(
            ComputerUseAgentLimits(maxActions: 0).validationMessage,
            "maxActions must be greater than zero"
        )
        XCTAssertEqual(
            ComputerUseAgentLimits(maxFailures: 0).validationMessage,
            "maxFailures must be greater than zero"
        )
        XCTAssertEqual(
            ComputerUseAgentLimits(maxDuration: 0).validationMessage,
            "maxDuration must be finite and greater than zero"
        )
        XCTAssertEqual(
            ComputerUseAgentLimits(settleDelay: -0.1).validationMessage,
            "settleDelay must be finite and non-negative"
        )

        XCTAssertEqual(
            ComputerUseIntervention.frontmostApplicationChanged.message,
            "The frontmost application changed."
        )
        XCTAssertEqual(
            ComputerUseIntervention.targetWindowChanged.message,
            "The target window changed or is no longer key."
        )
        XCTAssertEqual(
            ComputerUseIntervention.userStopped.message,
            "The user stopped the Computer Use session."
        )
    }

    func testModelErrorsAndSafeDefaultServicesHaveDescriptions() async throws {
        let errors: [ComputerUseModelError] = [
            .notConfigured,
            .invalidResponse("missing kind"),
            .requestFailed("timeout"),
        ]
        for error in errors {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }

        let model = UnconfiguredComputerUseModelClient()
        do {
            _ = try await model.decide(
                request: ComputerUseModelRequest(
                    instruction: "task",
                    observation: makePhase3Observation(generation: 1),
                    recentActionResults: [],
                    iteration: 1
                ),
                cancellation: ComputerUseCancellationToken()
            )
            XCTFail("Expected the unconfigured model to fail")
        } catch let error as ComputerUseModelError {
            XCTAssertEqual(error, .notConfigured)
        }

        let approval = DenyAllComputerUseApprovalService()
        let request = ComputerUseApprovalRequest(
            id: UUID(),
            action: .scroll(horizontal: 0, vertical: -10),
            target: makePhase3Observation(generation: 1).target,
            risk: .scroll,
            reason: "test"
        )
        let approvalDecision = await approval.requestApproval(
            request,
            cancellation: ComputerUseCancellationToken()
        )
        XCTAssertEqual(approvalDecision, .deny)
    }
}

@MainActor
final class ComputerUsePhase3AgentTests: XCTestCase {
    func testInvalidTasksAndLimitsFailBeforePlatformCalls() async {
        let observation = Phase3StubObservationService(result: makePhase3Observation(generation: 1))
        let model = Phase3ScriptedModelClient(decisions: [.completed(message: "done")])
        let agent = makeAgent(model: model, observation: observation)

        let emptyInstruction = await agent.run(
            task: ComputerUseAgentTask(instruction: "  ", applicationID: "target#42")
        )
        XCTAssertEqual(emptyInstruction.phase, .failed)
        XCTAssertTrue(observation.applicationIDs.isEmpty)

        let emptyTarget = await agent.run(
            task: ComputerUseAgentTask(instruction: "Do it", applicationID: "")
        )
        XCTAssertEqual(emptyTarget.phase, .failed)
        XCTAssertEqual(observation.observeCount, 0)

        let invalidLimitsAgent = makeAgent(
            model: model,
            observation: observation,
            limits: ComputerUseAgentLimits(maxActions: 0)
        )
        let invalidLimits = await invalidLimitsAgent.run(
            task: ComputerUseAgentTask(instruction: "Do it", applicationID: "target#42")
        )
        XCTAssertEqual(invalidLimits.phase, .failed)
        XCTAssertTrue(invalidLimits.message.contains("maxActions"))
        XCTAssertEqual(observation.observeCount, 0)
    }

    func testAgentReturnsCompletedAskUserAndBlockedDecisions() async {
        let cases: [(ComputerUseModelDecision, ComputerUseAgentPhase, String?)] = [
            (.completed(message: "Finished"), .completed, nil),
            (.askUser(question: "Need a choice"), .askingUser, "Need a choice"),
            (.blocked(reason: "Not allowed"), .blocked, nil),
        ]

        for (decision, expectedPhase, expectedQuestion) in cases {
            let observation = Phase3StubObservationService(result: makePhase3Observation(generation: 1))
            let model = Phase3ScriptedModelClient(decisions: [decision])
            let agent = makeAgent(model: model, observation: observation)
            let result = await agent.run(
                task: ComputerUseAgentTask(instruction: "Do it", applicationID: "target#42")
            )

            XCTAssertEqual(result.phase, expectedPhase)
            XCTAssertEqual(result.question, expectedQuestion)
            XCTAssertEqual(observation.observeCount, 1)
        }
    }

    func testAgentRequiresAConfiguredModel() async {
        let observation = Phase3StubObservationService(result: makePhase3Observation(generation: 1))
        let agent = makeAgent(
            model: UnconfiguredComputerUseModelClient(),
            observation: observation
        )

        let result = await agent.run(
            task: ComputerUseAgentTask(instruction: "Do it", applicationID: "target#42")
        )

        XCTAssertEqual(result.phase, .failed)
        XCTAssertTrue(result.message.contains("No Computer Use model"))
        XCTAssertEqual(observation.observeCount, 1)
    }

    func testAgentStopsOnObservationFailureAndIntervention() async {
        let failedObservation = Phase3StubObservationService(
            result: makePhase3Observation(generation: 1),
            error: ComputerUseObservationError.screenshotUnavailable
        )
        let failedAgent = makeAgent(
            model: Phase3ScriptedModelClient(decisions: [.completed(message: "done")]),
            observation: failedObservation
        )
        let failed = await failedAgent.run(
            task: ComputerUseAgentTask(instruction: "Do it", applicationID: "target#42")
        )
        XCTAssertEqual(failed.phase, .failed)
        XCTAssertEqual(failed.message, ComputerUseObservationError.screenshotUnavailable.errorDescription)

        let observation = Phase3StubObservationService(result: makePhase3Observation(generation: 1))
        let intervention = Phase3StubInterventionMonitor(interventions: [.frontmostApplicationChanged])
        let model = Phase3ScriptedModelClient(decisions: [.completed(message: "done")])
        let agent = makeAgent(model: model, observation: observation, intervention: intervention)
        let intervened = await agent.run(
            task: ComputerUseAgentTask(instruction: "Do it", applicationID: "target#42")
        )

        XCTAssertEqual(intervened.phase, .userIntervened)
        XCTAssertEqual(model.requests.count, 0)
    }

    func testAgentApprovesActionReobservesAndPassesRecentResultsToTheModel() async {
        let first = makePhase3Observation(generation: 1)
        let second = makePhase3Observation(generation: 2)
        let observation = Phase3StubObservationService(results: [first, second])
        let action = ComputerUseAction.click(point: ComputerUsePoint(x: 50, y: 50))
        let model = Phase3ScriptedModelClient(
            decisions: [.action(action), .completed(message: "Finished")]
        )
        let approval = Phase3StubApprovalService(decisions: [.allowOnce])
        let actionService = Phase3StubActionService()
        let agent = makeAgent(
            model: model,
            approval: approval,
            observation: observation,
            actionService: actionService
        )

        let result = await agent.run(
            task: ComputerUseAgentTask(instruction: "Click the button", applicationID: "target#42")
        )

        XCTAssertEqual(result.phase, .completed)
        XCTAssertEqual(result.actionResults.count, 1)
        XCTAssertEqual(result.actionResults[0].action, action)
        XCTAssertEqual(observation.observeCount, 2)
        XCTAssertEqual(approval.requests.count, 1)
        XCTAssertEqual(model.requests.map(\.iteration), [1, 2])
        XCTAssertEqual(model.requests[0].recentActionResults.count, 0)
        XCTAssertEqual(model.requests[1].recentActionResults.count, 1)
        XCTAssertTrue(model.requests[1].recentFailureMessages.isEmpty)
        XCTAssertEqual(actionService.requestIDs.count, 1)
        XCTAssertEqual(actionService.requestIDs[0], approval.requests[0].id)
    }

    func testAgentStopsForDeniedAndStoppedApprovals() async {
        let decisions: [(ComputerUseApprovalDecision, ComputerUseAgentPhase, String)] = [
            (.deny, .blocked, "denied"),
            (.stopSession, .cancelled, "stopped"),
        ]

        for (approvalDecision, phase, expectedText) in decisions {
            let observation = Phase3StubObservationService(result: makePhase3Observation(generation: 1))
            let model = Phase3ScriptedModelClient(
                decisions: [.action(.scroll(horizontal: 0, vertical: -10))]
            )
            let approval = Phase3StubApprovalService(decisions: [approvalDecision])
            let actionService = Phase3StubActionService()
            let agent = makeAgent(
                model: model,
                approval: approval,
                observation: observation,
                actionService: actionService
            )

            let result = await agent.run(
                task: ComputerUseAgentTask(instruction: "Scroll", applicationID: "target#42")
            )

            XCTAssertEqual(result.phase, phase)
            XCTAssertTrue(result.message.localizedCaseInsensitiveContains(expectedText))
            XCTAssertTrue(actionService.actions.isEmpty)
        }
    }

    func testAgentRetriesBoundedModelAndModelDecisionFailures() async {
        let observation = Phase3StubObservationService(
            results: [
                makePhase3Observation(generation: 1),
                makePhase3Observation(generation: 2),
                makePhase3Observation(generation: 3),
            ]
        )
        let model = Phase3ScriptedModelClient(
            decisions: [
                .retryableFailure(reason: "try again"),
                .completed(message: "done"),
            ]
        )
        let agent = makeAgent(model: model, observation: observation)
        let result = await agent.run(
            task: ComputerUseAgentTask(instruction: "Do it", applicationID: "target#42")
        )
        XCTAssertEqual(result.phase, .completed)
        XCTAssertEqual(result.failureCount, 1)
        XCTAssertEqual(observation.observeCount, 2)

        let invalidModel = Phase3ScriptedModelClient(
            decisions: [.completed(message: "done")],
            errors: [ComputerUseModelError.invalidResponse("missing action")]
        )
        let invalidObservation = Phase3StubObservationService(
            results: [makePhase3Observation(generation: 1), makePhase3Observation(generation: 2)]
        )
        let invalidAgent = makeAgent(model: invalidModel, observation: invalidObservation)
        let invalidResult = await invalidAgent.run(
            task: ComputerUseAgentTask(instruction: "Do it", applicationID: "target#42")
        )
        XCTAssertEqual(invalidResult.phase, .completed)
        XCTAssertEqual(invalidResult.failureCount, 1)
        XCTAssertEqual(
            invalidModel.requests[1].recentFailureMessages,
            [ComputerUseModelError.invalidResponse("missing action").localizedDescription]
        )

        let emptyDecisionModel = Phase3ScriptedModelClient(
            decisions: [
                .completed(message: "  "),
                .completed(message: "done"),
            ]
        )
        let emptyDecisionObservation = Phase3StubObservationService(
            results: [makePhase3Observation(generation: 1), makePhase3Observation(generation: 2)]
        )
        let emptyDecisionAgent = makeAgent(
            model: emptyDecisionModel,
            observation: emptyDecisionObservation
        )
        let emptyDecisionResult = await emptyDecisionAgent.run(
            task: ComputerUseAgentTask(instruction: "Do it", applicationID: "target#42")
        )
        XCTAssertEqual(emptyDecisionResult.phase, .completed)
        XCTAssertEqual(emptyDecisionResult.failureCount, 1)
        XCTAssertEqual(
            emptyDecisionModel.requests[1].recentFailureMessages,
            ["The model returned an empty completion message."]
        )
    }

    func testAgentStopsAtFailureLimitForInvalidActionsAndActionErrors() async {
        let invalidObservation = Phase3StubObservationService(result: makePhase3Observation(generation: 1))
        let invalidModel = Phase3ScriptedModelClient(
            decisions: [.action(.click(point: ComputerUsePoint(x: 900, y: 900)))]
        )
        let invalidAgent = makeAgent(
            model: invalidModel,
            observation: invalidObservation,
            limits: ComputerUseAgentLimits(maxFailures: 1)
        )
        let invalidResult = await invalidAgent.run(
            task: ComputerUseAgentTask(instruction: "Click", applicationID: "target#42")
        )
        XCTAssertEqual(invalidResult.phase, .failed)
        XCTAssertEqual(invalidResult.failureCount, 1)

        let actionObservation = Phase3StubObservationService(
            results: [
                makePhase3Observation(generation: 1),
                makePhase3Observation(generation: 2),
            ]
        )
        let actionModel = Phase3ScriptedModelClient(
            decisions: [
                .action(.scroll(horizontal: 0, vertical: -10)),
                .action(.scroll(horizontal: 0, vertical: -10)),
            ]
        )
        let actionService = Phase3StubActionService(
            errors: [
                ComputerUseActionError.eventCreationFailed,
                ComputerUseActionError.eventCreationFailed,
            ]
        )
        let actionAgent = makeAgent(
            model: actionModel,
            approval: Phase3StubApprovalService(decisions: [.allowOnce, .allowOnce]),
            observation: actionObservation,
            actionService: actionService,
            limits: ComputerUseAgentLimits(maxFailures: 2)
        )
        let actionResult = await actionAgent.run(
            task: ComputerUseAgentTask(instruction: "Scroll", applicationID: "target#42")
        )
        XCTAssertEqual(actionResult.phase, .failed)
        XCTAssertEqual(actionResult.failureCount, 2)
    }

    func testAgentClassifiesTargetInterventionAndActionLimit() async {
        let observation = Phase3StubObservationService(result: makePhase3Observation(generation: 1))
        let model = Phase3ScriptedModelClient(
            decisions: [.action(.scroll(horizontal: 0, vertical: -10))]
        )
        let approval = Phase3StubApprovalService(decisions: [.allowOnce])
        let intervention = Phase3StubInterventionMonitor(
            interventions: [nil, .frontmostApplicationChanged]
        )
        let actionService = Phase3StubActionService()
        let agent = makeAgent(
            model: model,
            approval: approval,
            observation: observation,
            actionService: actionService,
            intervention: intervention
        )
        let intervened = await agent.run(
            task: ComputerUseAgentTask(instruction: "Scroll", applicationID: "target#42")
        )
        XCTAssertEqual(intervened.phase, .userIntervened)
        XCTAssertTrue(actionService.actions.isEmpty)

        let limitObservation = Phase3StubObservationService(result: makePhase3Observation(generation: 1))
        let limitAgent = makeAgent(
            model: Phase3ScriptedModelClient(
                decisions: [.action(.scroll(horizontal: 0, vertical: -10))]
            ),
            approval: Phase3StubApprovalService(decisions: [.allowOnce]),
            observation: limitObservation,
            limits: ComputerUseAgentLimits(maxActions: 1)
        )
        let limited = await limitAgent.run(
            task: ComputerUseAgentTask(instruction: "Scroll", applicationID: "target#42")
        )
        XCTAssertEqual(limited.phase, .failed)
        XCTAssertEqual(limited.actionResults.count, 1)
        XCTAssertTrue(limited.message.contains("action limit"))
    }

    func testAgentHandlesCancellationAtEachAsyncBoundary() async {
        let before = ComputerUseCancellationToken()
        before.cancel()
        let beforeObservation = Phase3StubObservationService(result: makePhase3Observation(generation: 1))
        let beforeAgent = makeAgent(
            model: Phase3ScriptedModelClient(decisions: [.completed(message: "done")]),
            observation: beforeObservation
        )
        let beforeResult = await beforeAgent.run(
            task: ComputerUseAgentTask(instruction: "Do it", applicationID: "target#42"),
            cancellation: before
        )
        XCTAssertEqual(beforeResult.phase, .cancelled)
        XCTAssertEqual(beforeObservation.observeCount, 0)

        let observationCancelled = Phase3StubObservationService(
            result: makePhase3Observation(generation: 1),
            error: ComputerUseObservationError.cancelled
        )
        let observationAgent = makeAgent(
            model: Phase3ScriptedModelClient(decisions: [.completed(message: "done")]),
            observation: observationCancelled
        )
        let observationResult = await observationAgent.run(
            task: ComputerUseAgentTask(instruction: "Do it", applicationID: "target#42")
        )
        XCTAssertEqual(observationResult.phase, .cancelled)

        let modelCancellation = ComputerUseCancellationToken()
        let cancellingModel = Phase3ScriptedModelClient(decisions: [.completed(message: "done")])
        cancellingModel.onDecide = { _ in
            modelCancellation.cancel()
            throw ComputerUseModelError.requestFailed("canceled")
        }
        let modelAgent = makeAgent(
            model: cancellingModel,
            observation: Phase3StubObservationService(result: makePhase3Observation(generation: 1))
        )
        let modelResult = await modelAgent.run(
            task: ComputerUseAgentTask(instruction: "Do it", applicationID: "target#42"),
            cancellation: modelCancellation
        )
        XCTAssertEqual(modelResult.phase, .cancelled)

        let approvalCancellation = ComputerUseCancellationToken()
        let cancellingApproval = Phase3StubApprovalService(decisions: [.allowOnce])
        cancellingApproval.onRequest = { _ in
            approvalCancellation.cancel()
        }
        let approvalAgent = makeAgent(
            model: Phase3ScriptedModelClient(
                decisions: [.action(.scroll(horizontal: 0, vertical: -10))]
            ),
            approval: cancellingApproval,
            observation: Phase3StubObservationService(result: makePhase3Observation(generation: 1))
        )
        let approvalResult = await approvalAgent.run(
            task: ComputerUseAgentTask(instruction: "Scroll", applicationID: "target#42"),
            cancellation: approvalCancellation
        )
        XCTAssertEqual(approvalResult.phase, .cancelled)
    }

    func testAgentHandlesActionCancellationAndSettleCancellation() async {
        let actionCancellation = ComputerUseCancellationToken()
        let actionService = Phase3StubActionService()
        actionService.onExecute = { _ in
            actionCancellation.cancel()
            throw ComputerUseActionError.cancelled
        }
        let actionAgent = makeAgent(
            model: Phase3ScriptedModelClient(
                decisions: [.action(.scroll(horizontal: 0, vertical: -10))]
            ),
            approval: Phase3StubApprovalService(decisions: [.allowOnce]),
            observation: Phase3StubObservationService(result: makePhase3Observation(generation: 1)),
            actionService: actionService
        )
        let actionResult = await actionAgent.run(
            task: ComputerUseAgentTask(instruction: "Scroll", applicationID: "target#42"),
            cancellation: actionCancellation
        )
        XCTAssertEqual(actionResult.phase, .cancelled)

        let settleCancellation = ComputerUseCancellationToken()
        let settleAgent = makeAgent(
            model: Phase3ScriptedModelClient(
                decisions: [
                    .action(.scroll(horizontal: 0, vertical: -10)),
                ]
            ),
            approval: Phase3StubApprovalService(decisions: [.allowOnce]),
            observation: Phase3StubObservationService(result: makePhase3Observation(generation: 1)),
            sleep: { _ in
                settleCancellation.cancel()
                throw CancellationError()
            }
        )
        let settleResult = await settleAgent.run(
            task: ComputerUseAgentTask(instruction: "Scroll", applicationID: "target#42"),
            cancellation: settleCancellation
        )
        XCTAssertEqual(settleResult.phase, .cancelled)
    }

    func testAgentPropagatesFailuresAndStopsAtEachFailureLimit() async {
        let observations = Phase3StubObservationService(
            results: (1...5).map { makePhase3Observation(generation: UInt64($0)) }
        )
        let model = Phase3ScriptedModelClient(
            decisions: [
                .retryableFailure(reason: "one"),
                .retryableFailure(reason: "two"),
                .retryableFailure(reason: "three"),
                .retryableFailure(reason: "four"),
                .completed(message: "done"),
            ]
        )
        let agent = makeAgent(
            model: model,
            observation: observations,
            limits: ComputerUseAgentLimits(maxFailures: 10)
        )
        let result = await agent.run(
            task: ComputerUseAgentTask(instruction: "Do it", applicationID: "target#42")
        )
        XCTAssertEqual(result.phase, .completed)
        XCTAssertEqual(result.failureCount, 4)
        XCTAssertEqual(model.requests[4].recentFailureMessages, ["two", "three", "four"])

        let modelErrorAgent = makeAgent(
            model: Phase3ScriptedModelClient(
                errors: [ComputerUseModelError.requestFailed("network")]
            ),
            observation: Phase3StubObservationService(result: makePhase3Observation(generation: 1)),
            limits: ComputerUseAgentLimits(maxFailures: 1)
        )
        let modelErrorResult = await modelErrorAgent.run(
            task: ComputerUseAgentTask(instruction: "Do it", applicationID: "target#42")
        )
        XCTAssertEqual(modelErrorResult.phase, .failed)
        XCTAssertEqual(modelErrorResult.failureCount, 1)

        let invalidDecisionAgent = makeAgent(
            model: Phase3ScriptedModelClient(decisions: [.completed(message: " ")]),
            observation: Phase3StubObservationService(result: makePhase3Observation(generation: 1)),
            limits: ComputerUseAgentLimits(maxFailures: 1)
        )
        let invalidDecisionResult = await invalidDecisionAgent.run(
            task: ComputerUseAgentTask(instruction: "Do it", applicationID: "target#42")
        )
        XCTAssertEqual(invalidDecisionResult.phase, .failed)
        XCTAssertEqual(invalidDecisionResult.failureCount, 1)

        let retryLimitAgent = makeAgent(
            model: Phase3ScriptedModelClient(
                decisions: [.retryableFailure(reason: "stop")]
            ),
            observation: Phase3StubObservationService(result: makePhase3Observation(generation: 1)),
            limits: ComputerUseAgentLimits(maxFailures: 1)
        )
        let retryLimitResult = await retryLimitAgent.run(
            task: ComputerUseAgentTask(instruction: "Do it", applicationID: "target#42")
        )
        XCTAssertEqual(retryLimitResult.phase, .failed)
        XCTAssertEqual(retryLimitResult.failureCount, 1)
    }

    func testAgentCoversPostActionCancellationTimeoutAndFailurePaths() async {
        let postActionCancellation = ComputerUseCancellationToken()
        let postActionAgent = makeAgent(
            model: Phase3ScriptedModelClient(
                decisions: [
                    .action(.scroll(horizontal: 0, vertical: -10)),
                    .completed(message: "done"),
                ]
            ),
            approval: Phase3StubApprovalService(decisions: [.allowOnce]),
            observation: Phase3StubObservationService(
                results: [makePhase3Observation(generation: 1), makePhase3Observation(generation: 2)]
            ),
            sleep: { _ in
                postActionCancellation.cancel()
            }
        )
        let postActionResult = await postActionAgent.run(
            task: ComputerUseAgentTask(instruction: "Scroll", applicationID: "target#42"),
            cancellation: postActionCancellation
        )
        XCTAssertEqual(postActionResult.phase, .cancelled)
        XCTAssertEqual(postActionResult.actionResults.count, 1)

        let modelCancellation = ComputerUseCancellationToken()
        let cancellingModel = Phase3ScriptedModelClient(decisions: [.completed(message: "done")])
        cancellingModel.onDecide = { _ in
            modelCancellation.cancel()
        }
        let modelCancellationResult = await makeAgent(
            model: cancellingModel,
            observation: Phase3StubObservationService(result: makePhase3Observation(generation: 1))
        ).run(
            task: ComputerUseAgentTask(instruction: "Do it", applicationID: "target#42"),
            cancellation: modelCancellation
        )
        XCTAssertEqual(modelCancellationResult.phase, .cancelled)

        let timeLimitClock = Phase3Clock(values: [
            Date(timeIntervalSince1970: 0),
            Date(timeIntervalSince1970: 0),
            Date(timeIntervalSince1970: 2),
        ])
        let timeLimitAgent = makeAgent(
            model: Phase3ScriptedModelClient(
                decisions: [.action(.scroll(horizontal: 0, vertical: -10))]
            ),
            approval: Phase3StubApprovalService(decisions: [.allowOnce]),
            observation: Phase3StubObservationService(result: makePhase3Observation(generation: 1)),
            limits: ComputerUseAgentLimits(maxDuration: 1),
            dateProvider: { timeLimitClock.next() }
        )
        let timeLimitResult = await timeLimitAgent.run(
            task: ComputerUseAgentTask(instruction: "Scroll", applicationID: "target#42")
        )
        XCTAssertEqual(timeLimitResult.phase, .failed)
        XCTAssertEqual(timeLimitResult.actionResults.count, 1)
        XCTAssertTrue(timeLimitResult.message.contains("time limit"))

        let cancellationErrorAgent = makeAgent(
            model: Phase3ScriptedModelClient(
                decisions: [.action(.scroll(horizontal: 0, vertical: -10))]
            ),
            approval: Phase3StubApprovalService(decisions: [.allowOnce]),
            observation: Phase3StubObservationService(result: makePhase3Observation(generation: 1)),
            sleep: { _ in throw CancellationError() }
        )
        let cancellationErrorResult = await cancellationErrorAgent.run(
            task: ComputerUseAgentTask(instruction: "Scroll", applicationID: "target#42")
        )
        XCTAssertEqual(cancellationErrorResult.phase, .cancelled)

        let sleepFailureAgent = makeAgent(
            model: Phase3ScriptedModelClient(
                decisions: [.action(.scroll(horizontal: 0, vertical: -10))]
            ),
            approval: Phase3StubApprovalService(decisions: [.allowOnce]),
            observation: Phase3StubObservationService(result: makePhase3Observation(generation: 1)),
            limits: ComputerUseAgentLimits(maxFailures: 1),
            sleep: { _ in throw Phase3TestError.sleepFailed }
        )
        let sleepFailureResult = await sleepFailureAgent.run(
            task: ComputerUseAgentTask(instruction: "Scroll", applicationID: "target#42")
        )
        XCTAssertEqual(sleepFailureResult.phase, .failed)
        XCTAssertEqual(sleepFailureResult.actionResults.count, 1)
        XCTAssertTrue(sleepFailureResult.message.contains("failure limit"))

        let targetChangedActionAgent = makeAgent(
            model: Phase3ScriptedModelClient(
                decisions: [.action(.scroll(horizontal: 0, vertical: -10))]
            ),
            approval: Phase3StubApprovalService(decisions: [.allowOnce]),
            observation: Phase3StubObservationService(result: makePhase3Observation(generation: 1)),
            actionService: Phase3StubActionService(
                errors: [ComputerUseActionError.targetNotFrontmost]
            )
        )
        let targetChangedActionResult = await targetChangedActionAgent.run(
            task: ComputerUseAgentTask(instruction: "Scroll", applicationID: "target#42")
        )
        XCTAssertEqual(targetChangedActionResult.phase, .userIntervened)
    }

    func testAgentUsesDefaultSettlingClosure() async {
        let agent = ComputerUseAgent(
            modelClient: Phase3ScriptedModelClient(
                decisions: [
                    .action(.scroll(horizontal: 0, vertical: -10)),
                    .completed(message: "done"),
                ]
            ),
            approvalService: Phase3StubApprovalService(decisions: [.allowOnce]),
            observationService: Phase3StubObservationService(
                results: [makePhase3Observation(generation: 1), makePhase3Observation(generation: 2)]
            ),
            actionService: Phase3StubActionService(),
            interventionMonitor: Phase3StubInterventionMonitor(),
            limits: ComputerUseAgentLimits(settleDelay: 0.001)
        )
        let result = await agent.run(
            task: ComputerUseAgentTask(instruction: "Scroll", applicationID: "target#42")
        )
        XCTAssertEqual(result.phase, .completed)
        XCTAssertEqual(result.actionResults.count, 1)
    }

    func testAgentStopsOnTimeLimit() async {
        let clock = Phase3Clock(values: [
            Date(timeIntervalSince1970: 0),
            Date(timeIntervalSince1970: 2),
        ])
        let observation = Phase3StubObservationService(result: makePhase3Observation(generation: 1))
        let agent = makeAgent(
            model: Phase3ScriptedModelClient(decisions: [.completed(message: "done")]),
            observation: observation,
            limits: ComputerUseAgentLimits(maxDuration: 1),
            dateProvider: { clock.next() }
        )

        let result = await agent.run(
            task: ComputerUseAgentTask(instruction: "Do it", applicationID: "target#42")
        )

        XCTAssertEqual(result.phase, .failed)
        XCTAssertTrue(result.message.contains("time limit"))
        XCTAssertEqual(observation.observeCount, 0)
    }

    private func makeAgent(
        model: ComputerUseModelClient,
        approval: ComputerUseApprovalRequesting = Phase3StubApprovalService(decisions: [.deny]),
        observation: ComputerUseObservationServicing,
        actionService: ComputerUseActionServicing = Phase3StubActionService(),
        intervention: ComputerUseInterventionMonitoring = Phase3StubInterventionMonitor(),
        limits: ComputerUseAgentLimits = ComputerUseAgentLimits(settleDelay: 0),
        dateProvider: @escaping () -> Date = { Date(timeIntervalSince1970: 10_000) },
        sleep: @escaping (TimeInterval) async throws -> Void = { _ in }
    ) -> ComputerUseAgent {
        ComputerUseAgent(
            modelClient: model,
            approvalService: approval,
            observationService: observation,
            actionService: actionService,
            interventionMonitor: intervention,
            limits: limits,
            dateProvider: dateProvider,
            sleep: sleep
        )
    }
}

final class ComputerUsePhase3InterventionTests: XCTestCase {
    func testSystemInterventionMonitorDetectsProcessAndWindowChanges() {
        let observation = makePhase3Observation(generation: 1)
        let application = observation.target.application
        let window = observation.target.window
        let discovery = Phase3StubWindowDiscovery(windows: [window])
        var frontmost: Int32? = application.processIdentifier
        let monitor = SystemComputerUseInterventionMonitor(
            windowDiscovery: discovery,
            frontmostProcessIdentifierProvider: { frontmost }
        )

        XCTAssertNil(monitor.check(target: observation.target))
        frontmost = 999
        XCTAssertEqual(
            monitor.check(target: observation.target),
            .frontmostApplicationChanged
        )
        frontmost = application.processIdentifier
        discovery.windows = []
        XCTAssertEqual(monitor.check(target: observation.target), .targetWindowChanged)
        discovery.windows = [ComputerUseWindow(
            id: window.id,
            title: window.title,
            ownerProcessIdentifier: window.ownerProcessIdentifier,
            bounds: window.bounds,
            layer: window.layer,
            isOnScreen: window.isOnScreen,
            isKeyWindow: false
        )]
        XCTAssertEqual(monitor.check(target: observation.target), .targetWindowChanged)
    }
}
