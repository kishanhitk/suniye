import Foundation
import XCTest
@testable import Suniye

@MainActor
final class ComputerUsePhase1Tests: XCTestCase {
    func testStartLoadsApplicationsPermissionsAndSelectsFirstApplication() async {
        let first = makeApplication(id: "com.example.first", name: "First App", active: true)
        let second = makeApplication(id: "com.example.second", name: "Second App")
        let permissions = Phase1StubPermissionManager(
            snapshot: ComputerUsePermissionSnapshot(accessibility: .granted, screenRecording: .granted)
        )
        let coordinator = makeCoordinator(
            applications: [first, second],
            permissionManager: permissions
        )

        coordinator.start()
        await waitUntil { coordinator.phase == .ready }

        XCTAssertEqual(coordinator.applications, [first, second])
        XCTAssertEqual(coordinator.selectedApplicationID, first.id)
        XCTAssertEqual(coordinator.permissionSnapshot, permissions.currentSnapshot)
        XCTAssertTrue(coordinator.canObserve)
    }

    func testDerivedStateAndPhaseTitlesCoverAllCoordinatorStates() async {
        let coordinator = makeCoordinator(
            permissionManager: Phase1StubPermissionManager(
                snapshot: ComputerUsePermissionSnapshot(accessibility: .granted, screenRecording: .granted)
            )
        )

        XCTAssertEqual(coordinator.applicationIDs, [])
        XCTAssertEqual(coordinator.selectedApplication, nil)

        coordinator.start()
        await waitUntil { coordinator.phase == .ready }

        XCTAssertEqual(coordinator.applicationIDs, ["com.example.target"])
        XCTAssertEqual(coordinator.selectedApplication?.id, "com.example.target")

        let expectedTitles: [(ComputerUseCoordinatorPhase, String)] = [
            (.idle, "Ready to inspect"),
            (.loadingApplications, "Finding running apps"),
            (.requestingPermission, "Waiting for permission"),
            (.ready, "Ready to inspect"),
            (.observing, "Reading app state"),
            (.observed, "Observation captured"),
            (.failed, "Computer Use failed"),
        ]

        for (phase, title) in expectedTitles {
            coordinator.phase = phase
            XCTAssertEqual(coordinator.phaseTitle, title)
        }
    }

    func testMissingPermissionsDisableObservationUntilRequestsSucceed() async {
        let permissions = Phase1StubPermissionManager(
            snapshot: ComputerUsePermissionSnapshot(accessibility: .notGranted, screenRecording: .notGranted)
        )
        let coordinator = makeCoordinator(permissionManager: permissions)

        coordinator.start()
        await waitUntil { coordinator.phase == .ready }

        XCTAssertFalse(coordinator.canObserve)

        coordinator.requestAccessibility()
        await waitUntil { coordinator.permissionSnapshot.accessibility == .granted }
        XCTAssertEqual(permissions.accessibilityRequestCount, 1)
        XCTAssertFalse(coordinator.canObserve)

        coordinator.requestScreenRecording()
        await waitUntil { coordinator.permissionSnapshot.screenRecording == .granted }
        XCTAssertEqual(permissions.screenRecordingRequestCount, 1)
        XCTAssertTrue(coordinator.canObserve)
    }

    func testRefreshPermissionsUpdatesTheCoordinatorSnapshot() async {
        let permissions = Phase1StubPermissionManager(
            snapshot: ComputerUsePermissionSnapshot(accessibility: .notGranted, screenRecording: .notGranted)
        )
        let coordinator = makeCoordinator(permissionManager: permissions)

        coordinator.start()
        await waitUntil { coordinator.phase == .ready }
        permissions.setSnapshot(
            ComputerUsePermissionSnapshot(accessibility: .granted, screenRecording: .notGranted)
        )
        coordinator.refreshPermissions()
        await waitUntil { coordinator.permissionSnapshot.accessibility == .granted }

        XCTAssertFalse(coordinator.permissionSnapshot.canObserve)
    }

    func testObservationPublishesReadOnlyResult() async {
        let permissions = Phase1StubPermissionManager(
            snapshot: ComputerUsePermissionSnapshot(accessibility: .granted, screenRecording: .granted)
        )
        let service = Phase1StubObservationService(result: makeObservation())
        let coordinator = makeCoordinator(
            permissionManager: permissions,
            observationService: service
        )

        coordinator.start()
        await waitUntil { coordinator.phase == .ready }
        coordinator.observeSelectedApplication()
        await waitUntil { coordinator.phase == .observed }

        XCTAssertEqual(service.observeCount, 1)
        XCTAssertEqual(coordinator.observation, service.result)
        XCTAssertNil(coordinator.errorMessage)
    }

    func testObservationDoesNotStartWithoutRequiredPermission() async {
        let permissions = Phase1StubPermissionManager(
            snapshot: ComputerUsePermissionSnapshot(accessibility: .granted, screenRecording: .notGranted)
        )
        let service = Phase1StubObservationService(result: makeObservation())
        let coordinator = makeCoordinator(
            permissionManager: permissions,
            observationService: service
        )

        coordinator.start()
        await waitUntil { coordinator.phase == .ready }
        coordinator.observeSelectedApplication()
        try? await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertEqual(service.observeCount, 0)
        XCTAssertNil(coordinator.observation)
        XCTAssertEqual(coordinator.phase, .ready)
    }

    func testObservationFailureSurfacesActionableError() async {
        let permissions = Phase1StubPermissionManager(
            snapshot: ComputerUsePermissionSnapshot(accessibility: .granted, screenRecording: .granted)
        )
        let service = Phase1StubObservationService(
            result: makeObservation(),
            error: ComputerUseObservationError.screenshotUnavailable
        )
        let coordinator = makeCoordinator(
            permissionManager: permissions,
            observationService: service
        )

        coordinator.start()
        await waitUntil { coordinator.phase == .ready }
        coordinator.observeSelectedApplication()
        await waitUntil { coordinator.phase == .failed }

        XCTAssertEqual(coordinator.errorMessage, ComputerUseObservationError.screenshotUnavailable.errorDescription)
        XCTAssertNil(coordinator.observation)
    }

    func testCanceledObservationErrorReturnsToReadyWithoutError() async {
        let permissions = Phase1StubPermissionManager(
            snapshot: ComputerUsePermissionSnapshot(accessibility: .granted, screenRecording: .granted)
        )
        let service = Phase1StubObservationService(
            result: makeObservation(),
            error: ComputerUseObservationError.cancelled
        )
        let coordinator = makeCoordinator(
            permissionManager: permissions,
            observationService: service
        )

        coordinator.start()
        await waitUntil { coordinator.phase == .ready }
        coordinator.observeSelectedApplication()
        await waitUntil { coordinator.phase == .ready }

        XCTAssertNil(coordinator.errorMessage)
        XCTAssertNil(coordinator.observation)
    }

    func testCancelStopsInFlightObservationWithoutPublishingState() async {
        let permissions = Phase1StubPermissionManager(
            snapshot: ComputerUsePermissionSnapshot(accessibility: .granted, screenRecording: .granted)
        )
        let started = expectation(description: "observation started")
        let service = Phase1BlockingObservationService {
            started.fulfill()
        }
        let coordinator = makeCoordinator(
            permissionManager: permissions,
            observationService: service
        )

        coordinator.start()
        await waitUntil { coordinator.phase == .ready }
        coordinator.observeSelectedApplication()
        await fulfillment(of: [started], timeout: 1)

        coordinator.cancel()
        await waitUntil { coordinator.phase == .ready && coordinator.observation == nil }

        XCTAssertEqual(service.observeCount, 1)
        XCTAssertNil(coordinator.errorMessage)
    }

    func testRefreshClearsPreviousObservation() async {
        let permissions = Phase1StubPermissionManager(
            snapshot: ComputerUsePermissionSnapshot(accessibility: .granted, screenRecording: .granted)
        )
        let coordinator = makeCoordinator(permissionManager: permissions)

        coordinator.start()
        await waitUntil { coordinator.phase == .ready }
        coordinator.observeSelectedApplication()
        await waitUntil { coordinator.phase == .observed }

        coordinator.refresh()

        XCTAssertNil(coordinator.observation)
        await waitUntil { coordinator.phase == .ready }
        XCTAssertNil(coordinator.observation)
    }

    func testPermissionRequestsAreIgnoredWhileObservationIsBusy() async {
        let permissions = Phase1StubPermissionManager(
            snapshot: ComputerUsePermissionSnapshot(accessibility: .granted, screenRecording: .granted)
        )
        let started = expectation(description: "observation started")
        let service = Phase1BlockingObservationService {
            started.fulfill()
        }
        let coordinator = makeCoordinator(
            permissionManager: permissions,
            observationService: service
        )

        coordinator.start()
        await waitUntil { coordinator.phase == .ready }
        coordinator.observeSelectedApplication()
        await fulfillment(of: [started], timeout: 1)

        coordinator.requestAccessibility()
        coordinator.requestScreenRecording()

        XCTAssertEqual(permissions.accessibilityRequestCount, 0)
        XCTAssertEqual(permissions.screenRecordingRequestCount, 0)
        coordinator.cancel()
    }

    func testSelectingAnotherApplicationIsIgnoredWhileObservationIsBusy() async {
        let first = makeApplication(id: "com.example.first", name: "First App", active: true)
        let second = makeApplication(id: "com.example.second", name: "Second App")
        let permissions = Phase1StubPermissionManager(
            snapshot: ComputerUsePermissionSnapshot(accessibility: .granted, screenRecording: .granted)
        )
        let started = expectation(description: "observation started")
        let coordinator = makeCoordinator(
            applications: [first, second],
            permissionManager: permissions,
            observationService: Phase1BlockingObservationService {
                started.fulfill()
            }
        )

        coordinator.start()
        await waitUntil { coordinator.phase == .ready }
        coordinator.observeSelectedApplication()
        await fulfillment(of: [started], timeout: 1)

        coordinator.selectApplication(second.id)

        XCTAssertEqual(coordinator.selectedApplicationID, first.id)
        XCTAssertEqual(coordinator.phase, .observing)
        coordinator.cancel()
    }

    func testSelectingAnotherApplicationClearsPreviousObservation() async {
        let first = makeApplication(id: "com.example.first", name: "First App", active: true)
        let second = makeApplication(id: "com.example.second", name: "Second App")
        let permissions = Phase1StubPermissionManager(
            snapshot: ComputerUsePermissionSnapshot(accessibility: .granted, screenRecording: .granted)
        )
        let coordinator = makeCoordinator(
            applications: [first, second],
            permissionManager: permissions,
            observationService: Phase1StubObservationService(result: makeObservation(application: first))
        )

        coordinator.start()
        await waitUntil { coordinator.phase == .ready }
        coordinator.observeSelectedApplication()
        await waitUntil { coordinator.phase == .observed }

        coordinator.selectApplication(second.id)

        XCTAssertEqual(coordinator.selectedApplicationID, second.id)
        XCTAssertNil(coordinator.observation)
        XCTAssertEqual(coordinator.phase, .ready)
    }

    func testInvalidAndRepeatedApplicationSelectionsAreIgnored() async {
        let first = makeApplication(id: "com.example.first", name: "First App", active: true)
        let second = makeApplication(id: "com.example.second", name: "Second App")
        let coordinator = makeCoordinator(
            applications: [first, second],
            permissionManager: Phase1StubPermissionManager(
                snapshot: ComputerUsePermissionSnapshot(accessibility: .granted, screenRecording: .granted)
            )
        )

        coordinator.start()
        await waitUntil { coordinator.phase == .ready }
        coordinator.selectApplication("com.example.missing")
        XCTAssertEqual(coordinator.selectedApplicationID, first.id)

        coordinator.selectApplication(first.id)
        XCTAssertEqual(coordinator.selectedApplicationID, first.id)
    }

    private func makeCoordinator(
        applications: [ComputerUseApplication]? = nil,
        permissionManager: Phase1StubPermissionManager,
        observationService: ComputerUseObservationServicing? = nil
    ) -> ComputerUseCoordinator {
        let resolvedApplications = applications ?? [makeApplication(id: "com.example.target", name: "Target App", active: true)]
        let catalog = Phase1StubApplicationCatalog(applications: resolvedApplications)
        return ComputerUseCoordinator(
            applicationCatalog: catalog,
            permissionManager: permissionManager,
            observationService: observationService ?? Phase1StubObservationService(result: makeObservation(application: resolvedApplications[0]))
        )
    }

    private func makeApplication(
        id: String,
        name: String,
        active: Bool = false
    ) -> ComputerUseApplication {
        ComputerUseApplication(
            id: id,
            bundleIdentifier: id,
            displayName: name,
            processIdentifier: 42,
            isRunning: true,
            isActive: active
        )
    }

    private func makeObservation(
        application: ComputerUseApplication? = nil
    ) -> ComputerUseObservation {
        let application = application ?? makeApplication(id: "com.example.target", name: "Target App", active: true)
        let window = ComputerUseWindow(
            id: 7,
            title: "Target Window",
            ownerProcessIdentifier: application.processIdentifier,
            bounds: ComputerUseRect(x: 0, y: 0, width: 640, height: 480),
            layer: 0,
            isOnScreen: true,
            isKeyWindow: true
        )
        return ComputerUseObservation(
            generation: 1,
            capturedAt: Date(timeIntervalSince1970: 1_000),
            target: ComputerUseTarget(application: application, window: window),
            accessibility: ComputerUseAXSnapshot(
                text: "[0] role=AXWindow title=Target Window",
                elements: [],
                wasTruncated: false
            ),
            screenshot: nil
        )
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<100 {
            if condition() {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for coordinator state")
    }
}

private final class Phase1StubApplicationCatalog: ComputerUseApplicationCatalog {
    let applications: [ComputerUseApplication]

    init(applications: [ComputerUseApplication]) {
        self.applications = applications
    }

    func listApplications() -> [ComputerUseApplication] {
        applications
    }

    func application(withID identifier: String) -> ComputerUseApplication? {
        applications.first { $0.id == identifier || $0.bundleIdentifier == identifier }
    }
}

private final class Phase1StubPermissionManager: ComputerUsePermissionManaging {
    private(set) var currentSnapshot: ComputerUsePermissionSnapshot
    private(set) var accessibilityRequestCount = 0
    private(set) var screenRecordingRequestCount = 0

    init(snapshot: ComputerUsePermissionSnapshot) {
        currentSnapshot = snapshot
    }

    func snapshot() -> ComputerUsePermissionSnapshot {
        currentSnapshot
    }

    func setSnapshot(_ snapshot: ComputerUsePermissionSnapshot) {
        currentSnapshot = snapshot
    }

    func requestAccessibility() -> Bool {
        accessibilityRequestCount += 1
        currentSnapshot = ComputerUsePermissionSnapshot(
            accessibility: .granted,
            screenRecording: currentSnapshot.screenRecording
        )
        return true
    }

    func requestScreenRecording() -> Bool {
        screenRecordingRequestCount += 1
        currentSnapshot = ComputerUsePermissionSnapshot(
            accessibility: currentSnapshot.accessibility,
            screenRecording: .granted
        )
        return true
    }
}

private final class Phase1StubObservationService: ComputerUseObservationServicing {
    let result: ComputerUseObservation
    let error: Error?
    private(set) var observeCount = 0

    init(result: ComputerUseObservation, error: Error? = nil) {
        self.result = result
        self.error = error
    }

    func observe(
        applicationID: String,
        configuration: ComputerUseObservationConfiguration,
        cancellation: ComputerUseCancellationToken
    ) throws -> ComputerUseObservation {
        observeCount += 1
        if let error {
            throw error
        }
        guard !cancellation.isCancelled else {
            throw ComputerUseObservationError.cancelled
        }
        return result
    }
}

private final class Phase1BlockingObservationService: ComputerUseObservationServicing {
    let onStart: () -> Void
    private(set) var observeCount = 0

    init(onStart: @escaping () -> Void) {
        self.onStart = onStart
    }

    func observe(
        applicationID: String,
        configuration: ComputerUseObservationConfiguration,
        cancellation: ComputerUseCancellationToken
    ) throws -> ComputerUseObservation {
        observeCount += 1
        onStart()

        while !cancellation.isCancelled {
            Thread.sleep(forTimeInterval: 0.005)
        }

        throw ComputerUseObservationError.cancelled
    }
}
