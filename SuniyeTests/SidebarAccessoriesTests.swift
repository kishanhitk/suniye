import XCTest
@testable import Suniye

/// A dot in the sidebar means that a feature cannot work. Notices that change
/// nothing stay inside their pane.
@MainActor
final class SidebarAccessoriesTests: XCTestCase {
    func testMicrophoneGetsTheDotOnlyWhenNothingCanRecord() {
        let warnedCapture = StubAudioCaptureService()
        warnedCapture.route = AudioRouteSnapshot(
            preferredInputDeviceID: nil,
            effectiveInputDeviceID: "mac-mic",
            effectiveInputName: "Mac Microphone",
            inputTransport: .builtIn,
            outputTransport: .builtIn,
            inputSampleRate: 48_000,
            inputChannelCount: 1,
            requestedEchoCancellation: true,
            effectiveEchoCancellation: false,
            backend: .inputOnlyHAL,
            fallbackReason: nil,
            standIn: nil
        )
        let warned = makeTestAppState(audioCaptureService: warnedCapture)
        XCTAssertNotNil(warned.microphone.audioRouteWarningText)
        XCTAssertNil(SettingsPane.microphone.sidebarAccessory(warned))

        let silentCapture = StubAudioCaptureService()
        silentCapture.routeSnapshotError = AudioCaptureServiceError.noInputDevice
        let silent = makeTestAppState(audioCaptureService: silentCapture)
        XCTAssertEqual(SettingsPane.microphone.sidebarAccessory(silent), .attention)
    }

    /// The Globe key setting only changes how double-tap works; a shortcut
    /// that the app refused stops dictation.
    func testShortcutsGetTheDotOnlyForARejectedShortcut() {
        let appState = makeTestAppState(systemGlobeKeyActionProvider: { .startDictation })
        appState.refreshSystemGlobeKeyAction()
        XCTAssertEqual(appState.globeDoubleTapConflict, .startDictation)
        XCTAssertNil(SettingsPane.shortcuts.sidebarAccessory(appState))

        appState.hotkeyValidationMessage = "Paste Last Transcript already uses this shortcut."
        XCTAssertEqual(SettingsPane.shortcuts.sidebarAccessory(appState), .attention)
    }

    /// macOS can hold the login item for approval while the switch shows on;
    /// an unsigned build that cannot have one shows the switch off.
    func testGeneralGetsTheDotWhenTheLoginItemCannotOpenTheApp() {
        let appState = makeTestAppState()
        appState.launchAtLoginStatus = .unsupported("This build cannot open at login.")
        XCTAssertNil(SettingsPane.general.sidebarAccessory(appState))

        appState.launchAtLoginStatus = .requiresApproval
        XCTAssertEqual(SettingsPane.general.sidebarAccessory(appState), .attention)
    }

    /// The Speech model row and the Transcripts page report the same problem,
    /// and Settings carries the dot of the pane.
    func testSpeechModelDotFollowsTheTranscriptsProblem() {
        let appState = makeGrantedAppState()
        XCTAssertNil(MainWindowSection.settings.sidebarAccessory(appState))

        appState.phase = .error
        appState.lastError = "The speech model could not load."

        XCTAssertTrue(appState.attentionItems.contains { $0.recommendedDestination == .settings(.speechModel) })
        XCTAssertEqual(SettingsPane.speechModel.sidebarAccessory(appState), .attention)
        XCTAssertEqual(MainWindowSection.settings.sidebarAccessory(appState), .attention)
    }

    func testSpeechModelShowsTheDownloadProgress() {
        let appState = makeTestAppState()
        appState.phase = .downloadingModel
        appState.downloadProgress = 0.42

        XCTAssertEqual(SettingsPane.speechModel.sidebarAccessory(appState), .status("42%"))
    }

    /// Magic Format gets the dot for the setup problems that the Transcripts
    /// page lists, such as a missing API key.
    func testMagicFormatDotFollowsTheTranscriptsProblem() {
        let appState = makeTestAppState()
        appState.llmProvider = .openAICompatible
        appState.llmEnabled = false
        XCTAssertNil(MainWindowSection.style.sidebarAccessory(appState))

        appState.llmEnabled = true
        appState.hasLLMAPIKey = false
        XCTAssertTrue(appState.attentionItems.contains { $0.recommendedDestination == .section(.style) })
        XCTAssertEqual(MainWindowSection.style.sidebarAccessory(appState), .attention)
    }

    func testAMissingGrantPutsTheDotOnSettings() {
        let appState = makeGrantedAppState()
        XCTAssertNil(MainWindowSection.settings.sidebarAccessory(appState))

        appState.hasMicPermission = false
        XCTAssertEqual(MainWindowSection.settings.sidebarAccessory(appState), .attention)
    }

    /// A test app starts without grants, which lists the Permissions pane and
    /// puts a dot on Settings before any other problem.
    private func makeGrantedAppState() -> AppState {
        let appState = makeTestAppState()
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        return appState
    }
}
