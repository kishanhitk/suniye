import AppKit
import Carbon
import SuniyeAnalytics
import XCTest
@testable import Suniye

@MainActor
final class AppStateSettingsTests: XCTestCase {
    func testAutoSubmitDefaultsOff() {
        let appState = makeTestAppState()
        XCTAssertFalse(appState.autoSubmitEnabled)
    }

    func testSoundFeedbackDefaultsOff() {
        let appState = makeTestAppState()
        XCTAssertFalse(appState.soundFeedbackEnabled)
    }

    func testChangingSoundFeedbackPersistsGeneralSettings() {
        let generalSettingsStore = TestGeneralSettingsStore()
        let appState = makeTestAppState(generalSettingsStore: generalSettingsStore)

        appState.soundFeedbackEnabled = true

        XCTAssertTrue(generalSettingsStore.latest.soundFeedbackEnabled)
    }

    func testFloatingIndicatorSettingsDefaultToVisibleIdleAndDefaultPlacement() {
        let appState = makeTestAppState()

        XCTAssertFalse(appState.hideFloatingIndicatorWhenIdle)
        XCTAssertNil(appState.floatingIndicatorPlacement)
    }

    func testFloatingIndicatorSettingsLoadFromGeneralSettings() {
        let placement = FloatingIndicatorPlacement(centerXRatio: 0.18, bottomYRatio: 0.22)
        let generalSettingsStore = TestGeneralSettingsStore(
            value: GeneralSettings(
                preferredInputDeviceID: nil,
                autoSubmitEnabled: false,
                hotkeyConfiguration: .globe,
                echoCancellationEnabled: false,
                hideFloatingIndicatorWhenIdle: true,
                floatingIndicatorPlacement: placement,
                hasSeenOnboardingWelcome: false,
                hasCompletedCoreOnboarding: false
            )
        )
        let appState = makeTestAppState(generalSettingsStore: generalSettingsStore)

        XCTAssertTrue(appState.hideFloatingIndicatorWhenIdle)
        XCTAssertEqual(appState.floatingIndicatorPlacement, placement)
    }

    func testChangingHideFloatingIndicatorWhenIdlePersistsGeneralSettings() {
        let generalSettingsStore = TestGeneralSettingsStore()
        let appState = makeTestAppState(generalSettingsStore: generalSettingsStore)

        appState.hideFloatingIndicatorWhenIdle = true

        XCTAssertTrue(generalSettingsStore.latest.hideFloatingIndicatorWhenIdle)
    }

    func testResetFloatingIndicatorPlacementClearsSavedPlacement() {
        let placement = FloatingIndicatorPlacement(centerXRatio: 0.33, bottomYRatio: 0.18)
        let generalSettingsStore = TestGeneralSettingsStore(
            value: GeneralSettings(floatingIndicatorPlacement: placement)
        )
        let appState = makeTestAppState(generalSettingsStore: generalSettingsStore)

        appState.resetFloatingIndicatorPlacement()

        XCTAssertNil(appState.floatingIndicatorPlacement)
        XCTAssertNil(generalSettingsStore.latest.floatingIndicatorPlacement)
    }

    func testHandlingFloatingIndicatorPlacementChangePersistsGeneralSettings() {
        let generalSettingsStore = TestGeneralSettingsStore()
        let appState = makeTestAppState(generalSettingsStore: generalSettingsStore)
        let placement = FloatingIndicatorPlacement(centerXRatio: 0.61, bottomYRatio: 0.12)

        appState.handleFloatingIndicatorPlacementChanged(placement)

        XCTAssertEqual(appState.floatingIndicatorPlacement, placement)
        XCTAssertEqual(generalSettingsStore.latest.floatingIndicatorPlacement, placement)
    }

    func testSelectedASRModelPersistsToGeneralSettings() {
        let generalSettingsStore = TestGeneralSettingsStore()
        let appState = makeTestAppState(generalSettingsStore: generalSettingsStore)

        appState.selectedASRModelID = .senseVoice

        XCTAssertEqual(generalSettingsStore.latest.selectedASRModelID, .senseVoice)
    }

    func testLaunchAtLoginToggleTracksServiceStatus() {
        let launchService = StubLaunchAtLoginService()
        let appState = makeTestAppState(launchAtLoginService: launchService)

        XCTAssertEqual(appState.launchAtLoginStatus, .disabled)

        appState.setLaunchAtLoginEnabled(true)

        XCTAssertEqual(appState.launchAtLoginStatus, .enabled)
        XCTAssertNil(appState.launchAtLoginError)
    }

    func testLaunchAtLoginToggleSurfacesError() {
        let launchService = StubLaunchAtLoginService()
        launchService.setEnabledError = FakeError(message: "blocked")
        let appState = makeTestAppState(launchAtLoginService: launchService)

        appState.setLaunchAtLoginEnabled(true)

        XCTAssertEqual(appState.launchAtLoginStatus, .disabled)
        XCTAssertEqual(appState.launchAtLoginError, "blocked")
    }

    func testOpenMicrophonePrivacySettingsUsesPrivacyURL() {
        var openedURLs: [URL] = []
        let appState = makeTestAppState(fileOpener: {
            openedURLs.append($0)
            return true
        })

        appState.openMicrophonePrivacySettings()

        XCTAssertEqual(openedURLs.count, 1)
        XCTAssertEqual(openedURLs.first?.absoluteString, "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Microphone")
    }

    func testOpenAccessibilityPrivacySettingsUsesPrivacyURL() {
        var openedURLs: [URL] = []
        let appState = makeTestAppState(fileOpener: {
            openedURLs.append($0)
            return true
        })

        appState.openAccessibilityPrivacySettings()

        XCTAssertEqual(openedURLs.count, 1)
        XCTAssertEqual(openedURLs.first?.absoluteString, "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")
    }

    func testOpenSystemSettingsFailureSetsLastError() {
        var attemptedURLs: [URL] = []
        let appState = makeTestAppState(fileOpener: { url in
            attemptedURLs.append(url)
            return false
        })

        appState.openMicrophonePrivacySettings()

        XCTAssertEqual(attemptedURLs.count, 2)
        XCTAssertEqual(appState.lastError, "Unable to open System Settings.")
    }

    func testOpenAppleIntelligenceSettingsOpensFirstCandidate() {
        var openedURLs: [URL] = []
        let appState = makeTestAppState(fileOpener: { url in
            openedURLs.append(url)
            return true
        })

        appState.openAppleIntelligenceSettings()

        XCTAssertEqual(openedURLs.count, 1)
        XCTAssertEqual(
            openedURLs.first?.absoluteString,
            "x-apple.systempreferences:com.apple.Siri-Settings.extension"
        )
        XCTAssertNil(appState.lastError)
    }
}
