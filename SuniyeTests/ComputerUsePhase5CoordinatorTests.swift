import Foundation
import XCTest
@testable import Suniye

@MainActor
final class ComputerUsePhase5CoordinatorTests: XCTestCase {
    func testAgentApprovalIsPresentedByCoordinatorAndCompletesAfterUserApproval() async {
        let observation = makePhase3Observation(generation: 21)
        let model = Phase3ScriptedModelClient(
            decisions: [
                .action(.scroll(horizontal: 0, vertical: -100)),
                .completed(message: "Finished."),
            ]
        )
        let actionService = Phase3StubActionService()
        let coordinator = makeCoordinator(
            model: model,
            observation: observation,
            actionService: actionService
        )
        coordinator.includeScreenshot = false
        coordinator.agentInstruction = "Scroll down and finish the task."

        coordinator.start()
        await waitForPhase(coordinator, .ready)
        coordinator.startAgent()
        await waitForPhase(coordinator, .requestingApproval)

        guard let request = coordinator.pendingApproval else {
            return XCTFail("Expected an approval request")
        }
        XCTAssertEqual(request.allowedScopes, [.once])
        XCTAssertEqual(request.observationGeneration, observation.generation)

        coordinator.approvePendingAction()
        await waitForPhase(coordinator, .agentCompleted)

        XCTAssertEqual(coordinator.agentResult?.phase, .completed)
        XCTAssertEqual(coordinator.agentResult?.message, "Finished.")
        XCTAssertEqual(actionService.actions, [.scroll(horizontal: 0, vertical: -100)])
        XCTAssertNil(coordinator.pendingApproval)
    }

    func testCancelResolvesPendingAgentApproval() async {
        let model = Phase3ScriptedModelClient(
            decisions: [.action(.click(point: ComputerUsePoint(x: 20, y: 20)))]
        )
        let coordinator = makeCoordinator(
            model: model,
            observation: makePhase3Observation(generation: 22),
            actionService: Phase3StubActionService()
        )
        coordinator.includeScreenshot = false
        coordinator.agentInstruction = "Click the target and stop."

        coordinator.start()
        await waitForPhase(coordinator, .ready)
        coordinator.startAgent()
        await waitForPhase(coordinator, .requestingApproval)

        coordinator.cancel()
        await waitForPhase(coordinator, .ready)

        XCTAssertNil(coordinator.pendingApproval)
        XCTAssertNil(coordinator.agentResult)
    }

    func testSessionApprovalIsReusedByTheAgentWithoutAnotherPrompt() async {
        let observation = makePhase3Observation(generation: 23)
        let store = ComputerUseApprovalStore(
            userDefaults: isolatedDefaults(),
            storageKey: "phase5.session.approvals"
        )
        let policy = ComputerUsePolicyService(
            configuration: ComputerUsePolicyConfiguration(
                persistentApprovalRisks: [.scroll]
            )
        )
        let action = ComputerUseAction.scroll(horizontal: 0, vertical: -100)
        let firstModel = Phase3ScriptedModelClient(
            decisions: [.action(action), .completed(message: "First run.")]
        )
        let actionService = Phase3StubActionService()
        let coordinator = makeCoordinator(
            model: firstModel,
            observation: observation,
            actionService: actionService,
            store: store,
            policy: policy
        )
        coordinator.includeScreenshot = false
        coordinator.agentInstruction = "Scroll down and finish the task."

        coordinator.start()
        await waitForPhase(coordinator, .ready)
        coordinator.startAgent()
        await waitForPhase(coordinator, .requestingApproval)
        XCTAssertEqual(coordinator.pendingApproval?.allowedScopes, [.once, .session, .always])

        coordinator.approvePendingAction(scope: .session)
        await waitForPhase(coordinator, .agentCompleted)

        let secondModel = Phase3ScriptedModelClient(
            decisions: [.action(action), .completed(message: "Second run.")]
        )
        coordinator.configureModel(secondModel)
        coordinator.startAgent()
        await waitForPhase(coordinator, .agentCompleted)

        XCTAssertEqual(coordinator.agentResult?.message, "Second run.")
        XCTAssertEqual(actionService.actions, [action, action])
        XCTAssertNil(coordinator.pendingApproval)
    }

    func testRemoteModelConfigurationAndScreenshotConsentAreSessionScoped() async {
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
        XCTAssertFalse(coordinator.canRunAgent)

        coordinator.configureRemoteModel(configuration)
        XCTAssertTrue(coordinator.isModelConfigured)
        coordinator.includeScreenshot = false
        XCTAssertTrue(coordinator.canRunAgent)

        coordinator.setRemoteScreenshotUploadAllowed(true)
        XCTAssertTrue(coordinator.allowRemoteScreenshotUpload)
        coordinator.setRemoteScreenshotUploadAllowed(false)
        XCTAssertFalse(coordinator.allowRemoteScreenshotUpload)

        coordinator.configureRemoteModel(nil)
        XCTAssertFalse(coordinator.isModelConfigured)
        coordinator.setRemoteScreenshotUploadAllowed(true)
        XCTAssertTrue(coordinator.allowRemoteScreenshotUpload)
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
        blockedCoordinator.includeScreenshot = false
        blockedCoordinator.agentInstruction = "Try the task."
        blockedCoordinator.start()
        await waitForPhase(blockedCoordinator, .ready)
        blockedCoordinator.startAgent()
        await waitForPhase(blockedCoordinator, .agentCompleted)
        XCTAssertEqual(blockedCoordinator.agentResult?.phase, .blocked)
        XCTAssertNil(blockedCoordinator.errorMessage)

        let failedCoordinator = makeCoordinator(
            model: Phase3ScriptedModelClient(
                decisions: [.retryableFailure(reason: "Not enough state.")]
            ),
            observation: makePhase3Observation(generation: 26),
            actionService: Phase3StubActionService(),
            agentLimits: ComputerUseAgentLimits(maxFailures: 1, settleDelay: 0)
        )
        failedCoordinator.includeScreenshot = false
        failedCoordinator.agentInstruction = "Try the task."
        failedCoordinator.start()
        await waitForPhase(failedCoordinator, .ready)
        failedCoordinator.startAgent()
        await waitForPhase(failedCoordinator, .agentCompleted)
        XCTAssertEqual(failedCoordinator.agentResult?.phase, .failed)
        XCTAssertEqual(failedCoordinator.errorMessage, failedCoordinator.agentResult?.message)
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
        coordinator.setRemoteScreenshotUploadAllowed(true)
        coordinator.phase = .ready

        coordinator.configureModel(nil)
        coordinator.agentInstruction = "  "
        coordinator.startAgent()
        XCTAssertEqual(coordinator.phase, .actionFailed)
        XCTAssertEqual(coordinator.errorMessage, "Enter a task for Computer Use.")

        coordinator.phase = .ready
        coordinator.agentInstruction = "Try the task."
        coordinator.startAgent()
        XCTAssertEqual(coordinator.phase, .ready)

        coordinator.configureModel(
            Phase3ScriptedModelClient(decisions: [.completed(message: "unused")])
        )
        coordinator.includeScreenshot = true
        XCTAssertFalse(coordinator.canRunAgent)

        coordinator.phase = .runningAgent
        XCTAssertEqual(coordinator.phaseTitle, "Computer Use is working")
        coordinator.phase = .agentCompleted
        XCTAssertEqual(coordinator.phaseTitle, "Computer Use finished")
    }

    func testCoordinatorHandlesPolicyAndApprovalGuards() async {
        let observation = makePhase3Observation(generation: 28)
        let deniedPolicy = ComputerUsePolicyService(
            configuration: ComputerUsePolicyConfiguration(
                deniedBundleIdentifiers: [observation.target.application.bundleIdentifier]
            )
        )
        let deniedCoordinator = makeCoordinator(
            model: Phase3ScriptedModelClient(decisions: [.completed(message: "unused")]),
            observation: observation,
            actionService: Phase3StubActionService(),
            policy: deniedPolicy
        )

        deniedCoordinator.includeScreenshot = false
        deniedCoordinator.start()
        await waitForPhase(deniedCoordinator, .ready)
        deniedCoordinator.observeSelectedApplication()
        await waitForPhase(deniedCoordinator, .observed)
        deniedCoordinator.requestAction(.scroll(horizontal: 0, vertical: -10))
        XCTAssertEqual(deniedCoordinator.phase, .actionFailed)
        XCTAssertEqual(
            deniedCoordinator.errorMessage,
            "Computer Use is blocked from using Target App by policy."
        )

        let coordinator = makeCoordinator(
            model: Phase3ScriptedModelClient(decisions: [.completed(message: "unused")]),
            observation: observation,
            actionService: Phase3StubActionService()
        )
        coordinator.includeScreenshot = false
        coordinator.start()
        await waitForPhase(coordinator, .ready)
        coordinator.approvePendingAction()
        coordinator.requestAction(.scroll(horizontal: 0, vertical: -10))
        coordinator.observeSelectedApplication()
        await waitForPhase(coordinator, .observed)
        coordinator.requestAction(.scroll(horizontal: 0, vertical: -10))
        coordinator.observation = nil
        coordinator.approvePendingAction()
        XCTAssertEqual(coordinator.phase, .requestingApproval)

        coordinator.observation = observation
        coordinator.approvePendingAction(scope: .session)
        XCTAssertEqual(coordinator.phase, .actionFailed)
        XCTAssertEqual(
            coordinator.errorMessage,
            ComputerUsePolicyError.approvalScopeNotAllowed.localizedDescription
        )

        let request = ComputerUseApprovalRequest(
            id: UUID(),
            action: .scroll(horizontal: 0, vertical: -10),
            target: observation.target,
            risk: .scroll,
            reason: "Test approval",
            observationGeneration: observation.generation
        )
        coordinator.observation = nil
        coordinator.phase = .requestingApproval
        coordinator.pendingApproval = request
        coordinator.approvePendingAction()
        XCTAssertEqual(coordinator.phase, .requestingApproval)

        let cancellation = ComputerUseCancellationToken()
        cancellation.cancel()
        let decision = await coordinator.requestApproval(request, cancellation: cancellation)
        XCTAssertEqual(decision, .stopSession)
    }

    func testCoordinatorAgentApprovalDenialAndPersistentApproval() async {
        let observation = makePhase3Observation(generation: 29)
        let deniedModel = Phase3ScriptedModelClient(
            decisions: [.action(.scroll(horizontal: 0, vertical: -10))]
        )
        let deniedCoordinator = makeCoordinator(
            model: deniedModel,
            observation: observation,
            actionService: Phase3StubActionService()
        )
        deniedCoordinator.includeScreenshot = false
        deniedCoordinator.agentInstruction = "Scroll and stop."
        deniedCoordinator.start()
        await waitForPhase(deniedCoordinator, .ready)
        deniedCoordinator.startAgent()
        await waitForPhase(deniedCoordinator, .requestingApproval)
        deniedCoordinator.approvePendingAction(scope: .session)
        XCTAssertEqual(
            deniedCoordinator.errorMessage,
            ComputerUsePolicyError.approvalScopeNotAllowed.localizedDescription
        )
        deniedCoordinator.denyPendingAction()
        await waitForPhase(deniedCoordinator, .agentCompleted)
        XCTAssertEqual(deniedCoordinator.agentResult?.phase, .blocked)

        let policy = ComputerUsePolicyService(
            configuration: ComputerUsePolicyConfiguration(persistentApprovalRisks: [.scroll])
        )
        let persistentCoordinator = makeCoordinator(
            model: Phase3ScriptedModelClient(
                decisions: [
                    .action(.scroll(horizontal: 0, vertical: -10)),
                    .completed(message: "Finished.")
                ]
            ),
            observation: observation,
            actionService: Phase3StubActionService(),
            policy: policy
        )
        persistentCoordinator.includeScreenshot = false
        persistentCoordinator.agentInstruction = "Scroll and finish."
        persistentCoordinator.start()
        await waitForPhase(persistentCoordinator, .ready)
        persistentCoordinator.startAgent()
        await waitForPhase(persistentCoordinator, .requestingApproval)
        persistentCoordinator.approvePendingAction(scope: .always)
        await waitForPhase(persistentCoordinator, .agentCompleted)
        XCTAssertEqual(persistentCoordinator.agentResult?.phase, .completed)
    }

    func testCoordinatorReturnsToObservationAfterCanceledAction() async {
        let observation = makePhase3Observation(generation: 30)
        let coordinator = makeCoordinator(
            model: Phase3ScriptedModelClient(decisions: [.completed(message: "unused")]),
            observation: observation,
            actionService: Phase3StubActionService(errors: [ComputerUseActionError.cancelled])
        )
        coordinator.includeScreenshot = false
        coordinator.start()
        await waitForPhase(coordinator, .ready)
        coordinator.observeSelectedApplication()
        await waitForPhase(coordinator, .observed)
        coordinator.requestAction(.scroll(horizontal: 0, vertical: -10))
        coordinator.approvePendingAction()
        await waitForPhase(coordinator, .observed)

        XCTAssertNil(coordinator.lastActionResult)
        XCTAssertNil(coordinator.errorMessage)
    }

    func testCoordinatorIgnoresCanceledActionResult() async {
        let started = expectation(description: "action started")
        let release = DispatchSemaphore(value: 0)
        let actionService = Phase3StubActionService()
        actionService.onExecute = { _ in
            started.fulfill()
            release.wait()
        }
        let coordinator = makeCoordinator(
            model: Phase3ScriptedModelClient(decisions: [.completed(message: "unused")]),
            observation: makePhase3Observation(generation: 31),
            actionService: actionService
        )
        coordinator.includeScreenshot = false
        coordinator.start()
        await waitForPhase(coordinator, .ready)
        coordinator.observeSelectedApplication()
        await waitForPhase(coordinator, .observed)
        coordinator.requestAction(.scroll(horizontal: 0, vertical: -10))
        coordinator.approvePendingAction()

        await fulfillment(of: [started], timeout: 1)
        coordinator.cancel()
        release.signal()
        await waitForPhase(coordinator, .ready)
        try? await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertNil(coordinator.lastActionResult)
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
        coordinator.includeScreenshot = false
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
        staleCoordinator.includeScreenshot = false
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
        actionService: ComputerUseActionServicing,
        permissionManager: ComputerUsePermissionManaging = Phase5PermissionManager(),
        store: ComputerUseApprovalStoring? = nil,
        policy: ComputerUsePolicyChecking? = nil,
        agentLimits: ComputerUseAgentLimits = ComputerUseAgentLimits(settleDelay: 0)
    ) -> ComputerUseCoordinator {
        ComputerUseCoordinator(
            applicationCatalog: Phase5ApplicationCatalog(application: observation.target.application),
            permissionManager: permissionManager,
            observationService: Phase3StubObservationService(result: observation),
            actionService: actionService,
            approvalStore: store,
            policy: policy,
            modelClient: model,
            interventionMonitor: Phase3StubInterventionMonitor(),
            agentLimits: agentLimits
        )
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "Suniye-Phase5-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
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
            screenRecording: .notGranted
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
            screenRecording: .notGranted
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
