import Carbon
import XCTest
@testable import Suniye

@MainActor
final class AppStateSettingsTests: XCTestCase {
    func testHistoryLoadRecomputesStats() {
        let historyStore = TestHistoryStore()
        historyStore.value = [
            RecentResult(id: UUID(), text: "hello world", createdAt: .now, durationSeconds: 1.5, wasLLMPolished: false),
            RecentResult(id: UUID(), text: "second test clip", createdAt: .now.addingTimeInterval(-60), durationSeconds: 2.5, wasLLMPolished: true)
        ]

        let appState = makeTestAppState(historyStore: historyStore)

        XCTAssertEqual(appState.sessionCount, 2)
        XCTAssertEqual(appState.wordsTranscribed, 5)
        XCTAssertEqual(appState.totalDictationSeconds, 4.0, accuracy: 0.001)
    }

    func testDeleteRecentResultUpdatesHistoryAndStats() {
        let first = RecentResult(id: UUID(), text: "hello world", createdAt: .now, durationSeconds: 1.5, wasLLMPolished: false)
        let second = RecentResult(id: UUID(), text: "second test clip", createdAt: .now.addingTimeInterval(-60), durationSeconds: 2.5, wasLLMPolished: true)
        let historyStore = TestHistoryStore()
        historyStore.value = [first, second]

        let appState = makeTestAppState(historyStore: historyStore)
        appState.deleteRecentResult(first)

        XCTAssertEqual(appState.recentResults.count, 1)
        XCTAssertEqual(appState.sessionCount, 1)
        XCTAssertEqual(appState.wordsTranscribed, 3)
        XCTAssertEqual(historyStore.value.map(\.id), [second.id])
    }

    func testAutoSubmitDefaultsOff() {
        let appState = makeTestAppState()
        XCTAssertFalse(appState.autoSubmitEnabled)
    }

    func testPreferredInputDevicePassedToCaptureService() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.availableDevices = [
            AudioInputDevice(id: "default-device", name: "MacBook Air Microphone", isDefault: true),
            AudioInputDevice(id: "usb-mic", name: "USB Microphone", isDefault: false)
        ]

        let appState = makeTestAppState(audioCaptureService: audioCapture)
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        appState.selectedInputDeviceID = "usb-mic"

        appState.startRecordingFromUI()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(audioCapture.startCaptureCallCount, 1)
        XCTAssertEqual(audioCapture.lastPreferredInputDeviceID, "usb-mic")
        XCTAssertEqual(appState.phase, .recording)
    }

    func testStartRecordingClearsRetryableTranscriptionError() async {
        let audioCapture = StubAudioCaptureService()
        let appState = makeTestAppState(audioCaptureService: audioCapture)
        appState.phase = .error
        appState.statusText = "Transcription error"
        appState.lastError = "Transcription failed: No audio captured"
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true

        appState.startRecordingFromUI()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(audioCapture.startCaptureCallCount, 1)
        XCTAssertEqual(appState.phase, .recording)
        XCTAssertEqual(appState.statusText, "Recording")
        XCTAssertNil(appState.lastError)
    }

    func testStartRecordingDoesNotClearNonRetryableLoadError() async {
        let audioCapture = StubAudioCaptureService()
        let appState = makeTestAppState(audioCaptureService: audioCapture)
        appState.phase = .error
        appState.statusText = "Load failed"
        appState.lastError = "Model load failed: broken recognizer"
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true

        appState.startRecordingFromUI()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(audioCapture.startCaptureCallCount, 0)
        XCTAssertEqual(appState.phase, .error)
        XCTAssertEqual(appState.statusText, "Load failed")
        XCTAssertEqual(appState.lastError, "Model load failed: broken recognizer")
    }

    func testManualIndicatorToggleStartsRecordingFromReady() async {
        let appState = makeTestAppState()
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true

        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(appState.phase, .recording)
        XCTAssertEqual(
            appState.floatingIndicatorState,
            .listening(levels: Array(repeating: 0, count: 12), source: .manual)
        )
    }

    func testManualIndicatorToggleStopsRecordingAndReturnsIndicatorToIdle() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = CapturedAudio(samples: [0.1, 0.2, 0.3], sampleRate: 16_000)
        let transcriptionService = StubTranscriptionService()
        transcriptionService.transcribeResult = .success("")
        let appState = makeTestAppState(
            transcriptionService: transcriptionService,
            audioCaptureService: audioCapture
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true

        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)
        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(appState.phase, .ready)
        XCTAssertEqual(appState.floatingIndicatorState, .idle)
    }

    func testBlockedIndicatorToggleShowsInlineErrorWhenModelMissing() async {
        let appState = makeTestAppState()
        appState.phase = .needsModel

        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(appState.floatingIndicatorState, .error(message: "Download model first"))
        try? await Task.sleep(nanoseconds: 1_300_000_000)
        XCTAssertEqual(appState.floatingIndicatorState, .idle)
    }

    func testAudioLevelCallbackUpdatesListeningIndicator() async {
        let audioCapture = StubAudioCaptureService()
        let appState = makeTestAppState(audioCaptureService: audioCapture)
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true

        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)
        audioCapture.onLevelsUpdate?(Array(repeating: 0.42, count: 12))
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(
            appState.floatingIndicatorState,
            .listening(levels: Array(repeating: 0.42, count: 12), source: .manual)
        )
    }

    func testChangingHotkeyRewiresMonitoringWhenRuntimeServicesEnabled() {
        let hotkeyService = StubHotkeyService()
        let modelManager = StubModelManager()
        modelManager.isReady = false

        let appState = makeTestAppState(
            modelManager: modelManager,
            hotkeyService: hotkeyService,
            startServices: true
        )

        appState.hotkeyConfiguration = .keyCombo(keyCode: UInt32(kVK_ANSI_Grave), carbonModifiers: 0)

        XCTAssertGreaterThanOrEqual(hotkeyService.startMonitoringCallCount, 2)
        XCTAssertEqual(hotkeyService.lastConfiguration, .keyCombo(keyCode: UInt32(kVK_ANSI_Grave), carbonModifiers: 0))
    }

    func testHotkeyCallbacksStillDriveRecordingWhenRuntimeServicesEnabled() async {
        let hotkeyService = StubHotkeyService()
        let modelManager = StubModelManager()
        modelManager.isReady = false
        let transcriptionService = StubTranscriptionService()
        transcriptionService.transcribeResult = .success("")
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = CapturedAudio(samples: [0.2, 0.1], sampleRate: 16_000)
        let appState = makeTestAppState(
            modelManager: modelManager,
            transcriptionService: transcriptionService,
            audioCaptureService: audioCapture,
            hotkeyService: hotkeyService,
            startServices: true
        )
        try? await Task.sleep(nanoseconds: 100_000_000)
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        appState.phase = .ready

        hotkeyService.onHotkeyDown?()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(
            appState.floatingIndicatorState,
            .listening(levels: Array(repeating: 0, count: 12), source: .hotkey)
        )

        hotkeyService.onHotkeyUp?()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(appState.phase, .ready)
        XCTAssertEqual(appState.floatingIndicatorState, .idle)
    }

    func testDeleteModelTransitionsToNeedsModel() async {
        let modelManager = StubModelManager()
        let transcriptionService = StubTranscriptionService()
        let appState = makeTestAppState(modelManager: modelManager, transcriptionService: transcriptionService)
        appState.phase = .ready
        appState.showOnboarding = false

        appState.deleteModel()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(modelManager.deleteCallCount, 1)
        XCTAssertEqual(transcriptionService.unloadCallCount, 1)
        XCTAssertEqual(appState.phase, .needsModel)
        XCTAssertEqual(appState.statusText, "Model required")
        XCTAssertTrue(appState.showOnboarding)
    }

    func testModelDownloadDerivedUIStateWhileDownloading() {
        let modelManager = StubModelManager()
        modelManager.isReady = false
        let appState = makeTestAppState(modelManager: modelManager)
        appState.phase = .downloadingModel
        appState.downloadProgress = 0.25

        XCTAssertEqual(appState.modelStatusValue, "Downloading 25%")
        XCTAssertEqual(appState.modelStatusIcon, "arrow.down.circle.fill")
        XCTAssertEqual(appState.modelPrimaryActionTitle, "Downloading…")
        XCTAssertEqual(appState.modelDownloadProgressLabel, "25% downloaded • 170 MB of ~680 MB")
    }

    func testModelDownloadDerivedUIStateAfterFailure() {
        let modelManager = StubModelManager()
        modelManager.isReady = false
        let appState = makeTestAppState(modelManager: modelManager)
        appState.phase = .error
        appState.lastError = "network timeout"

        XCTAssertEqual(appState.modelStatusValue, "Download failed")
        XCTAssertEqual(appState.modelStatusIcon, "xmark.octagon.fill")
        XCTAssertEqual(
            appState.modelPrimaryActionDetail,
            "Last attempt failed. Retry the offline model download to enable local transcription."
        )
    }

    func testModelOperationStateDuringValidationAfterDownload() {
        let modelManager = StubModelManager()
        modelManager.isReady = false
        let appState = makeTestAppState(modelManager: modelManager)
        appState.phase = .loading

        XCTAssertTrue(appState.isModelOperationInProgress)
        XCTAssertEqual(appState.modelOperationStatusText, "Extracting and validating model…")
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
}
