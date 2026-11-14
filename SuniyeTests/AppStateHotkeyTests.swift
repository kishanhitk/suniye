import Carbon
import XCTest
@testable import Suniye

@MainActor
final class AppStateHotkeyTests: XCTestCase {
    func testChangingHotkeyRewiresMonitoringWhenRuntimeServicesEnabled() {
        let hotkeyService = StubHotkeyService()
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []

        let appState = makeTestAppState(
            modelManager: modelManager,
            hotkeyService: hotkeyService,
            startServices: true
        )

        appState.hotkeyConfiguration = .keyCombo(keyCode: UInt32(kVK_ANSI_Grave), carbonModifiers: 0)

        XCTAssertGreaterThanOrEqual(hotkeyService.startMonitoringCallCount, 2)
        XCTAssertEqual(hotkeyService.lastConfiguration, .keyCombo(keyCode: UInt32(kVK_ANSI_Grave), carbonModifiers: 0))
        XCTAssertEqual(hotkeyService.lastPasteLastTranscriptConfiguration, .pasteLastTranscriptDefault)
    }

    func testChangingPasteLastTranscriptHotkeyPersistsAndRewiresMonitoring() {
        let hotkeyService = StubHotkeyService()
        let generalSettingsStore = TestGeneralSettingsStore()
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        let configuration = HotkeyConfiguration.keyCombo(
            keyCode: UInt32(kVK_ANSI_P),
            carbonModifiers: UInt32(controlKey | cmdKey)
        )
        let appState = makeTestAppState(
            modelManager: modelManager,
            hotkeyService: hotkeyService,
            generalSettingsStore: generalSettingsStore,
            startServices: true
        )

        appState.updatePasteLastTranscriptHotkey(configuration)

        XCTAssertEqual(appState.pasteLastTranscriptHotkeyConfiguration, configuration)
        XCTAssertEqual(generalSettingsStore.latest.pasteLastTranscriptHotkeyConfiguration, configuration)
        XCTAssertEqual(hotkeyService.lastPasteLastTranscriptConfiguration, configuration)
        XCTAssertGreaterThanOrEqual(hotkeyService.startMonitoringCallCount, 2)
    }

    func testPasteLastTranscriptHotkeyRejectsInvalidAndConflictingShortcuts() {
        let appState = makeTestAppState()
        let originalPasteShortcut = appState.pasteLastTranscriptHotkeyConfiguration

        appState.updatePasteLastTranscriptHotkey(
            .keyCombo(keyCode: UInt32(kVK_ANSI_P), carbonModifiers: 0)
        )
        XCTAssertEqual(appState.pasteLastTranscriptHotkeyConfiguration, originalPasteShortcut)
        XCTAssertEqual(appState.hotkeyValidationMessage, "Paste Last Transcript requires at least one modifier key.")

        appState.updateDictationHotkey(originalPasteShortcut)
        XCTAssertEqual(appState.hotkeyConfiguration, .globe)
        XCTAssertEqual(
            appState.hotkeyValidationMessage,
            "Hold to Dictate and Paste Last Transcript must use different shortcuts."
        )

        let validPasteShortcut = HotkeyConfiguration.keyCombo(
            keyCode: UInt32(kVK_ANSI_P),
            carbonModifiers: UInt32(controlKey | cmdKey)
        )
        appState.updatePasteLastTranscriptHotkey(validPasteShortcut)
        XCTAssertEqual(appState.pasteLastTranscriptHotkeyConfiguration, validPasteShortcut)
        XCTAssertNil(appState.hotkeyValidationMessage)

        let editModeShortcut = HotkeyConfiguration.keyCombo(
            keyCode: UInt32(kVK_ANSI_E),
            carbonModifiers: UInt32(optionKey)
        )
        appState.editModeHotkeyConfiguration = editModeShortcut
        appState.updatePasteLastTranscriptHotkey(editModeShortcut)
        XCTAssertEqual(appState.pasteLastTranscriptHotkeyConfiguration, validPasteShortcut)
        XCTAssertEqual(
            appState.hotkeyValidationMessage,
            "Paste Last Transcript and Edit Mode must use different shortcuts."
        )
    }

    func testLoadedPasteLastTranscriptHotkeyIsNormalizedAwayFromConflicts() {
        let dictationShortcut = HotkeyConfiguration.pasteLastTranscriptDefault
        let settingsStore = TestGeneralSettingsStore(
            value: GeneralSettings(
                hotkeyConfiguration: dictationShortcut,
                pasteLastTranscriptHotkeyConfiguration: .globe
            )
        )

        let appState = makeTestAppState(generalSettingsStore: settingsStore)

        XCTAssertTrue(appState.pasteLastTranscriptHotkeyConfiguration.isModifiedKeyCombo)
        XCTAssertNotEqual(appState.pasteLastTranscriptHotkeyConfiguration, dictationShortcut)
        XCTAssertEqual(
            settingsStore.latest.pasteLastTranscriptHotkeyConfiguration,
            appState.pasteLastTranscriptHotkeyConfiguration
        )
    }

    func testHotkeyCallbacksStillDriveRecordingWhenRuntimeServicesEnabled() async {
        let hotkeyService = StubHotkeyService()
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        let transcriptionService = StubTranscriptionService()
        transcriptionService.transcribeResult = .success("")
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = makeValidCapturedAudio()
        var now = Date(timeIntervalSince1970: 1_000)
        let appState = makeTestAppState(
            modelManager: modelManager,
            transcriptionService: transcriptionService,
            audioCaptureService: audioCapture,
            hotkeyService: hotkeyService,
            nowProvider: { now },
            startServices: true
        )
        try? await Task.sleep(nanoseconds: 100_000_000)
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        appState.activeOnboardingStep = nil
        appState.phase = .ready

        hotkeyService.onHotkeyDown?()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(
            appState.floatingIndicatorState,
            .listening(levels: Array(repeating: 0, count: AudioLevelMeter.bandCount), source: .hotkey, preview: .off)
        )

        now = now.addingTimeInterval(1)
        hotkeyService.onHotkeyUp?()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(appState.phase, .ready)
        XCTAssertEqual(appState.floatingIndicatorState, .idle)
    }

    func testPasteLastTranscriptHotkeyCallbackUsesLatestHistoryResult() async {
        let hotkeyService = StubHotkeyService()
        let textInsertionService = SpyTextInsertionService()
        let historyStore = TestHistoryStore()
        historyStore.value = [
            RecentResult(id: UUID(), text: "latest transcript", createdAt: .now, durationSeconds: 1, wasLLMPolished: false)
        ]
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        let appState = makeTestAppState(
            modelManager: modelManager,
            textInsertionService: textInsertionService,
            hotkeyService: hotkeyService,
            historyStore: historyStore,
            startServices: true
        )

        hotkeyService.onPasteLastTranscript?()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(textInsertionService.insertedTexts, ["latest transcript"])
        XCTAssertEqual(textInsertionService.submitCallCount, 0)
        XCTAssertEqual(appState.recentResults.count, 1)
        XCTAssertEqual(historyStore.value.count, 1)
    }
}
