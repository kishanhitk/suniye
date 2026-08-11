import AppKit
import Carbon
import SuniyeAnalytics
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

    func testCopyLastTranscriptCopiesNewestHistoryResult() {
        let first = RecentResult(id: UUID(), text: "latest transcript", createdAt: .now, durationSeconds: 1.5, wasLLMPolished: false)
        let second = RecentResult(id: UUID(), text: "older transcript", createdAt: .now.addingTimeInterval(-60), durationSeconds: 2.5, wasLLMPolished: true)
        let historyStore = TestHistoryStore()
        historyStore.value = [first, second]
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("previous clipboard", forType: .string)

        let appState = makeTestAppState(historyStore: historyStore)
        let didCopy = appState.copyLastTranscript()

        XCTAssertTrue(didCopy)
        XCTAssertEqual(pasteboard.string(forType: .string), "latest transcript")
    }

    func testCopyLastTranscriptReturnsFalseWhenHistoryIsEmpty() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("previous clipboard", forType: .string)
        let appState = makeTestAppState()

        let didCopy = appState.copyLastTranscript()

        XCTAssertFalse(didCopy)
        XCTAssertEqual(pasteboard.string(forType: .string), "previous clipboard")
    }

    func testPasteLastTranscriptWorksWhileBusyWithoutChangingHistoryOrSubmitting() {
        let result = RecentResult(
            id: UUID(),
            text: "latest transcript",
            createdAt: .now,
            durationSeconds: 1.5,
            wasLLMPolished: false
        )
        let historyStore = TestHistoryStore()
        historyStore.value = [result]
        let textInsertionService = SpyTextInsertionService()
        let appState = makeTestAppState(
            textInsertionService: textInsertionService,
            historyStore: historyStore
        )

        appState.phase = .recording
        XCTAssertTrue(appState.pasteLastTranscript())
        appState.phase = .transcribing
        XCTAssertTrue(appState.pasteLastTranscript())

        XCTAssertEqual(textInsertionService.insertedTexts, ["latest transcript", "latest transcript"])
        XCTAssertEqual(textInsertionService.submitCallCount, 0)
        XCTAssertEqual(appState.recentResults, [result])
        XCTAssertEqual(appState.phase, .transcribing)
    }

    func testPasteLastTranscriptSilentlyReturnsFalseWhenHistoryIsEmpty() {
        let textInsertionService = SpyTextInsertionService()
        let appState = makeTestAppState(textInsertionService: textInsertionService)

        XCTAssertFalse(appState.pasteLastTranscript())
        XCTAssertTrue(textInsertionService.attemptedTexts.isEmpty)
        XCTAssertNil(appState.lastError)
        XCTAssertEqual(appState.floatingIndicatorState, .idle)
    }

    func testPasteLastTranscriptSilentlyReturnsFalseWhenLatestHistoryTextIsEmpty() {
        let historyStore = TestHistoryStore()
        historyStore.value = [
            RecentResult(id: UUID(), text: "", createdAt: .now, durationSeconds: 1, wasLLMPolished: false)
        ]
        let textInsertionService = SpyTextInsertionService()
        let appState = makeTestAppState(
            textInsertionService: textInsertionService,
            historyStore: historyStore
        )

        XCTAssertFalse(appState.pasteLastTranscript())
        XCTAssertTrue(textInsertionService.attemptedTexts.isEmpty)
        XCTAssertNil(appState.lastError)
        XCTAssertEqual(appState.floatingIndicatorState, .idle)
    }

    func testPasteLastTranscriptFailureUsesConfiguredShortcutInWarning() {
        let historyStore = TestHistoryStore()
        historyStore.value = [
            RecentResult(id: UUID(), text: "latest transcript", createdAt: .now, durationSeconds: 1, wasLLMPolished: false)
        ]
        let textInsertionService = SpyTextInsertionService()
        textInsertionService.insertError = FakeError(message: "no focus")
        let appState = makeTestAppState(
            textInsertionService: textInsertionService,
            historyStore: historyStore
        )
        appState.updatePasteLastTranscriptHotkey(
            .keyCombo(keyCode: UInt32(kVK_ANSI_P), carbonModifiers: UInt32(controlKey | cmdKey))
        )

        XCTAssertFalse(appState.pasteLastTranscript())

        XCTAssertEqual(appState.lastError, "Couldn't insert text. Focus a text field, then press ⌃⌘P.")
        XCTAssertEqual(
            appState.floatingIndicatorState,
            .error(message: "Couldn't insert text. Focus a text field, then press ⌃⌘P.")
        )
    }

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

    func testLegacyInstallWithModelInstalledMarksOnboardingComplete() {
        let modelManager = StubModelManager()
        let generalSettingsStore = TestGeneralSettingsStore()

        let appState = makeTestAppState(
            modelManager: modelManager,
            generalSettingsStore: generalSettingsStore
        )
        appState.startOnboardingIfNeeded()

        XCTAssertTrue(appState.hasSeenOnboardingWelcome)
        XCTAssertTrue(appState.hasCompletedCoreOnboarding)
        XCTAssertNil(appState.activeOnboardingStep)
        XCTAssertEqual(generalSettingsStore.latest.onboardingProgress, .finished)
        // Legacy Bools stay written (derived) for downgrade safety.
        XCTAssertEqual(generalSettingsStore.latest.hasSeenOnboardingWelcome, true)
        XCTAssertEqual(generalSettingsStore.latest.hasCompletedCoreOnboarding, true)
    }

    func testFreshInstallStartsAtWelcome() {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        let generalSettingsStore = TestGeneralSettingsStore()

        let appState = makeTestAppState(
            modelManager: modelManager,
            generalSettingsStore: generalSettingsStore
        )
        appState.startOnboardingIfNeeded()

        XCTAssertFalse(appState.hasSeenOnboardingWelcome)
        XCTAssertFalse(appState.hasCompletedCoreOnboarding)
        XCTAssertEqual(appState.activeOnboardingStep, .welcome)
        XCTAssertEqual(generalSettingsStore.latest.onboardingProgress, .notStarted)
    }

    func testSeenWelcomeResumesSpeak() {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        let generalSettingsStore = TestGeneralSettingsStore(
            value: GeneralSettings(
                preferredInputDeviceID: nil,
                hasSeenOnboardingWelcome: true,
                hasCompletedCoreOnboarding: false
            )
        )

        let appState = makeTestAppState(
            modelManager: modelManager,
            generalSettingsStore: generalSettingsStore
        )
        appState.startOnboardingIfNeeded()

        XCTAssertEqual(appState.activeOnboardingStep, .speak)
    }

    func testFirstLaunchRecordedFlagPersistsThroughSettings() {
        let generalSettingsStore = TestGeneralSettingsStore(
            value: GeneralSettings(firstLaunchRecorded: true)
        )
        let appState = makeTestAppState(generalSettingsStore: generalSettingsStore)

        // Any persisting change must round-trip the flag untouched.
        appState.autoSubmitEnabled = true

        XCTAssertEqual(generalSettingsStore.latest.firstLaunchRecorded, true)
    }

    func testLegacyOnboardingStateMarksFirstLaunchAsRecorded() {
        let generalSettingsStore = TestGeneralSettingsStore(
            value: GeneralSettings(
                hasSeenOnboardingWelcome: true,
                hasCompletedCoreOnboarding: false
            )
        )

        _ = makeTestAppState(generalSettingsStore: generalSettingsStore)

        XCTAssertTrue(generalSettingsStore.latest.firstLaunchRecorded)
    }

    func testLegacyUsageWithoutOnboardingFlagsMarksFirstLaunchAsRecorded() {
        let generalSettingsStore = TestGeneralSettingsStore(
            value: GeneralSettings(preferredInputDeviceID: "built-in-microphone")
        )

        _ = makeTestAppState(generalSettingsStore: generalSettingsStore)

        XCTAssertTrue(generalSettingsStore.latest.firstLaunchRecorded)
    }

    func testChosenGemmaDownloadResumesAtBootstrap() async {
        // The user chose the local model during setup, the download died after
        // they moved on: bootstrap must self-heal instead of silently inserting
        // raw text forever.
        let localManager = StubLocalLLMModelManager()
        let appState = makeTestAppState(localLLMModelManager: localManager)
        appState.llmEnabled = true
        appState.llmProvider = .localGemma

        await appState.bootstrap()
        for _ in 0 ..< 20 {
            await Task.yield()
        }

        XCTAssertEqual(localManager.downloadCallCount, 1)
    }

    func testCanceledGemmaDownloadDoesNotResumeAtBootstrap() async {
        let localManager = StubLocalLLMModelManager()
        let settings = TestGeneralSettingsStore(
            value: GeneralSettings(localGemmaDownloadCancelled: true)
        )
        let appState = makeTestAppState(
            localLLMModelManager: localManager,
            generalSettingsStore: settings
        )
        appState.llmEnabled = true
        appState.llmProvider = .localGemma

        await appState.bootstrap()

        XCTAssertEqual(localManager.downloadCallCount, 0)
    }

    func testGemmaResumeSkippedWhenInstalledOrNotChosen() {
        let installed = StubLocalLLMModelManager()
        installed.installedModelIDs.insert(installed.preferredModelID)
        let installedState = makeTestAppState(localLLMModelManager: installed)
        installedState.llmEnabled = true
        installedState.llmProvider = .localGemma
        installedState.resumeInterruptedLocalGemmaDownloadIfNeeded()
        XCTAssertEqual(installed.downloadCallCount, 0)

        let notChosen = StubLocalLLMModelManager()
        let notChosenState = makeTestAppState(localLLMModelManager: notChosen)
        notChosenState.llmEnabled = false
        notChosenState.llmProvider = .localGemma
        notChosenState.resumeInterruptedLocalGemmaDownloadIfNeeded()
        XCTAssertEqual(notChosen.downloadCallCount, 0)

        let unsupported = StubLocalLLMModelManager()
        unsupported.isHardwareSupported = false
        let unsupportedState = makeTestAppState(localLLMModelManager: unsupported)
        unsupportedState.llmEnabled = true
        unsupportedState.llmProvider = .localGemma
        unsupportedState.resumeInterruptedLocalGemmaDownloadIfNeeded()
        XCTAssertEqual(unsupported.downloadCallCount, 0)
    }

    func testFinishOnboardingClearsActiveStep() {
        let appState = makeTestAppState(
            generalSettingsStore: TestGeneralSettingsStore(value: GeneralSettings(onboardingProgress: .typeAnywhereReached))
        )
        appState.startOnboardingIfNeeded()

        appState.finishOnboarding()

        XCTAssertNil(appState.activeOnboardingStep)
    }

    func testASRModelReadyRequiresInstalledAndUsablePhase() {
        let modelManager = StubModelManager()
        let appState = makeTestAppState(modelManager: modelManager)

        appState.phase = .loading
        XCTAssertFalse(appState.asrModelReady)

        appState.phase = .ready
        XCTAssertTrue(appState.asrModelReady)

        appState.phase = .recording
        XCTAssertTrue(appState.asrModelReady)

        modelManager.installedModelIDs = []
        XCTAssertFalse(appState.asrModelReady)
    }


    func testSoundFeedbackDisabledDoesNotPlayRecordingStartSound() async {
        let audioCapture = StubAudioCaptureService()
        let soundFeedback = SpySoundFeedbackService()
        let appState = makeTestAppState(
            audioCaptureService: audioCapture,
            soundFeedbackService: soundFeedback
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true

        appState.startRecordingFromUI()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(audioCapture.startCaptureCallCount, 1)
        XCTAssertTrue(soundFeedback.playedEvents.isEmpty)
    }

    func testSoundFeedbackEnabledDoesNotPlayAudioThatWouldBeCapturedAtRecordingStart() async {
        let audioCapture = StubAudioCaptureService()
        let soundFeedback = SpySoundFeedbackService()
        let appState = makeTestAppState(
            audioCaptureService: audioCapture,
            soundFeedbackService: soundFeedback
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        appState.soundFeedbackEnabled = true

        appState.startRecordingFromUI()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(audioCapture.startCaptureCallCount, 1)
        XCTAssertTrue(soundFeedback.playedEvents.isEmpty)
    }

    func testSoundFeedbackEnabledDoesNotPlayRecordingStartWhenCaptureFails() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.startCaptureError = FakeError(message: "mic unavailable")
        let soundFeedback = SpySoundFeedbackService()
        let appState = makeTestAppState(
            audioCaptureService: audioCapture,
            soundFeedbackService: soundFeedback
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        appState.soundFeedbackEnabled = true

        appState.startRecordingFromUI()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(audioCapture.startCaptureCallCount, 1)
        XCTAssertEqual(soundFeedback.playedEvents, [.error])
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
            .listening(levels: Array(repeating: 0, count: AudioLevelMeter.bandCount), source: .manual, preview: .off)
        )
    }

    func testManualIndicatorToggleStopsRecordingAndReturnsIndicatorToIdle() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = makeValidCapturedAudio()
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

    func testSuccessfulTranscriptionClearsStaleLastError() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = makeValidCapturedAudio()
        let transcriptionService = StubTranscriptionService()
        transcriptionService.transcribeResult = .success("Hello")
        let appState = makeTestAppState(
            transcriptionService: transcriptionService,
            audioCaptureService: audioCapture
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        appState.lastError = "Transcription failed: previous error"

        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)
        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNil(appState.lastError)
        XCTAssertEqual(appState.phase, .ready)
    }

    func testSystemInsertionFormatsTextForCursorContext() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = makeValidCapturedAudio()
        let transcriptionService = StubTranscriptionService()
        transcriptionService.transcribeResult = .success("Strong.")
        let textInsertionService = SpyTextInsertionService()
        textInsertionService.insertionContext = TextInsertionContext(
            value: "coffeemachine",
            selectedRange: NSRange(location: 6, length: 0),
            selectedText: nil,
            previousCharacter: "e",
            nextCharacter: "m"
        )
        let appState = makeTestAppState(
            transcriptionService: transcriptionService,
            audioCaptureService: audioCapture,
            textInsertionService: textInsertionService
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true

        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)
        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(textInsertionService.insertedTexts, [" strong "])
        XCTAssertEqual(appState.recentResults.first?.text, "Strong.")
    }

    func testDictationCopiesToClipboardWithoutAccessibility() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = makeValidCapturedAudio()
        let transcriptionService = StubTranscriptionService()
        transcriptionService.transcribeResult = .success("Hello without access")
        let textInsertionService = SpyTextInsertionService()
        let spy = SpyAnalytics()
        let appState = makeTestAppState(
            transcriptionService: transcriptionService,
            audioCaptureService: audioCapture,
            textInsertionService: textInsertionService,
            analytics: spy,
            accessibilityTrustProvider: { false }
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = false

        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)
        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(textInsertionService.copiedTexts, ["Hello without access"])
        XCTAssertTrue(textInsertionService.insertedTexts.isEmpty)
        XCTAssertEqual(appState.recentResults.first?.text, "Hello without access")
        let metrics = spy.trackedEvents.compactMap { event -> DictationMetrics? in
            if case let .dictationCompleted(value) = event { return value }
            return nil
        }.last
        XCTAssertEqual(metrics?.destination, .clipboard)
    }

    func testDictationRefreshesAccessibilityBeforeChoosingInsertionDestination() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = makeValidCapturedAudio()
        let transcriptionService = StubTranscriptionService()
        transcriptionService.transcribeResult = .success("Hello after grant")
        let textInsertionService = SpyTextInsertionService()
        let appState = makeTestAppState(
            transcriptionService: transcriptionService,
            audioCaptureService: audioCapture,
            textInsertionService: textInsertionService,
            accessibilityTrustProvider: { true }
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = false

        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)
        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(textInsertionService.insertedTexts, ["Hello after grant"])
        XCTAssertTrue(textInsertionService.copiedTexts.isEmpty)
    }

    func testClipboardFailureDoesNotRecordDictation() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = makeValidCapturedAudio()
        let transcriptionService = StubTranscriptionService()
        transcriptionService.transcribeResult = .success("Clipboard failure")
        let textInsertionService = SpyTextInsertionService()
        textInsertionService.copyError = FakeError(message: "clipboard unavailable")
        let appState = makeTestAppState(
            transcriptionService: transcriptionService,
            audioCaptureService: audioCapture,
            textInsertionService: textInsertionService,
            accessibilityTrustProvider: { false }
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = false

        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)
        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(textInsertionService.copiedTexts.isEmpty)
        XCTAssertTrue(appState.recentResults.isEmpty)
        XCTAssertEqual(appState.lastError, "Transcription failed: clipboard unavailable")
    }

    func testSoundFeedbackEnabledPlaysSuccessForCompletedDictation() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = makeValidCapturedAudio()
        let transcriptionService = StubTranscriptionService()
        transcriptionService.transcribeResult = .success("Hello")
        let soundFeedback = SpySoundFeedbackService()
        let appState = makeTestAppState(
            transcriptionService: transcriptionService,
            audioCaptureService: audioCapture,
            soundFeedbackService: soundFeedback
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        appState.soundFeedbackEnabled = true

        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)
        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(soundFeedback.playedEvents, [.transcriptionSucceeded])
    }

    func testSoundFeedbackEnabledPlaysSuccessForSubmitOnlyCommand() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = makeValidCapturedAudio()
        let transcriptionService = StubTranscriptionService()
        transcriptionService.transcribeResult = .success("send")
        let textInsertionService = SpyTextInsertionService()
        let soundFeedback = SpySoundFeedbackService()
        let appState = makeTestAppState(
            transcriptionService: transcriptionService,
            audioCaptureService: audioCapture,
            textInsertionService: textInsertionService,
            soundFeedbackService: soundFeedback
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        appState.soundFeedbackEnabled = true

        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)
        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(textInsertionService.submitCallCount, 1)
        XCTAssertEqual(soundFeedback.playedEvents, [.transcriptionSucceeded])
    }

    func testSoundFeedbackEnabledPlaysErrorForInsertionFailure() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = makeValidCapturedAudio()
        let transcriptionService = StubTranscriptionService()
        transcriptionService.transcribeResult = .success("Hello")
        let textInsertionService = SpyTextInsertionService()
        textInsertionService.insertError = FakeError(message: "paste failed")
        let soundFeedback = SpySoundFeedbackService()
        let appState = makeTestAppState(
            transcriptionService: transcriptionService,
            audioCaptureService: audioCapture,
            textInsertionService: textInsertionService,
            soundFeedbackService: soundFeedback
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        appState.soundFeedbackEnabled = true
        appState.autoSubmitEnabled = true

        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)
        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(soundFeedback.playedEvents, [.error])
        XCTAssertEqual(textInsertionService.attemptedTexts, ["Hello"])
        XCTAssertTrue(textInsertionService.insertedTexts.isEmpty)
        XCTAssertEqual(textInsertionService.submitCallCount, 0)
        XCTAssertEqual(appState.lastTranscriptText, "Hello")
        XCTAssertEqual(appState.recentResults.count, 1)
        XCTAssertEqual(appState.phase, .ready)
        XCTAssertEqual(appState.lastError, "Couldn't insert text. Focus a text field, then press ⌃⌘V.")
        XCTAssertEqual(
            appState.floatingIndicatorState,
            .error(message: "Couldn't insert text. Focus a text field, then press ⌃⌘V.")
        )

        textInsertionService.insertError = nil
        XCTAssertTrue(appState.pasteLastTranscript())
        XCTAssertEqual(textInsertionService.insertedTexts, ["Hello"])
        XCTAssertEqual(textInsertionService.submitCallCount, 0)
        XCTAssertEqual(appState.recentResults.count, 1)
        XCTAssertNil(appState.lastError)
        XCTAssertEqual(appState.floatingIndicatorState, .idle)
        XCTAssertEqual(soundFeedback.playedEvents, [.error])
    }

    func testSoundFeedbackEnabledPlaysErrorForTranscriptionFailure() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = makeValidCapturedAudio()
        let transcriptionService = StubTranscriptionService()
        transcriptionService.transcribeResult = .failure(FakeError(message: "decoder failed"))
        let soundFeedback = SpySoundFeedbackService()
        let appState = makeTestAppState(
            transcriptionService: transcriptionService,
            audioCaptureService: audioCapture,
            soundFeedbackService: soundFeedback
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        appState.soundFeedbackEnabled = true

        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)
        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(soundFeedback.playedEvents, [.error])
    }

    func testSoundFeedbackEnabledPlaysErrorForEmptyNoSubmitTranscription() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = makeValidCapturedAudio()
        let transcriptionService = StubTranscriptionService()
        transcriptionService.transcribeResult = .success("")
        let soundFeedback = SpySoundFeedbackService()
        let appState = makeTestAppState(
            transcriptionService: transcriptionService,
            audioCaptureService: audioCapture,
            soundFeedbackService: soundFeedback
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        appState.soundFeedbackEnabled = true

        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)
        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(soundFeedback.playedEvents, [.error])
    }

    func testSoundFeedbackEnabledPlaysErrorForEmptyPracticeTranscription() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = makeValidCapturedAudio()
        let transcriptionService = StubTranscriptionService()
        transcriptionService.transcribeResult = .success("")
        let soundFeedback = SpySoundFeedbackService()
        let appState = makeTestAppState(
            transcriptionService: transcriptionService,
            audioCaptureService: audioCapture,
            soundFeedbackService: soundFeedback
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        appState.soundFeedbackEnabled = true
        appState.activeOnboardingStep = .speak

        appState.startRecordingFromUI()
        try? await Task.sleep(nanoseconds: 50_000_000)
        appState.stopRecordingFromUI()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(soundFeedback.playedEvents, [.error])
    }

    func testPracticeModeStoresPreviewWithoutInsertionOrHistory() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = makeValidCapturedAudio()
        let transcriptionService = StubTranscriptionService()
        transcriptionService.transcribeResult = .success("Hello from practice")
        let textInsertionService = SpyTextInsertionService()
        let historyStore = TestHistoryStore()
        let appState = makeTestAppState(
            transcriptionService: transcriptionService,
            audioCaptureService: audioCapture,
            textInsertionService: textInsertionService,
            historyStore: historyStore
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        appState.activeOnboardingStep = .speak

        appState.startRecordingFromUI()
        try? await Task.sleep(nanoseconds: 50_000_000)
        appState.stopRecordingFromUI()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(appState.onboardingPracticeText, "Hello from practice")
        XCTAssertEqual(appState.onboardingPracticeResult?.severity, .success)
        XCTAssertTrue(textInsertionService.insertedTexts.isEmpty)
        XCTAssertEqual(textInsertionService.submitCallCount, 0)
        XCTAssertTrue(appState.recentResults.isEmpty)
        XCTAssertTrue(historyStore.value.isEmpty)
    }

    func testPracticeModeFailureClearsStalePreview() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = makeValidCapturedAudio()
        let transcriptionService = StubTranscriptionService()
        transcriptionService.transcribeResult = .failure(FakeError(message: "decoder failed"))
        let appState = makeTestAppState(
            transcriptionService: transcriptionService,
            audioCaptureService: audioCapture
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        appState.activeOnboardingStep = .speak
        appState.onboardingPracticeText = "Old preview"
        appState.onboardingPracticeResult = OnboardingPracticeResult(
            message: "That's it — this works in any app.",
            severity: .success
        )

        appState.startRecordingFromUI()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(appState.onboardingPracticeText, "")
        XCTAssertNil(appState.onboardingPracticeResult)

        appState.stopRecordingFromUI()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(appState.onboardingPracticeText, "")
        XCTAssertEqual(appState.onboardingPracticeResult?.severity, .error)
        XCTAssertEqual(appState.onboardingPracticeResult?.message, "decoder failed")
    }

    func testRecordingDoesNotStartWhileWelcomeStepIsActive() async {
        let audioCapture = StubAudioCaptureService()
        let appState = makeTestAppState(audioCaptureService: audioCapture)
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        appState.activeOnboardingStep = .welcome

        appState.startRecordingFromUI()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(audioCapture.startCaptureCallCount, 0)
        XCTAssertEqual(appState.phase, .ready)
        XCTAssertEqual(appState.floatingIndicatorState, .error(message: "Finish setup first"))
    }

    func testRecordingStartsOnTypeAnywhereStep() async {
        // Real dictation is deliberately allowed on the Accessibility screen
        // (the "try it in Notes" demo depends on it).
        let audioCapture = StubAudioCaptureService()
        let appState = makeTestAppState(audioCaptureService: audioCapture)
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        appState.activeOnboardingStep = .typeAnywhere

        appState.startRecordingFromUI()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(audioCapture.startCaptureCallCount, 1)
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

    func testBlockedIndicatorToggleDuringTranscribingRestoresProcessingState() async {
        let appState = makeTestAppState()
        appState.phase = .transcribing
        appState.floatingIndicatorState = .processing(message: "Transcribing...")

        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(appState.floatingIndicatorState, .error(message: "Still processing previous clip"))
        try? await Task.sleep(nanoseconds: 1_300_000_000)
        // Restore path now matches the transcribe transition's labeled pill.
        XCTAssertEqual(appState.floatingIndicatorState, .processing(message: "Transcribing..."))
    }

    func testBlockedIndicatorToggleDuringPolishingPreservesStageLabel() async {
        let appState = makeTestAppState()
        appState.phase = .transcribing
        // The pill has already advanced past "Transcribing..." to a polish stage.
        appState.floatingIndicatorState = .processing(message: "Polishing...")

        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(appState.floatingIndicatorState, .error(message: "Still processing previous clip"))
        try? await Task.sleep(nanoseconds: 1_300_000_000)
        // Restore must not regress the stage back to "Transcribing...".
        XCTAssertEqual(appState.floatingIndicatorState, .processing(message: "Polishing..."))
    }


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
        appState.activeOnboardingStep = nil
        appState.phase = .ready

        hotkeyService.onHotkeyDown?()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(
            appState.floatingIndicatorState,
            .listening(levels: Array(repeating: 0, count: AudioLevelMeter.bandCount), source: .hotkey, preview: .off)
        )

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

    func testDeleteModelTransitionsToNeedsModel() async {
        let modelManager = StubModelManager()
        let transcriptionService = StubTranscriptionService()
        let appState = makeTestAppState(modelManager: modelManager, transcriptionService: transcriptionService)
        appState.phase = .ready

        appState.deleteModel()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(modelManager.deleteCallCount, 1)
        XCTAssertEqual(transcriptionService.unloadCallCount, 1)
        XCTAssertEqual(appState.phase, .needsModel)
        XCTAssertEqual(appState.statusText, "Model required")
        XCTAssertNil(appState.activeOnboardingStep)
        XCTAssertTrue(appState.hasCompletedCoreOnboarding)
    }

    func testSelectingInstalledASRModelLoadsRecognizerAndPersistsSelection() async {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = [.parakeetV3, .senseVoice]
        let transcriptionService = StubTranscriptionService()
        let appState = makeTestAppState(modelManager: modelManager, transcriptionService: transcriptionService)
        appState.phase = .ready
        appState.selectedASRModelID = .parakeetV3
        appState.loadedASRModelID = .parakeetV3

        appState.selectASRModel(.senseVoice)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(appState.selectedASRModelID, .senseVoice)
        XCTAssertEqual(appState.loadedASRModelID, .senseVoice)
        XCTAssertEqual(appState.phase, .ready)
        XCTAssertEqual(transcriptionService.loadedConfigs.last?.modelID, .senseVoice)
    }

    func testBootstrapFallsBackToAnotherInstalledModelWhenPreferredLoadFails() async {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = [.parakeetV3, .senseVoice, .moonshineBase]
        let transcriptionService = StubTranscriptionService()
        transcriptionService.loadModelErrorsByModelID = [
            .parakeetV3: FakeError(message: "selected broken"),
            .senseVoice: FakeError(message: "fallback broken")
        ]
        let generalSettingsStore = TestGeneralSettingsStore(
            value: GeneralSettings(
                preferredInputDeviceID: nil,
                hasSeenOnboardingWelcome: true,
                hasCompletedCoreOnboarding: true,
                selectedASRModelID: .parakeetV3
            )
        )
        let appState = makeTestAppState(
            modelManager: modelManager,
            transcriptionService: transcriptionService,
            generalSettingsStore: generalSettingsStore
        )

        await appState.bootstrap()

        XCTAssertEqual(appState.selectedASRModelID, .moonshineBase)
        XCTAssertEqual(appState.loadedASRModelID, .moonshineBase)
        XCTAssertEqual(appState.phase, .ready)
        XCTAssertEqual(generalSettingsStore.latest.selectedASRModelID, .moonshineBase)
        XCTAssertEqual(transcriptionService.loadedConfigs.map(\.modelID), [.parakeetV3, .senseVoice, .moonshineBase])
    }

    func testDeletingCurrentASRModelFallsBackToInstalledAlternative() async {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = [.parakeetV3, .senseVoice]
        let transcriptionService = StubTranscriptionService()
        let appState = makeTestAppState(modelManager: modelManager, transcriptionService: transcriptionService)
        appState.phase = .ready
        appState.selectedASRModelID = .parakeetV3
        appState.loadedASRModelID = .parakeetV3

        appState.deleteASRModel(.parakeetV3)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(modelManager.lastDeletedModelID, .parakeetV3)
        XCTAssertEqual(appState.selectedASRModelID, .senseVoice)
        XCTAssertEqual(appState.loadedASRModelID, .senseVoice)
        XCTAssertEqual(appState.phase, .ready)
    }

    func testDeletingCurrentASRModelSkipsBrokenFallbackAndPersistsSuccessfulAlternative() async {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = [.parakeetV3, .senseVoice, .moonshineBase]
        let transcriptionService = StubTranscriptionService()
        transcriptionService.loadModelErrorsByModelID = [
            .senseVoice: FakeError(message: "fallback broken")
        ]
        let generalSettingsStore = TestGeneralSettingsStore(
            value: GeneralSettings(
                preferredInputDeviceID: nil,
                hasSeenOnboardingWelcome: true,
                hasCompletedCoreOnboarding: true,
                selectedASRModelID: .parakeetV3
            )
        )
        let appState = makeTestAppState(
            modelManager: modelManager,
            transcriptionService: transcriptionService,
            generalSettingsStore: generalSettingsStore
        )
        appState.phase = .ready
        appState.selectedASRModelID = .parakeetV3
        appState.loadedASRModelID = .parakeetV3

        appState.deleteASRModel(.parakeetV3)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(modelManager.lastDeletedModelID, .parakeetV3)
        XCTAssertEqual(appState.selectedASRModelID, .moonshineBase)
        XCTAssertEqual(appState.loadedASRModelID, .moonshineBase)
        XCTAssertEqual(appState.phase, .ready)
        XCTAssertEqual(generalSettingsStore.latest.selectedASRModelID, .moonshineBase)
        XCTAssertEqual(transcriptionService.loadedConfigs.map(\.modelID), [.senseVoice, .moonshineBase])
    }

    func testModelDownloadSuccessStaysOnSpeakScreen() async {
        // No auto-advance: the screen updates in place when the model turns
        // ready; moving on stays a user action.
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        let generalSettingsStore = TestGeneralSettingsStore(
            value: GeneralSettings(onboardingProgress: .speakReached)
        )
        let appState = makeTestAppState(
            modelManager: modelManager,
            generalSettingsStore: generalSettingsStore
        )
        appState.startOnboardingIfNeeded()
        appState.hasMicPermission = true

        appState.startModelDownload()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(appState.phase, .ready)
        XCTAssertTrue(appState.asrModelReady)
        XCTAssertEqual(appState.activeOnboardingStep, .speak)
        XCTAssertFalse(appState.hasCompletedCoreOnboarding)
    }

    func testOnboardingModelDownloadUsesSelectedASRModel() async {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        let generalSettingsStore = TestGeneralSettingsStore(
            value: GeneralSettings(
                preferredInputDeviceID: nil,
                hasSeenOnboardingWelcome: true,
                hasCompletedCoreOnboarding: false,
                selectedASRModelID: .parakeetV3
            )
        )
        let appState = makeTestAppState(
            modelManager: modelManager,
            generalSettingsStore: generalSettingsStore
        )
        appState.activeOnboardingStep = .speak
        appState.hasMicPermission = true

        appState.startModelDownload()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(modelManager.lastDownloadedModelID, .parakeetV3)
    }

    func testModelDownloadDerivedUIStateWhileDownloading() {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        let now = Date(timeIntervalSince1970: 600)
        let appState = makeTestAppState(
            modelManager: modelManager,
            nowProvider: { now }
        )
        appState.phase = .downloadingModel
        appState.activeASRModelOperationID = .parakeetV3
        appState.downloadProgress = 0.25
        appState.modelDownloadStartedAt = Date(timeIntervalSince1970: 540)

        XCTAssertEqual(appState.modelStatusValue, "Downloading 25%")
        XCTAssertEqual(appState.modelStatusIcon, "arrow.down.circle.fill")
        XCTAssertEqual(appState.modelPrimaryActionTitle, "Downloading…")
        XCTAssertEqual(appState.modelDownloadProgressLabel, "25% downloaded • 170 MB of ~680 MB\nAbout 3m left")
    }

    func testCurrentModelStaysCurrentWhileAnotherModelDownloads() {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = [.senseVoice]
        let appState = makeTestAppState(modelManager: modelManager)
        appState.selectedASRModelID = .senseVoice
        appState.loadedASRModelID = .senseVoice
        appState.phase = .downloadingModel
        appState.activeASRModelOperationID = .moonshineBase
        appState.downloadProgress = 0.2

        XCTAssertEqual(appState.modelStatusValue, "Current")
        XCTAssertEqual(appState.modelStatusIcon, "checkmark.circle.fill")
        XCTAssertEqual(appState.modelPrimaryActionTitle, "Current")
    }

    func testModelDownloadProgressLabelShowsEstimatingBeforeETAIsKnown() {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        let appState = makeTestAppState(modelManager: modelManager)
        appState.phase = .downloadingModel
        appState.activeASRModelOperationID = .parakeetV3
        appState.downloadProgress = 0

        XCTAssertEqual(appState.modelDownloadProgressLabel, "0% downloaded • Zero KB of ~680 MB\nEstimating time remaining")
    }

    func testModelDownloadDerivedUIStateAfterFailure() {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        let appState = makeTestAppState(modelManager: modelManager)
        appState.phase = .error
        appState.lastFailedASRModelID = .parakeetV3
        appState.lastFailedASRModelError = "network timeout"

        XCTAssertEqual(appState.modelStatusValue, "Download failed")
        XCTAssertEqual(appState.modelStatusIcon, "xmark.octagon.fill")
        XCTAssertEqual(
            appState.modelPrimaryActionDetail,
            "Last attempt failed. Retry setup for Parakeet TDT 0.6B v3 to use it for dictation."
        )
    }

    func testModelOperationStateDuringValidationAfterDownload() {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = []
        let appState = makeTestAppState(modelManager: modelManager)
        appState.phase = .loading
        appState.activeASRModelOperationID = .parakeetV3

        XCTAssertTrue(appState.isModelOperationInProgress)
        XCTAssertEqual(appState.modelOperationStatusText, "Extracting and validating Parakeet TDT 0.6B v3…")
    }

    func testMissingLibraryModelShowsDownloadActionTitle() {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = [.parakeetV3]
        let appState = makeTestAppState(modelManager: modelManager)
        appState.selectedASRModelID = .parakeetV3
        appState.loadedASRModelID = .parakeetV3

        XCTAssertEqual(appState.asrModelPrimaryActionTitle(for: .whisperLargeV3Turbo), "Download Model")
        XCTAssertEqual(appState.asrModelPrimaryActionTitle(for: .parakeetV3), "Current")
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
