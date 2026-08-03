import CoreGraphics
import Foundation
import XCTest
@testable import Suniye

@MainActor
final class ComputerUsePhase2CoordinatorTests: XCTestCase {
    func testPhaseTitlesCoverTheTaskStates() {
        let coordinator = makePhase2Coordinator(
            observation: makePhase2Observation(),
            actionService: Phase2StubActionService()
        )
        let expectedTitles: [(ComputerUseCoordinatorPhase, String)] = [
            (.observed, "Observation captured"),
            (.runningAgent, "Computer Use is working"),
            (.agentCompleted, "Computer Use finished"),
            (.failed, "Computer Use failed"),
        ]

        for (phase, title) in expectedTitles {
            coordinator.phase = phase
            XCTAssertEqual(coordinator.phaseTitle, title)
        }
    }

    func testPlatformRunnerDelegatesApplicationAndPermissionBoundaries() async {
        let observation = makePhase2Observation()
        let application = observation.target.application
        let permissionManager = Phase2StubPermissionManager(granted: true)
        let runner = ComputerUsePlatformRunner(
            applicationCatalog: Phase2StubApplicationCatalog(applications: [application]),
            permissionManager: permissionManager,
            observationService: Phase2StubObservationService(result: observation)
        )

        let listedApplications = await runner.listApplications()
        let listedPermissions = await runner.permissionSnapshot()
        XCTAssertEqual(listedApplications, [application])
        XCTAssertEqual(listedPermissions, permissionManager.snapshot())
    }

    private func makePhase2Coordinator(
        observation: ComputerUseObservation,
        actionService: ComputerUseActionServicing
    ) -> ComputerUseCoordinator {
        let application = observation.target.application
        return ComputerUseCoordinator(
            applicationCatalog: Phase2StubApplicationCatalog(applications: [application]),
            permissionManager: Phase2StubPermissionManager(granted: true),
            observationService: Phase2StubObservationService(result: observation),
            actionService: actionService
        )
    }
}
