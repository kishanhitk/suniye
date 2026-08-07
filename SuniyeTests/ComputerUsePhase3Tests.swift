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
            .target(application: "com.google.Chrome"),
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
        let result = ComputerUseAgentResult(
            phase: .completed,
            message: "Done",
            question: nil,
            latestObservation: observation,
            actionResults: [],
            failureCount: 0
        )
        XCTAssertEqual(try JSONDecoder().decode(ComputerUseAgentTask.self, from: JSONEncoder().encode(task)), task)
        XCTAssertEqual(try JSONDecoder().decode(ComputerUseAgentResult.self, from: JSONEncoder().encode(result)), result)
    }

    func testAgentDecisionValidationAndInterventionMessages() {
        XCTAssertEqual(
            "The user stopped the Computer Use session.",
            "The user stopped the Computer Use session."
        )
        XCTAssertEqual(
            ComputerUseModelDecision.target(application: " ").validationMessage,
            "The model returned an empty target application."
        )
    }

    func testModelErrorsAndUnconfiguredModelHaveDescriptions() async throws {
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

    }
}

@MainActor
final class ComputerUsePhase3AgentTests: XCTestCase {
    func testTaskLeavesStartingApplicationOptional() {
        let task = ComputerUseAgentTask(
            instruction: "Use the active app"
        )

        XCTAssertNil(task.applicationID)
    }

    func testAgentDoesNotInferAnApplicationFromInstructionText() async {
        let selfApplication = ComputerUseApplication(
            id: "dev.suniye.app.preview#99",
            bundleIdentifier: "dev.suniye.app.preview",
            displayName: "Suniye Preview",
            processIdentifier: 99,
            isRunning: true,
            isActive: true
        )
        let chromeApplication = ComputerUseApplication(
            id: "com.google.Chrome#42",
            bundleIdentifier: "com.google.Chrome",
            displayName: "Google Chrome",
            processIdentifier: 42,
            isRunning: true,
            isActive: false
        )
        let observation = Phase3StubObservationService(result: makePhase3Observation(generation: 1))
        let agent = ComputerUseAgent(
            modelClient: Phase3ScriptedModelClient(decisions: [.completed(message: "done")]),
            applicationCatalog: Phase3InstructionApplicationCatalog(
                applications: [selfApplication, chromeApplication]
            ),
            observationService: observation,
            actionService: Phase3StubActionService()
        )

        let result = await agent.run(
            task: ComputerUseAgentTask(
                instruction: "Open Chrome and go to Flipkart.",
                applicationID: selfApplication.id
            )
        )

        XCTAssertEqual(result.phase, .completed)
        XCTAssertEqual(observation.applicationIDs, [selfApplication.id])
    }

    func testAgentDoesNotExcludeAnExplicitSuniyeTarget() async {
        let application = ComputerUseApplication(
            id: "dev.suniye.app.preview#99",
            bundleIdentifier: "dev.suniye.app.preview",
            displayName: "Suniye Preview",
            processIdentifier: 99,
            isRunning: true,
            isActive: true
        )
        let observation = Phase3StubObservationService(result: makePhase3Observation(generation: 1))
        let agent = ComputerUseAgent(
            modelClient: Phase3ScriptedModelClient(decisions: [.completed(message: "done")]),
            applicationCatalog: Phase3InstructionApplicationCatalog(
                applications: [application]
            ),
            observationService: observation,
            actionService: Phase3StubActionService()
        )

        let result = await agent.run(
            task: ComputerUseAgentTask(
                instruction: "Use the active app.",
                applicationID: application.id
            )
        )

        XCTAssertEqual(result.phase, .completed)
        XCTAssertEqual(observation.applicationIDs, [application.id])
    }

    func testInvalidTasksFailBeforePlatformCalls() async {
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

    func testAgentStopsOnObservationFailureAndAllowsTargetChanges() async {
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

        let observation = Phase3StubObservationService(
            results: [
                makePhase3Observation(generation: 1),
                makePhase3Observation(generation: 2),
            ]
        )
        let model = Phase3ScriptedModelClient(
            decisions: [
                .target(application: "com.google.Chrome"),
                .completed(message: "done"),
            ]
        )
        let agent = makeAgent(model: model, observation: observation)
        let switched = await agent.run(
            task: ComputerUseAgentTask(instruction: "Do it", applicationID: "target#42")
        )

        XCTAssertEqual(switched.phase, .completed)
        XCTAssertEqual(observation.applicationIDs, ["target#42", "com.google.Chrome"])
        XCTAssertEqual(model.requests.count, 2)
    }

    func testAgentAutomaticallyExecutesActionReobservesAndPassesRecentResultsToTheModel() async {
        let first = makePhase3Observation(generation: 1)
        let second = makePhase3Observation(generation: 2)
        let observation = Phase3StubObservationService(results: [first, second])
        let action = ComputerUseAction.click(point: ComputerUsePoint(x: 50, y: 50))
        let model = Phase3ScriptedModelClient(
            decisions: [.action(action), .completed(message: "Finished")]
        )
        let actionService = Phase3StubActionService()
        let agent = makeAgent(
            model: model,
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
        XCTAssertEqual(model.requests.map(\.iteration), [1, 2])
        XCTAssertEqual(model.requests[0].recentActionResults.count, 0)
        XCTAssertEqual(model.requests[1].recentActionResults.count, 1)
        XCTAssertTrue(model.requests[1].recentFailureMessages.isEmpty)
        XCTAssertEqual(actionService.requestIDs.count, 1)
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

    func testAgentRecoversWhenTargetWindowDisappearsBeforeTargetSwitch() async {
        let observation = Phase3StubObservationService(
            results: [
                makePhase3Observation(generation: 1),
                makePhase3Observation(generation: 2),
            ],
            errorsByObservation: [
                2: ComputerUseObservationError.noWindow("dev.suniye.app.preview"),
            ]
        )
        let model = Phase3ScriptedModelClient(
            decisions: [
                .retryableFailure(reason: "Choose the requested app."),
                .target(application: "com.panic.Nova"),
                .completed(message: "Recovered."),
            ]
        )
        let agent = makeAgent(model: model, observation: observation)

        let result = await agent.run(
            task: ComputerUseAgentTask(
                instruction: "Open the editor.",
                applicationID: "dev.suniye.app.preview"
            )
        )

        XCTAssertEqual(result.phase, .completed)
        XCTAssertEqual(result.message, "Recovered.")
        XCTAssertEqual(
            observation.applicationIDs,
            ["dev.suniye.app.preview", "dev.suniye.app.preview", "com.panic.Nova"]
        )
        XCTAssertEqual(model.requests.count, 3)
        XCTAssertEqual(
            model.requests[1].recentFailureMessages,
            ["Choose the requested app.", "The application has no visible window: dev.suniye.app.preview."]
        )
    }

    func testAgentForwardsModelActionsAndRetriesActionErrors() async {
        let invalidObservation = Phase3StubObservationService(
            results: [
                makePhase3Observation(generation: 1),
                makePhase3Observation(generation: 2),
            ]
        )
        let invalidModel = Phase3ScriptedModelClient(
            decisions: [
                .action(.scroll(elementIndex: 999, direction: .up)),
                .completed(message: "done"),
            ]
        )
        let invalidAgent = makeAgent(
            model: invalidModel,
            observation: invalidObservation
        )
        let invalidResult = await invalidAgent.run(
            task: ComputerUseAgentTask(instruction: "Click", applicationID: "target#42")
        )
        XCTAssertEqual(invalidResult.phase, .completed)
        XCTAssertEqual(invalidResult.failureCount, 0)
        XCTAssertEqual(invalidResult.actionResults.count, 1)

        let actionObservation = Phase3StubObservationService(
            results: [
                makePhase3Observation(generation: 1),
                makePhase3Observation(generation: 2),
                makePhase3Observation(generation: 3),
            ]
        )
        let actionModel = Phase3ScriptedModelClient(
            decisions: [
                .action(.scroll(elementIndex: 0, direction: .up)),
                .action(.scroll(elementIndex: 0, direction: .up)),
                .completed(message: "done"),
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
            observation: actionObservation,
            actionService: actionService
        )
        let actionResult = await actionAgent.run(
            task: ComputerUseAgentTask(instruction: "Scroll", applicationID: "target#42")
        )
        XCTAssertEqual(actionResult.phase, .completed)
        XCTAssertEqual(actionResult.failureCount, 2)
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
                decisions: [.action(.scroll(elementIndex: 0, direction: .up))]
            ),
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
                    .action(.scroll(elementIndex: 0, direction: .up)),
                ]
            ),
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

    func testAgentPropagatesFailuresUntilTheModelCompletes() async {
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
            observation: observations
        )
        let result = await agent.run(
            task: ComputerUseAgentTask(instruction: "Do it", applicationID: "target#42")
        )
        XCTAssertEqual(result.phase, .completed)
        XCTAssertEqual(result.failureCount, 4)
        XCTAssertEqual(model.requests[4].recentFailureMessages, ["one", "two", "three", "four"])

        let modelErrorAgent = makeAgent(
            model: Phase3ScriptedModelClient(
                decisions: [.completed(message: "done")],
                errors: [ComputerUseModelError.requestFailed("network")]
            ),
            observation: Phase3StubObservationService(
                results: [
                    makePhase3Observation(generation: 1),
                    makePhase3Observation(generation: 2),
                ]
            )
        )
        let modelErrorResult = await modelErrorAgent.run(
            task: ComputerUseAgentTask(instruction: "Do it", applicationID: "target#42")
        )
        XCTAssertEqual(modelErrorResult.phase, .completed)
        XCTAssertEqual(modelErrorResult.failureCount, 1)

        let invalidDecisionAgent = makeAgent(
            model: Phase3ScriptedModelClient(
                decisions: [
                    .completed(message: " "),
                    .completed(message: "done"),
                ]
            ),
            observation: Phase3StubObservationService(
                results: [
                    makePhase3Observation(generation: 1),
                    makePhase3Observation(generation: 2),
                ]
            )
        )
        let invalidDecisionResult = await invalidDecisionAgent.run(
            task: ComputerUseAgentTask(instruction: "Do it", applicationID: "target#42")
        )
        XCTAssertEqual(invalidDecisionResult.phase, .completed)
        XCTAssertEqual(invalidDecisionResult.failureCount, 1)

        let retryAgent = makeAgent(
            model: Phase3ScriptedModelClient(
                decisions: [
                    .retryableFailure(reason: "stop"),
                    .completed(message: "done"),
                ]
            ),
            observation: Phase3StubObservationService(
                results: [
                    makePhase3Observation(generation: 1),
                    makePhase3Observation(generation: 2),
                ]
            )
        )
        let retryResult = await retryAgent.run(
            task: ComputerUseAgentTask(instruction: "Do it", applicationID: "target#42")
        )
        XCTAssertEqual(retryResult.phase, .completed)
        XCTAssertEqual(retryResult.failureCount, 1)
    }

    func testAgentCoversPostActionCancellationTimeoutAndFailurePaths() async {
        let postActionCancellation = ComputerUseCancellationToken()
        let postActionAgent = makeAgent(
            model: Phase3ScriptedModelClient(
                decisions: [
                    .action(.scroll(elementIndex: 0, direction: .up)),
                    .completed(message: "done"),
                ]
            ),
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

        let cancellationErrorAgent = makeAgent(
            model: Phase3ScriptedModelClient(
                decisions: [.action(.scroll(elementIndex: 0, direction: .up))]
            ),
            observation: Phase3StubObservationService(result: makePhase3Observation(generation: 1)),
            sleep: { _ in throw CancellationError() }
        )
        let cancellationErrorResult = await cancellationErrorAgent.run(
            task: ComputerUseAgentTask(instruction: "Scroll", applicationID: "target#42")
        )
        XCTAssertEqual(cancellationErrorResult.phase, .cancelled)

        let sleepFailureAgent = makeAgent(
            model: Phase3ScriptedModelClient(
                decisions: [
                    .action(.scroll(elementIndex: 0, direction: .up)),
                    .completed(message: "done"),
                ]
            ),
            observation: Phase3StubObservationService(
                results: [
                    makePhase3Observation(generation: 1),
                    makePhase3Observation(generation: 2),
                ]
            ),
            sleep: { _ in throw Phase3TestError.sleepFailed }
        )
        let sleepFailureResult = await sleepFailureAgent.run(
            task: ComputerUseAgentTask(instruction: "Scroll", applicationID: "target#42")
        )
        XCTAssertEqual(sleepFailureResult.phase, .completed)
        XCTAssertEqual(sleepFailureResult.actionResults.count, 1)
        XCTAssertEqual(sleepFailureResult.failureCount, 1)

        let targetActivationAgent = makeAgent(
            model: Phase3ScriptedModelClient(
                decisions: [
                    .action(.scroll(elementIndex: 0, direction: .up)),
                    .completed(message: "done"),
                ]
            ),
            observation: Phase3StubObservationService(
                results: [
                    makePhase3Observation(generation: 1),
                    makePhase3Observation(generation: 2),
                ]
            ),
            actionService: Phase3StubActionService(
                errors: [ComputerUseActionError.targetActivationFailed]
            )
        )
        let targetActivationResult = await targetActivationAgent.run(
            task: ComputerUseAgentTask(instruction: "Scroll", applicationID: "target#42")
        )
        XCTAssertEqual(targetActivationResult.phase, .completed)
        XCTAssertEqual(targetActivationResult.failureCount, 1)
    }

    func testAgentUsesDefaultSettlingClosure() async {
        let agent = ComputerUseAgent(
            modelClient: Phase3ScriptedModelClient(
                decisions: [
                    .action(.scroll(elementIndex: 0, direction: .up)),
                    .completed(message: "done"),
                ]
            ),
            observationService: Phase3StubObservationService(
                results: [makePhase3Observation(generation: 1), makePhase3Observation(generation: 2)]
            ),
            actionService: Phase3StubActionService()
        )
        let result = await agent.run(
            task: ComputerUseAgentTask(instruction: "Scroll", applicationID: "target#42")
        )
        XCTAssertEqual(result.phase, .completed)
        XCTAssertEqual(result.actionResults.count, 1)
    }

    private func makeAgent(
        model: ComputerUseModelClient,
        observation: ComputerUseObservationServicing,
        actionService: ComputerUseActionServicing = Phase3StubActionService(),
        sleep: @escaping (TimeInterval) async throws -> Void = { _ in }
    ) -> ComputerUseAgent {
        ComputerUseAgent(
            modelClient: model,
            applicationCatalog: Phase3StubApplicationCatalog(),
            observationService: observation,
            actionService: actionService,
            sleep: sleep
        )
    }
}
