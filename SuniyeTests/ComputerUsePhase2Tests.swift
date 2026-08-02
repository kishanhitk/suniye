import CoreGraphics
import Foundation
import XCTest
@testable import Suniye

@MainActor
final class ComputerUsePhase2CoordinatorTests: XCTestCase {
    func testPhaseTitlesCoverTheActionStates() {
        let coordinator = makePhase2Coordinator(
            observation: makePhase2Observation(),
            actionService: Phase2StubActionService()
        )
        let expectedTitles: [(ComputerUseCoordinatorPhase, String)] = [
            (.requestingApproval, "Approval required"),
            (.acting, "Performing approved action"),
            (.actionCompleted, "Action completed"),
            (.actionFailed, "Action failed"),
        ]

        for (phase, title) in expectedTitles {
            coordinator.phase = phase
            XCTAssertEqual(coordinator.phaseTitle, title)
        }
    }

    func testCoordinatorActivatesTheSelectedWindowBeforeControl() async {
        let observation = makePhase2Observation()
        let activator = Phase2StubWindowActivator()
        let coordinator = makePhase2Coordinator(
            observation: observation,
            actionService: Phase2StubActionService(),
            windowActivator: activator
        )

        coordinator.start()
        await waitForPhase(coordinator, .ready)
        coordinator.activateSelectedWindow()

        for _ in 0 ..< 100 where activator.targets.isEmpty {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(activator.targets.first?.window, coordinator.selectedWindow)
        XCTAssertEqual(coordinator.phase, .ready)
    }

    func testApprovalFlowExecutesOnceAndRequiresFreshObservationForNextAction() async {
        let observation = makePhase2Observation()
        let actionService = Phase2StubActionService()
        let coordinator = makePhase2Coordinator(
            observation: observation,
            actionService: actionService
        )

        coordinator.start()
        await waitForPhase(coordinator, .ready)
        coordinator.observeSelectedApplication()
        await waitForPhase(coordinator, .observed)

        let action = ComputerUseAction.keyPress(
            key: .named(.returnKey),
            modifiers: ComputerUseKeyModifiers()
        )
        XCTAssertTrue(coordinator.canRequestAction)
        coordinator.requestAction(action)
        XCTAssertEqual(coordinator.phase, .requestingApproval)
        XCTAssertEqual(coordinator.pendingApproval?.action, action)
        XCTAssertFalse(coordinator.canRequestAction)

        coordinator.approvePendingAction()
        await waitForPhase(coordinator, .actionCompleted)

        XCTAssertEqual(actionService.executedActions, [action])
        XCTAssertEqual(coordinator.lastActionResult?.action, action)
        XCTAssertNil(coordinator.pendingApproval)
        XCTAssertFalse(coordinator.canRequestAction)
    }

    func testDenyAndStopApprovalDoNotExecuteAndStopClearsObservation() async {
        let observation = makePhase2Observation()
        let actionService = Phase2StubActionService()
        let coordinator = makePhase2Coordinator(
            observation: observation,
            actionService: actionService
        )

        coordinator.start()
        await waitForPhase(coordinator, .ready)
        coordinator.observeSelectedApplication()
        await waitForPhase(coordinator, .observed)

        coordinator.requestAction(.scroll(horizontal: 0, vertical: -100))
        coordinator.denyPendingAction()
        XCTAssertEqual(coordinator.phase, .observed)
        XCTAssertNil(coordinator.pendingApproval)
        XCTAssertTrue(actionService.executedActions.isEmpty)

        coordinator.requestAction(.typeText("hello"))
        coordinator.stopPendingAction()
        XCTAssertEqual(coordinator.phase, .ready)
        XCTAssertNil(coordinator.pendingApproval)
        XCTAssertNil(coordinator.observation)
        XCTAssertTrue(actionService.executedActions.isEmpty)
    }

    func testInvalidActionAndActionFailureAreSurfacedWithoutPublishingAResult() async {
        let observation = makePhase2Observation()
        let actionService = Phase2StubActionService()
        let coordinator = makePhase2Coordinator(
            observation: observation,
            actionService: actionService
        )

        coordinator.start()
        await waitForPhase(coordinator, .ready)
        coordinator.observeSelectedApplication()
        await waitForPhase(coordinator, .observed)

        coordinator.requestAction(.click(point: ComputerUsePoint(x: 900, y: 900)))
        XCTAssertEqual(coordinator.phase, .actionFailed)
        XCTAssertEqual(
            coordinator.errorMessage,
            ComputerUseActionError.invalidAction("click must be inside the target window").errorDescription
        )
        XCTAssertNil(coordinator.pendingApproval)

        coordinator.observeSelectedApplication()
        await waitForPhase(coordinator, .observed)
        actionService.error = ComputerUseActionError.targetNotFrontmost
        coordinator.requestAction(.keyPress(key: .named(.escape), modifiers: ComputerUseKeyModifiers()))
        coordinator.approvePendingAction()
        await waitForPhase(coordinator, .actionFailed)

        XCTAssertEqual(coordinator.errorMessage, ComputerUseActionError.targetNotFrontmost.errorDescription)
        XCTAssertNil(coordinator.lastActionResult)
    }

    func testCancelStopsAnInFlightActionWithoutPublishingState() async {
        let observation = makePhase2Observation()
        let started = expectation(description: "action started")
        let actionService = Phase2BlockingActionService {
            started.fulfill()
        }
        let coordinator = makePhase2Coordinator(
            observation: observation,
            actionService: actionService
        )

        coordinator.start()
        await waitForPhase(coordinator, .ready)
        coordinator.observeSelectedApplication()
        await waitForPhase(coordinator, .observed)
        coordinator.requestAction(.keyPress(key: .named(.returnKey), modifiers: ComputerUseKeyModifiers()))
        coordinator.approvePendingAction()
        await fulfillment(of: [started], timeout: 1)

        coordinator.cancel()
        await waitForPhase(coordinator, .ready)
        try? await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertNil(coordinator.lastActionResult)
        XCTAssertNil(coordinator.pendingApproval)
        XCTAssertNil(coordinator.errorMessage)
        XCTAssertEqual(actionService.executeCount, 1)
    }

    func testWindowSelectionPublishesWindowIdentityAndResetsObservation() async {
        let observation = makePhase2Observation()
        let secondWindow = ComputerUseWindow(
            id: 8,
            title: "Second Window",
            ownerProcessIdentifier: observation.target.application.processIdentifier,
            bounds: ComputerUseRect(x: 20, y: 20, width: 320, height: 240),
            layer: 0,
            isOnScreen: true,
            isKeyWindow: false
        )
        let coordinator = makePhase2Coordinator(
            observation: observation,
            actionService: Phase2StubActionService(),
            windows: [observation.target.window, secondWindow]
        )

        coordinator.start()
        await waitForPhase(coordinator, .ready)
        XCTAssertEqual(coordinator.windowIDs, [observation.target.window.id, secondWindow.id])
        XCTAssertEqual(coordinator.selectedWindow?.id, observation.target.window.id)

        coordinator.observation = observation
        coordinator.selectWindow(secondWindow.id)
        XCTAssertEqual(coordinator.selectedWindowID, secondWindow.id)
        XCTAssertEqual(coordinator.selectedWindow?.title, secondWindow.title)
        XCTAssertNil(coordinator.observation)

        coordinator.selectWindow(999)
        XCTAssertEqual(coordinator.selectedWindowID, secondWindow.id)
        coordinator.selectedWindowID = nil
        XCTAssertNil(coordinator.selectedWindow)
    }

    func testPlatformRunnerDelegatesWindowAndApprovalBoundaries() async throws {
        let observation = makePhase2Observation()
        let application = observation.target.application
        let discovery = Phase2StubWindowDiscovery(windows: [observation.target.window])
        let activator = Phase2StubWindowActivator()
        let permissionManager = Phase2StubPermissionManager(granted: true)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "Suniye-Phase2-\(UUID().uuidString)"))
        let store = ComputerUseApprovalStore(userDefaults: defaults, storageKey: "approvals")
        defer { store.revokeAll() }
        store.save(
            scope: .always,
            applicationBundleIdentifier: application.bundleIdentifier,
            risk: .click,
            sessionID: UUID(),
            expiresAt: nil
        )
        let runner = ComputerUsePlatformRunner(
            applicationCatalog: Phase2StubApplicationCatalog(applications: [application]),
            windowDiscovery: discovery,
            windowActivator: activator,
            permissionManager: permissionManager,
            approvalStore: store,
            observationService: Phase2StubObservationService(result: observation),
            actionService: Phase2StubActionService()
        )

        let listedApplications = await runner.listApplications()
        let listedPermissions = await runner.permissionSnapshot()
        let listedWindows = await runner.listWindows(applicationID: application.id)
        let missingWindows = await runner.listWindows(applicationID: "missing")
        let listedApprovals = await runner.listAlwaysApprovals()
        XCTAssertEqual(listedApplications, [application])
        XCTAssertEqual(listedPermissions, permissionManager.snapshot())
        XCTAssertEqual(listedWindows, [observation.target.window])
        XCTAssertEqual(missingWindows, [])
        XCTAssertEqual(listedApprovals.count, 1)

        let activated = await runner.activateWindow(
            applicationID: application.id,
            windowID: observation.target.window.id
        )
        let missingWindowActivation = await runner.activateWindow(
            applicationID: application.id,
            windowID: 999
        )
        let missingApplicationActivation = await runner.activateWindow(
            applicationID: "missing",
            windowID: observation.target.window.id
        )
        XCTAssertTrue(activated)
        XCTAssertFalse(missingWindowActivation)
        XCTAssertFalse(missingApplicationActivation)
        XCTAssertEqual(activator.targets.count, 1)

        if let approval = await runner.listAlwaysApprovals().first {
            await runner.revokeAlwaysApproval(approval)
        }
        let remainingApprovals = await runner.listAlwaysApprovals()
        XCTAssertTrue(remainingApprovals.isEmpty)
    }

    private func makePhase2Coordinator(
        observation: ComputerUseObservation,
        actionService: ComputerUseActionServicing,
        windowActivator: ComputerUseWindowActivating = Phase2StubWindowActivator(),
        windows: [ComputerUseWindow]? = nil
    ) -> ComputerUseCoordinator {
        let application = observation.target.application
        return ComputerUseCoordinator(
            applicationCatalog: Phase2StubApplicationCatalog(applications: [application]),
            windowDiscovery: Phase2StubWindowDiscovery(
                windows: windows ?? [observation.target.window]
            ),
            windowActivator: windowActivator,
            permissionManager: Phase2StubPermissionManager(granted: true),
            observationService: Phase2StubObservationService(result: observation),
            actionService: actionService
        )
    }
}
