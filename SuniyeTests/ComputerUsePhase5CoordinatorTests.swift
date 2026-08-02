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

    private func makeCoordinator(
        model: ComputerUseModelClient,
        observation: ComputerUseObservation,
        actionService: ComputerUseActionServicing,
        store: ComputerUseApprovalStoring? = nil,
        policy: ComputerUsePolicyChecking? = nil
    ) -> ComputerUseCoordinator {
        ComputerUseCoordinator(
            applicationCatalog: Phase5ApplicationCatalog(application: observation.target.application),
            permissionManager: Phase5PermissionManager(),
            observationService: Phase3StubObservationService(result: observation),
            actionService: actionService,
            approvalStore: store,
            policy: policy,
            modelClient: model,
            interventionMonitor: Phase3StubInterventionMonitor(),
            agentLimits: ComputerUseAgentLimits(settleDelay: 0)
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
