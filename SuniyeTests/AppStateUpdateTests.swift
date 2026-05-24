import Foundation
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

    func testAutomaticallyChecksForUpdatesWritesThroughToController() {
        let updateController = StubAppUpdateController()
        let appState = makeAppState(appUpdateController: updateController)

        appState.setAutomaticallyChecksForUpdates(true)

        XCTAssertTrue(updateController.automaticallyChecksForUpdates)
        XCTAssertTrue(appState.automaticallyChecksForUpdates)
    }

    func testMagicFormatStatusIsOffWhenDisabled() {
        let appState = makeAppState()

        XCTAssertEqual(appState.magicFormatSetupState, .off)
        XCTAssertEqual(appState.llmStatusHint, "Turn it on to improve dictation before text is pasted.")
    }

    func testMagicFormatStatusNeedsAPIKeyWhenEnabledWithoutKey() {
        let appState = makeAppState()
        appState.llmEnabled = true

        XCTAssertEqual(appState.magicFormatSetupState, .needsAPIKey)
        XCTAssertTrue(appState.attentionItems.contains {
            $0.id == "llm-key-missing"
                && $0.title == "Magic Format needs an API key"
                && $0.detail == "Magic Format is on, but your API key is missing."
        })
    }

    func testMagicFormatStatusNeedsServiceSetupWhenEndpointInvalid() {
        let appState = makeAppState()
        appState.llmEnabled = true
        appState.llmEndpointURLString = "not a url"

        XCTAssertEqual(appState.magicFormatSetupState, .needsServiceSetup)
        XCTAssertEqual(appState.llmEndpointValidationError, "Enter a valid service URL.")
        XCTAssertTrue(appState.attentionItems.contains {
            $0.id == "llm-endpoint-invalid"
                && $0.title == "Magic Format needs service setup"
                && $0.detail == "Enter a valid service URL."
        })
    }

    func testAttentionItemsExposeMicrophonePermissionFixAction() throws {
        let appState = makeAppState()
        appState.hasMicPermission = false

        let item = try XCTUnwrap(appState.attentionItems.first { $0.id == "mic-permission-missing" })
        XCTAssertEqual(item.fixAction, .requestMicrophonePermission)
        XCTAssertEqual(item.fixTitle, "Grant Access")
    }

    func testAttentionItemsExposeAccessibilityPermissionFixAction() throws {
        let appState = makeAppState()
        appState.hasAccessibilityPermission = false

        let item = try XCTUnwrap(appState.attentionItems.first { $0.id == "accessibility-permission-missing" })
        XCTAssertEqual(item.fixAction, .requestAccessibilityPermission)
        XCTAssertEqual(item.fixTitle, "Grant Access")
    }

    func testMagicFormatStatusIsReadyWhenEnabledAndConfigured() {
        let appState = makeTestAppState(
            llmSettingsStore: TestLLMSettingsStore(),
            generalSettingsStore: TestGeneralSettingsStore(),
            historyStore: TestHistoryStore(),
            keychainService: TestKeychainService(value: "test-key"),
            appUpdateController: StubAppUpdateController(),
            launchAtLoginService: StubLaunchAtLoginService()
        )
        appState.llmEnabled = true
        appState.refreshLLMKeyStatus()

        XCTAssertEqual(appState.magicFormatSetupState, .ready)
        XCTAssertEqual(appState.llmKeyStatusText, "Saved")
    }

    private func makeAppState(
        appUpdateController: StubAppUpdateController? = nil
    ) -> AppState {
        makeTestAppState(
            llmSettingsStore: TestLLMSettingsStore(),
            generalSettingsStore: TestGeneralSettingsStore(),
            historyStore: TestHistoryStore(),
            keychainService: TestKeychainService(value: nil),
            appUpdateController: appUpdateController ?? StubAppUpdateController(),
            launchAtLoginService: StubLaunchAtLoginService()
        )
    }
}
