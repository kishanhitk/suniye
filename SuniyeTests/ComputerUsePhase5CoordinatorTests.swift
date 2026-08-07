import Foundation
import XCTest
@testable import Suniye

@MainActor
final class ComputerUsePhase5CoordinatorTests: XCTestCase {
    func testAgentExecutesActionsWithoutAnApprovalPrompt() async {
        let observation = makePhase3Observation(generation: 21)
        let action = ComputerUseAction.scroll(elementIndex: 0, direction: .up)
        let model = Phase3ScriptedModelClient(
            decisions: [
                .action(action),
                .completed(message: "Finished automatically."),
            ]
        )
        let actionService = Phase3StubActionService()
        let coordinator = makeCoordinator(
            model: model,
            observation: observation,
            actionService: actionService
        )
        coordinator.agentInstruction = "Scroll down and finish the task."

        coordinator.start()
        await waitForPhase(coordinator, .ready)
        coordinator.startAgent()
        await waitForPhase(coordinator, .agentCompleted)

        XCTAssertEqual(coordinator.agentResult?.phase, .completed)
        XCTAssertEqual(actionService.actions, [action])
        XCTAssertEqual(coordinator.conversation.map(\.role), [.user, .assistant])
        XCTAssertEqual(
            coordinator.conversation.map(\.text),
            ["Scroll down and finish the task.", "Finished automatically."]
        )
        XCTAssertTrue(coordinator.agentInstruction.isEmpty)
    }

    func testFollowUpCarriesTheConversationIntoTheNextModelRequest() async {
        let model = Phase3ScriptedModelClient(
            decisions: [
                .completed(message: "The first task is done."),
                .completed(message: "The follow-up is done."),
            ]
        )
        let coordinator = makeCoordinator(
            model: model,
            observation: makePhase3Observation(generation: 22),
            actionService: Phase3StubActionService()
        )

        coordinator.start()
        await waitForPhase(coordinator, .ready)
        coordinator.agentInstruction = "Open the document."
        coordinator.startAgent()
        await waitForPhase(coordinator, .agentCompleted)

        coordinator.agentInstruction = "Now summarize it."
        coordinator.startAgent()
        await waitForPhase(coordinator, .agentCompleted)

        XCTAssertEqual(model.requests.count, 2)
        XCTAssertTrue(model.requests[0].conversation.isEmpty)
        XCTAssertEqual(
            model.requests[1].conversation.map(\.text),
            ["Open the document.", "The first task is done."]
        )
        XCTAssertEqual(
            coordinator.conversation.map(\.text),
            [
                "Open the document.",
                "The first task is done.",
                "Now summarize it.",
                "The follow-up is done.",
            ]
        )

        coordinator.clearConversation()
        XCTAssertTrue(coordinator.conversation.isEmpty)
        XCTAssertNil(coordinator.agentResult)
    }

    func testConversationControlsRespectActiveRunAndRecordCancellation() {
        let coordinator = makeCoordinator(
            model: Phase3ScriptedModelClient(decisions: [.completed(message: "unused")]),
            observation: makePhase3Observation(generation: 41),
            actionService: Phase3StubActionService()
        )
        coordinator.conversation = [
            ComputerUseConversationMessage(role: .user, text: "Keep this message."),
        ]
        coordinator.phase = .runningAgent

        coordinator.clearConversation()
        XCTAssertEqual(coordinator.conversation.map(\.text), ["Keep this message."])

        coordinator.cancel()
        XCTAssertEqual(coordinator.phase, .ready)
        XCTAssertEqual(
            coordinator.conversation.map(\.text),
            ["Keep this message.", "Stopped."]
        )
    }

    func testVoiceTaskStartsAgentAutomatically() async {
        let coordinator = makeCoordinator(
            model: Phase3ScriptedModelClient(
                decisions: [.completed(message: "Finished from voice.")]
            ),
            observation: makePhase3Observation(generation: 23),
            actionService: Phase3StubActionService()
        )

        coordinator.start()
        await waitForPhase(coordinator, .ready)
        XCTAssertEqual(
            coordinator.submitVoiceTask("Read the current app state."),
            .started
        )
        await waitForPhase(coordinator, .agentCompleted)

        XCTAssertTrue(coordinator.agentInstruction.isEmpty)
        XCTAssertEqual(coordinator.agentResult?.message, "Finished from voice.")
        XCTAssertEqual(coordinator.conversation.first?.text, "Read the current app state.")
        XCTAssertFalse(coordinator.isVoiceTaskPending)
    }

    func testQueuedVoiceTaskUsesCapturedInstructionAfterModelConnects() async {
        let coordinator = makeCoordinator(
            model: Phase3ScriptedModelClient(decisions: [.completed(message: "unused")]),
            observation: makePhase3Observation(generation: 34),
            actionService: Phase3StubActionService()
        )

        coordinator.start()
        await waitForPhase(coordinator, .ready)
        coordinator.configureModel(nil)

        XCTAssertEqual(
            coordinator.submitVoiceTask("  Read the current app state.  "),
            .queued
        )
        XCTAssertTrue(coordinator.isVoiceTaskPending)
        coordinator.agentInstruction = "A later manual edit."

        coordinator.configureModel(
            Phase3ScriptedModelClient(decisions: [.completed(message: "Finished queued voice task.")])
        )
        await waitForPhase(coordinator, .agentCompleted)

        XCTAssertTrue(coordinator.agentInstruction.isEmpty)
        XCTAssertEqual(coordinator.agentResult?.message, "Finished queued voice task.")
        XCTAssertFalse(coordinator.isVoiceTaskPending)
    }

    func testVoiceTaskRejectsEmptyInstruction() {
        let coordinator = makeCoordinator(
            model: Phase3ScriptedModelClient(decisions: [.completed(message: "unused")]),
            observation: makePhase3Observation(generation: 35),
            actionService: Phase3StubActionService()
        )

        XCTAssertEqual(
            coordinator.submitVoiceTask(" \n "),
            .rejected(message: "No Computer Use task was transcribed.")
        )
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertFalse(coordinator.isVoiceTaskPending)
    }

    func testVoiceTaskReportsPreparationAndPermissionWaits() async {
        let coordinator = makeCoordinator(
            model: Phase3ScriptedModelClient(decisions: [.completed(message: "unused")]),
            observation: makePhase3Observation(generation: 36),
            actionService: Phase3StubActionService()
        )

        coordinator.start()
        await waitForPhase(coordinator, .ready)
        coordinator.phase = .loadingApplications
        XCTAssertEqual(
            coordinator.submitVoiceTask("Wait for startup."),
            .queued
        )
        XCTAssertEqual(
            coordinator.errorMessage,
            "Voice task captured. Computer Use is still preparing."
        )
        coordinator.cancel()

        coordinator.phase = .ready
        coordinator.permissionSnapshot = ComputerUsePermissionSnapshot(
            accessibility: .notGranted,
            screenRecording: .notGranted
        )
        XCTAssertEqual(
            coordinator.submitVoiceTask("Wait for permission."),
            .queued
        )
        XCTAssertEqual(
            coordinator.errorMessage,
            "Voice task captured. Grant Computer Use permissions to run it."
        )
        coordinator.cancel()

        coordinator.phase = .runningAgent
        XCTAssertEqual(
            coordinator.submitVoiceTask("Do not interrupt."),
            .rejected(message: "Computer Use is already working.")
        )
        XCTAssertEqual(coordinator.phase, .runningAgent)
    }

    func testRemoteModelConfigurationIsSessionScoped() async {
        let coordinator = makeCoordinator(
            model: Phase3ScriptedModelClient(decisions: [.completed(message: "unused")]),
            observation: makePhase3Observation(generation: 24),
            actionService: Phase3StubActionService()
        )
        let configuration = ComputerUseRemoteModelConfiguration(
            endpointURL: URL(string: "https://example.com/v1/chat/completions")!,
            modelID: "computer-use-model",
            apiKey: "test-key"
        )

        coordinator.start()
        await waitForPhase(coordinator, .ready)
        XCTAssertTrue(coordinator.canRunAgent)

        coordinator.configureRemoteModel(configuration)
        XCTAssertTrue(coordinator.isModelConfigured)
        XCTAssertTrue(coordinator.canRunAgent)
        coordinator.selectedApplicationID = nil
        XCTAssertTrue(coordinator.canRunAgent)

        coordinator.configureRemoteModel(nil)
        XCTAssertFalse(coordinator.isModelConfigured)
        coordinator.configureModel(
            Phase3ScriptedModelClient(decisions: [.completed(message: "unused")])
        )
        XCTAssertTrue(coordinator.isModelConfigured)
    }

    func testAgentPublishesBlockedAndFailedTerminalResults() async {
        let blockedCoordinator = makeCoordinator(
            model: Phase3ScriptedModelClient(decisions: [.blocked(reason: "Blocked by policy.")]),
            observation: makePhase3Observation(generation: 25),
            actionService: Phase3StubActionService()
        )
        blockedCoordinator.agentInstruction = "Try the task."
        blockedCoordinator.start()
        await waitForPhase(blockedCoordinator, .ready)
        blockedCoordinator.startAgent()
        await waitForPhase(blockedCoordinator, .agentCompleted)
        XCTAssertEqual(blockedCoordinator.agentResult?.phase, .blocked)
        XCTAssertNil(blockedCoordinator.errorMessage)

        let failedCoordinator = makeCoordinator(
            model: Phase3ScriptedModelClient(
                decisions: [
                    .retryableFailure(reason: "Not enough state."),
                    .completed(message: "Recovered."),
                ]
            ),
            observation: makePhase3Observation(generation: 26),
            actionService: Phase3StubActionService()
        )
        failedCoordinator.agentInstruction = "Try the task."
        failedCoordinator.start()
        await waitForPhase(failedCoordinator, .ready)
        failedCoordinator.startAgent()
        await waitForPhase(failedCoordinator, .agentCompleted)
        XCTAssertEqual(failedCoordinator.agentResult?.phase, .completed)
        XCTAssertEqual(failedCoordinator.agentResult?.failureCount, 1)
        XCTAssertNil(failedCoordinator.errorMessage)
    }

    func testAgentObservationFailurePublishesFailedCoordinatorPhase() async {
        let observation = makePhase3Observation(generation: 37)
        let coordinator = makeCoordinator(
            model: Phase3ScriptedModelClient(decisions: [.completed(message: "unused")]),
            observation: observation,
            observationService: Phase3StubObservationService(
                result: observation,
                error: ComputerUseObservationError.screenshotUnavailable
            ),
            actionService: Phase3StubActionService()
        )
        coordinator.agentInstruction = "Inspect the app."

        coordinator.start()
        await waitForPhase(coordinator, .ready)
        coordinator.startAgent()
        await waitForPhase(coordinator, .failed)

        XCTAssertEqual(coordinator.agentResult?.phase, .failed)
        XCTAssertEqual(
            coordinator.errorMessage,
            ComputerUseObservationError.screenshotUnavailable.errorDescription
        )
        XCTAssertEqual(coordinator.phaseTitle, "Computer Use failed")
    }

    func testCoordinatorGuardsConfigurationAndAgentState() async {
        let coordinator = makeCoordinator(
            model: Phase3ScriptedModelClient(decisions: [.completed(message: "unused")]),
            observation: makePhase3Observation(generation: 27),
            actionService: Phase3StubActionService()
        )
        let configuration = ComputerUseRemoteModelConfiguration(
            endpointURL: URL(string: "https://example.com/v1/chat/completions")!,
            modelID: "computer-use-model",
            apiKey: "test-key"
        )

        coordinator.start()
        await waitForPhase(coordinator, .ready)
        coordinator.phase = .runningAgent
        coordinator.configureModel(nil)
        coordinator.configureRemoteModel(configuration)
        coordinator.phase = .ready

        coordinator.configureModel(nil)
        coordinator.agentInstruction = "  "
        coordinator.startAgent()
        XCTAssertEqual(coordinator.phase, .failed)
        XCTAssertEqual(coordinator.errorMessage, "Enter a task for Computer Use.")

        coordinator.phase = .ready
        coordinator.agentInstruction = "Try the task."
        coordinator.startAgent()
        XCTAssertEqual(coordinator.phase, .ready)

        coordinator.configureModel(
            Phase3ScriptedModelClient(decisions: [.completed(message: "unused")])
        )
        XCTAssertTrue(coordinator.canRunAgent)

        coordinator.phase = .runningAgent
        XCTAssertEqual(coordinator.phaseTitle, "Computer Use is working")
        coordinator.phase = .agentCompleted
        XCTAssertEqual(coordinator.phaseTitle, "Computer Use finished")
    }

    func testCoordinatorSurfacesPolicyDenial() async {
        let observation = makePhase3Observation(generation: 28)
        let deniedPolicy = ComputerUsePolicyService(
            configuration: ComputerUsePolicyConfiguration(
                deniedBundleIdentifiers: [observation.target.application.bundleIdentifier]
            )
        )
        let deniedCoordinator = makeCoordinator(
            model: Phase3ScriptedModelClient(
                decisions: [.action(.scroll(elementIndex: 0, direction: .up))]
            ),
            observation: observation,
            actionService: Phase3StubActionService(),
            policy: deniedPolicy
        )

        deniedCoordinator.start()
        await waitForPhase(deniedCoordinator, .ready)
        deniedCoordinator.agentInstruction = "Scroll in the target app."
        deniedCoordinator.startAgent()
        await waitForPhase(deniedCoordinator, .agentCompleted)
        XCTAssertEqual(deniedCoordinator.agentResult?.phase, .blocked)
        XCTAssertEqual(
            deniedCoordinator.agentResult?.message,
            "Computer Use is blocked from using Target App by policy."
        )
    }

    func testCoordinatorIgnoresCanceledAndStalePermissionResults() async {
        let permissionManager = Phase5BlockingPermissionManager()
        let firstRequestStarted = expectation(description: "first permission request started")
        permissionManager.setAccessibilityRequestHandler {
            firstRequestStarted.fulfill()
        }
        let coordinator = makeCoordinator(
            model: Phase3ScriptedModelClient(decisions: [.completed(message: "unused")]),
            observation: makePhase3Observation(generation: 32),
            actionService: Phase3StubActionService(),
            permissionManager: permissionManager
        )
        coordinator.start()
        await waitForPhase(coordinator, .ready)

        permissionManager.blockNextAccessibilityRequest()
        coordinator.requestAccessibility()
        await fulfillment(of: [firstRequestStarted], timeout: 1)
        coordinator.refresh()
        permissionManager.releaseRequest()
        await waitForPhase(coordinator, .ready)

        let stalePermissionManager = Phase5BlockingPermissionManager()
        let staleRequestStarted = expectation(description: "stale permission request started")
        stalePermissionManager.setAccessibilityRequestHandler {
            staleRequestStarted.fulfill()
        }
        let staleCoordinator = makeCoordinator(
            model: Phase3ScriptedModelClient(decisions: [.completed(message: "Finished.")]),
            observation: makePhase3Observation(generation: 33),
            actionService: Phase3StubActionService(),
            permissionManager: stalePermissionManager
        )
        staleCoordinator.agentInstruction = "Finish the task."
        staleCoordinator.start()
        await waitForPhase(staleCoordinator, .ready)
        stalePermissionManager.blockNextAccessibilityRequest()
        staleCoordinator.requestAccessibility()
        await fulfillment(of: [staleRequestStarted], timeout: 1)
        staleCoordinator.phase = .ready
        staleCoordinator.startAgent()
        stalePermissionManager.releaseRequest()
        await waitForPhase(staleCoordinator, .agentCompleted)
        XCTAssertEqual(staleCoordinator.agentResult?.phase, .completed)
    }

    private func makeCoordinator(
        model: ComputerUseModelClient,
        observation: ComputerUseObservation,
        observationService: ComputerUseObservationServicing? = nil,
        actionService: ComputerUseActionServicing,
        permissionManager: ComputerUsePermissionManaging = Phase5PermissionManager(),
        policy: ComputerUsePolicyChecking? = nil
    ) -> ComputerUseCoordinator {
        let coordinator = ComputerUseCoordinator(
            applicationCatalog: Phase5ApplicationCatalog(application: observation.target.application),
            permissionManager: permissionManager,
            observationService: observationService ?? Phase3StubObservationService(result: observation),
            actionService: actionService,
            policy: policy,
            modelClient: model
        )
        coordinator.selectedApplicationID = observation.target.application.id
        return coordinator
    }

    private func waitForPhase(
        _ coordinator: ComputerUseCoordinator,
        _ expected: ComputerUseCoordinatorPhase,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0 ..< 200 {
            if coordinator.phase == expected {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        let error = coordinator.errorMessage ?? "none"
        let agentMessage = coordinator.agentResult?.message ?? "none"
        XCTFail(
            "Timed out waiting for phase \(expected), got \(coordinator.phase), error=\(error), agent=\(agentMessage)",
            file: file,
            line: line
        )
    }
}

private final class Phase5ApplicationCatalog: ComputerUseApplicationCatalog {
    let application: ComputerUseApplication

    init(application: ComputerUseApplication) {
        self.application = application
    }

    func listApplications() -> [ComputerUseApplication] {
        [application]
    }

    func application(withID identifier: String) -> ComputerUseApplication? {
        identifier == application.id ? application : nil
    }
}

private final class Phase5PermissionManager: ComputerUsePermissionManaging {
    func snapshot() -> ComputerUsePermissionSnapshot {
        ComputerUsePermissionSnapshot(
            accessibility: .granted,
            screenRecording: .granted
        )
    }

    func requestAccessibility() -> Bool {
        true
    }

    func requestScreenRecording() -> Bool {
        true
    }
}

private final class Phase5BlockingPermissionManager: ComputerUsePermissionManaging {
    private let stateLock = NSLock()
    private let requestRelease = DispatchSemaphore(value: 0)
    private var shouldBlockNextRequest = false
    private var requestHandler: (() -> Void)?

    func setAccessibilityRequestHandler(_ handler: @escaping () -> Void) {
        stateLock.lock()
        requestHandler = handler
        stateLock.unlock()
    }

    func blockNextAccessibilityRequest() {
        stateLock.lock()
        shouldBlockNextRequest = true
        stateLock.unlock()
    }

    func releaseRequest() {
        requestRelease.signal()
    }

    func snapshot() -> ComputerUsePermissionSnapshot {
        ComputerUsePermissionSnapshot(
            accessibility: .granted,
            screenRecording: .granted
        )
    }

    func requestAccessibility() -> Bool {
        stateLock.lock()
        let shouldBlock = shouldBlockNextRequest
        shouldBlockNextRequest = false
        let handler = requestHandler
        stateLock.unlock()

        if shouldBlock {
            handler?()
            requestRelease.wait()
        }
        return true
    }

    func requestScreenRecording() -> Bool {
        true
    }
}
