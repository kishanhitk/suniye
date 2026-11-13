import XCTest
@testable import Suniye

@MainActor
final class AppStateRecordingTests: XCTestCase {
    private func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func drainScheduledTasks() async {
        for _ in 0 ..< 8 {
            await Task.yield()
        }
    }

    private func readyAppState(
        audioCapture: StubAudioCaptureService = StubAudioCaptureService(),
        transcriptionService: StubTranscriptionService = StubTranscriptionService(),
        textInsertionService: SpyTextInsertionService = SpyTextInsertionService()
    ) -> AppState {
        let appState = makeTestAppState(
            transcriptionService: transcriptionService,
            audioCaptureService: audioCapture,
            textInsertionService: textInsertionService
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        return appState
    }

    private func startRecording(_ appState: AppState, audioCapture: StubAudioCaptureService) async {
        let started = expectation(description: "capture started")
        audioCapture.onStartCapture = { _ in started.fulfill() }
        appState.toggleFloatingIndicatorRecording()
        await fulfillment(of: [started], timeout: 1)
        await drainScheduledTasks()
    }

    func testRecordingStartWarmsTargetAppAccessibility() async {
        let audioCapture = StubAudioCaptureService()
        let insertion = SpyTextInsertionService()
        let appState = readyAppState(audioCapture: audioCapture, textInsertionService: insertion)

        await startRecording(appState, audioCapture: audioCapture)

        XCTAssertEqual(insertion.warmTargetAppAccessibilityCallCount, 1)
    }

    func testFinishEditModeRecordingNoOpWhenNotRecording() async {
        let audioCapture = StubAudioCaptureService()
        let appState = readyAppState(audioCapture: audioCapture)

        await appState.finishEditModeRecording()

        XCTAssertEqual(appState.phase, .ready)
        XCTAssertEqual(audioCapture.stopCaptureCallCount, 0)
    }

    func testFinishEditModeRecordingIgnoresManualRecordingSession() async {
        let audioCapture = StubAudioCaptureService()
        let appState = readyAppState(audioCapture: audioCapture)
        await startRecording(appState, audioCapture: audioCapture)

        await appState.finishEditModeRecording()

        // The trigger does not match the manual session, so nothing stops.
        XCTAssertEqual(appState.phase, .recording)
        XCTAssertEqual(audioCapture.stopCaptureCallCount, 0)
    }

    /// A shortcut press while a pill recording runs starts nothing.
    func testShortcutPressWhileRecordingShowsAlreadyListening() async {
        let audioCapture = StubAudioCaptureService()
        let hotkey = StubHotkeyService()
        let appState = await recordingFromThePill(audioCapture: audioCapture, hotkey: hotkey)

        hotkey.onHotkeyDown?()
        await drainScheduledTasks()

        XCTAssertEqual(appState.floatingIndicatorState, .error(message: "Already listening"))
        XCTAssertEqual(appState.phase, .recording)
    }

    private func recordingFromThePill(audioCapture: StubAudioCaptureService, hotkey: StubHotkeyService) async -> AppState {
        let appState = makeTestAppState(
            audioCaptureService: audioCapture,
            hotkeyService: hotkey,
            generalSettingsStore: TestGeneralSettingsStore(value: GeneralSettings(onboardingProgress: .finished)),
            startServices: true
        )
        await waitUntil { appState.phase == .ready }
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        await startRecording(appState, audioCapture: audioCapture)
        return appState
    }

    func testBlockedStartMessagesForModelPhases() async {
        let appState = readyAppState()

        appState.phase = .downloadingModel
        appState.toggleFloatingIndicatorRecording()
        await drainScheduledTasks()
        XCTAssertEqual(appState.floatingIndicatorState, .error(message: "Model download in progress"))

        appState.phase = .loading
        appState.toggleFloatingIndicatorRecording()
        await drainScheduledTasks()
        XCTAssertEqual(appState.floatingIndicatorState, .error(message: "Still loading model"))
    }

    func testTransientErrorResetLeavesForeignIndicatorStateAlone() async {
        let appState = readyAppState()
        appState.phase = .loading

        appState.toggleFloatingIndicatorRecording()
        await drainScheduledTasks()
        XCTAssertEqual(appState.floatingIndicatorState, .error(message: "Still loading model"))

        // The pill moved on before the reset timer fired; the timer must not clobber it.
        appState.floatingIndicatorState = .processing(message: "busy elsewhere")
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        XCTAssertEqual(appState.floatingIndicatorState, .processing(message: "busy elsewhere"))
    }

    func testInterruptionForUnknownSessionIsIgnored() async {
        let audioCapture = StubAudioCaptureService()
        let appState = readyAppState(audioCapture: audioCapture)
        await startRecording(appState, audioCapture: audioCapture)

        audioCapture.onEvent?(.interrupted(sessionID: UUID(), reason: .inputMuted))
        await drainScheduledTasks()

        XCTAssertEqual(appState.phase, .recording)
        XCTAssertEqual(audioCapture.cancelCaptureCallCount, 0)
    }

    func testRouteChangedEventUpdatesSnapshotOnlyForActiveSession() async throws {
        let audioCapture = StubAudioCaptureService()
        let appState = readyAppState(audioCapture: audioCapture)
        await startRecording(appState, audioCapture: audioCapture)
        let sessionID = try XCTUnwrap(audioCapture.lastStartedSessionID)

        let newRoute = AudioRouteSnapshot(
            preferredInputDeviceID: nil,
            effectiveInputDeviceID: "bt-headset",
            effectiveInputName: "BT Headset",
            inputTransport: .bluetooth,
            outputTransport: .bluetooth,
            inputSampleRate: 16_000,
            inputChannelCount: 1,
            requestedEchoCancellation: false,
            effectiveEchoCancellation: false,
            backend: .inputOnlyHAL,
            fallbackReason: nil,
            standIn: nil
        )

        audioCapture.onEvent?(.routeChanged(sessionID: UUID(), route: newRoute))
        await drainScheduledTasks()
        XCTAssertNotEqual(appState.microphone.audioRouteSnapshot?.effectiveInputName, "BT Headset")

        audioCapture.onEvent?(.routeChanged(sessionID: sessionID, route: newRoute))
        await drainScheduledTasks()
        XCTAssertEqual(appState.microphone.audioRouteSnapshot?.effectiveInputName, "BT Headset")
    }

    func testAudioLevelsIgnoredWhenIndicatorIsNotListening() async throws {
        let audioCapture = StubAudioCaptureService()
        let appState = readyAppState(audioCapture: audioCapture)
        await startRecording(appState, audioCapture: audioCapture)
        let sessionID = try XCTUnwrap(audioCapture.lastStartedSessionID)

        appState.floatingIndicatorState = .idle
        audioCapture.onEvent?(.levelsUpdated(
            sessionID: sessionID,
            levels: Array(repeating: 0.9, count: AudioLevelMeter.bandCount)
        ))
        await drainScheduledTasks()

        XCTAssertEqual(appState.floatingIndicatorState, .idle)
    }

    func testOnboardingPracticeCaptureFailureShowsPracticeError() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = CapturedAudio(
            samples: Array(repeating: 0, count: 16_000),
            sampleRate: 16_000
        )
        let appState = readyAppState(audioCapture: audioCapture)
        appState.activeOnboardingStep = .speak
        await startRecording(appState, audioCapture: audioCapture)

        appState.toggleFloatingIndicatorRecording()
        await waitUntil { appState.phase == .ready }
        await drainScheduledTasks()

        XCTAssertEqual(appState.onboardingPracticeText, "")
        XCTAssertEqual(appState.onboardingPracticeResult?.severity, .error)
        XCTAssertEqual(
            appState.onboardingPracticeResult?.message,
            "No speech was detected from the selected microphone."
        )
    }

    func testAutoSubmitSubmitsAfterInsertingText() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = makeValidCapturedAudio()
        let transcription = StubTranscriptionService()
        transcription.transcribeResult = .success("hello there")
        let insertion = SpyTextInsertionService()
        let appState = readyAppState(
            audioCapture: audioCapture,
            transcriptionService: transcription,
            textInsertionService: insertion
        )
        appState.autoSubmitEnabled = true
        await startRecording(appState, audioCapture: audioCapture)

        appState.toggleFloatingIndicatorRecording()
        await waitUntil { insertion.submitCallCount == 1 && appState.phase == .ready }

        XCTAssertEqual(insertion.submitCallCount, 1)
        XCTAssertTrue(insertion.insertedTexts.first?.contains("hello there") == true)
        XCTAssertEqual(appState.recentResults.first?.text, "hello there")
    }

    func testDictationEndingInSendPastesEveryWordWithoutPressingEnter() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = makeValidCapturedAudio()
        let transcription = StubTranscriptionService()
        transcription.transcribeResult = .success("Tell me when you are ready to send.")
        let insertion = SpyTextInsertionService()
        let appState = readyAppState(
            audioCapture: audioCapture,
            transcriptionService: transcription,
            textInsertionService: insertion
        )
        await startRecording(appState, audioCapture: audioCapture)

        appState.toggleFloatingIndicatorRecording()
        await waitUntil { appState.phase == .ready }

        XCTAssertEqual(insertion.insertedTexts, ["Tell me when you are ready to send."])
        XCTAssertEqual(insertion.submitCallCount, 0)
        XCTAssertEqual(appState.recentResults.first?.text, "Tell me when you are ready to send.")
    }

    /// KIS-205: a paste into an app that publishes no focus information still
    /// delivers the text, but Return must not follow it — nothing knows where
    /// it would land.
    func testAutoSubmitWithheldWhenTheInsertionCouldNotBeVerified() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = makeValidCapturedAudio()
        let transcription = StubTranscriptionService()
        transcription.transcribeResult = .success("hello there")
        let insertion = SpyTextInsertionService()
        insertion.insertOutcome = .unverified
        let appState = readyAppState(
            audioCapture: audioCapture,
            transcriptionService: transcription,
            textInsertionService: insertion
        )
        appState.autoSubmitEnabled = true
        await startRecording(appState, audioCapture: audioCapture)

        appState.toggleFloatingIndicatorRecording()
        await waitUntil { appState.phase == .ready }

        XCTAssertEqual(insertion.submitCallCount, 0)
        XCTAssertTrue(insertion.insertedTexts.first?.contains("hello there") == true)
        XCTAssertEqual(appState.recentResults.first?.text, "hello there")
    }

    func testEditModeHotkeyCallbacksAreWiredWhenServicesStart() async {
        let hotkeyService = StubHotkeyService()
        let appState = makeTestAppState(
            hotkeyService: hotkeyService,
            startServices: true
        )
        await waitUntil { appState.phase != .loading }

        XCTAssertNotNil(hotkeyService.onEditModeHotkeyDown)
        XCTAssertNotNil(hotkeyService.onEditModeHotkeyUp)

        // Down: Edit Mode is unavailable (Magic Format off), so it must refuse.
        hotkeyService.onEditModeHotkeyDown?()
        await waitUntil { appState.lastError != nil }
        XCTAssertEqual(appState.lastError, "Edit Mode needs a working Magic Format provider")

        // Up: no active edit recording, so it is a no-op.
        hotkeyService.onEditModeHotkeyUp?()
        await drainScheduledTasks()
        XCTAssertNotEqual(appState.phase, .transcribing)
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

        appState.toggleFloatingIndicatorRecording()
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

        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(audioCapture.startCaptureCallCount, 1)
        XCTAssertEqual(soundFeedback.playedEvents, [.error])
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
}
