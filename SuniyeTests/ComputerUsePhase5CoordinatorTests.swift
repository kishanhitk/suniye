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
        actionService: ComputerUseActionServicing,
        permissionManager: ComputerUsePermissionManaging = Phase5PermissionManager(),
        policy: ComputerUsePolicyChecking? = nil
    ) -> ComputerUseCoordinator {
        ComputerUseCoordinator(
            applicationCatalog: Phase5ApplicationCatalog(application: observation.target.application),
            permissionManager: permissionManager,
            observationService: Phase3StubObservationService(result: observation),
            actionService: actionService,
            policy: policy,
            modelClient: model
        )
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
