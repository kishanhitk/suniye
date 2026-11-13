import Foundation
import SuniyeAnalytics
import XCTest
@testable import Suniye

@MainActor
final class AppStateUpdateTests: XCTestCase {
    func testStartUpdateControllerStartsInjectedController() {
        let updateController = StubAppUpdateController()
        let appState = makeAppState(appUpdateController: updateController)

        appState.startUpdateController()

        XCTAssertEqual(updateController.startCallCount, 1)
    }

    func testCheckForUpdatesCallsInjectedController() {
        let updateController = StubAppUpdateController()
        let appState = makeAppState(appUpdateController: updateController)

        appState.checkForUpdates()

        XCTAssertEqual(updateController.checkForUpdatesCallCount, 1)
    }

    func testUpdateControllerStateIsRefreshedFromCallback() {
        let updateController = StubAppUpdateController()
        let appState = makeAppState(appUpdateController: updateController)

        XCTAssertFalse(appState.canCheckForUpdates)

        updateController.canCheckForUpdates = true
        updateController.notifyStateChanged()

        XCTAssertTrue(appState.canCheckForUpdates)
    }

    func testRestartToUpdateInstallsTheStagedUpdate() {
        let updateController = StubAppUpdateController()
        let spy = SpyAnalytics()
        let appState = makeAppState(appUpdateController: updateController, analytics: spy)
        appState.phase = .ready

        appState.restartToUpdate()
        XCTAssertEqual(updateController.installUpdateAndRelaunchCallCount, 0)
        XCTAssertFalse(spy.trackedEventNames.contains("update_action"), "a refused restart is not a restart")

        updateController.isUpdateReadyToInstall = true
        updateController.notifyStateChanged()
        appState.restartToUpdate()

        XCTAssertTrue(appState.isUpdateReadyToInstall)
        XCTAssertEqual(updateController.installUpdateAndRelaunchCallCount, 1)
        let kinds = spy.trackedEvents.compactMap { event -> UpdateActionKind? in
            if case let .updateAction(kind, _, _) = event { return kind }
            return nil
        }
        XCTAssertEqual(kinds, [.restartToUpdate])
    }

    func testRestartToUpdateIsRefusedWhileRecordingOrTranscribing() {
        let updateController = StubAppUpdateController()
        updateController.isUpdateReadyToInstall = true
        let appState = makeAppState(appUpdateController: updateController)
        updateController.notifyStateChanged()

        for phase in [AppState.Phase.recording, .transcribing] {
            appState.phase = phase
            XCTAssertFalse(appState.canRestartToUpdate, "\(phase)")
            appState.restartToUpdate()
        }
        XCTAssertEqual(updateController.installUpdateAndRelaunchCallCount, 0)

        appState.phase = .ready
        XCTAssertTrue(appState.canRestartToUpdate)
    }

    func testAutomaticallyChecksForUpdatesWritesThroughToController() {
        let updateController = StubAppUpdateController()
        let appState = makeAppState(appUpdateController: updateController)

        appState.setAutomaticallyChecksForUpdates(true)

        XCTAssertTrue(updateController.automaticallyChecksForUpdates)
        XCTAssertTrue(appState.automaticallyChecksForUpdates)
    }

    func testUpdateChannelLoadsFromGeneralSettingsAndAppliesToController() {
        let updateController = StubAppUpdateController()
        let appState = makeAppState(
            generalSettingsStore: TestGeneralSettingsStore(value: GeneralSettings(updateChannel: .tip)),
            appUpdateController: updateController
        )

        XCTAssertEqual(appState.updateChannel, .tip)
        XCTAssertEqual(updateController.updateChannel, .tip)
    }

    func testSetUpdateChannelPersistsAndUpdatesController() {
        let updateController = StubAppUpdateController()
        let generalSettingsStore = TestGeneralSettingsStore()
        let appState = makeAppState(
            generalSettingsStore: generalSettingsStore,
            appUpdateController: updateController
        )

        appState.setUpdateChannel(.tip)

        XCTAssertEqual(appState.updateChannel, .tip)
        XCTAssertEqual(updateController.updateChannel, .tip)
        XCTAssertEqual(generalSettingsStore.latest.updateChannel, .tip)
    }

    private func makeAppState(
        generalSettingsStore: GeneralSettingsStoreProtocol = TestGeneralSettingsStore(),
        appUpdateController: StubAppUpdateController? = nil,
        analytics: Analytics = SpyAnalytics()
    ) -> AppState {
        makeTestAppState(
            llmSettingsStore: TestLLMSettingsStore(),
            generalSettingsStore: generalSettingsStore,
            historyStore: TestHistoryStore(),
            keychainService: TestKeychainService(value: nil),
            appUpdateController: appUpdateController ?? StubAppUpdateController(),
            launchAtLoginService: StubLaunchAtLoginService(),
            analytics: analytics
        )
    }
}
