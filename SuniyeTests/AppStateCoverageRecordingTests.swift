import XCTest
@testable import Suniye

/// Coverage tests for dictation edge branches: blocked starts, stale session
/// events, edit-mode hotkey wiring, onboarding practice capture failures, and
/// auto-submit.
@MainActor
final class AppStateCoverageRecordingTests: XCTestCase {
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
        appState.startRecordingFromUI()
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

    // MARK: - Stop guards

    func testStopRecordingFromUIIgnoredWhenNotRecording() {
        let audioCapture = StubAudioCaptureService()
        let appState = readyAppState(audioCapture: audioCapture)

        appState.stopRecordingFromUI()

        XCTAssertEqual(audioCapture.stopCaptureCallCount, 0)
        XCTAssertEqual(appState.phase, .ready)
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

    // MARK: - Blocked starts

    func testStartWhileRecordingShowsAlreadyListening() async {
        let audioCapture = StubAudioCaptureService()
        let appState = readyAppState(audioCapture: audioCapture)
        await startRecording(appState, audioCapture: audioCapture)

        appState.startRecordingFromUI()
        await drainScheduledTasks()

        XCTAssertEqual(appState.floatingIndicatorState, .error(message: "Already listening"))
        XCTAssertEqual(appState.phase, .recording)
    }

    func testStartWhileRecordingWithNonListeningIndicatorComputesFallbackRestore() async {
        let audioCapture = StubAudioCaptureService()
        let appState = readyAppState(audioCapture: audioCapture)
        await startRecording(appState, audioCapture: audioCapture)

        appState.floatingIndicatorState = .idle
        appState.startRecordingFromUI()
        await drainScheduledTasks()

        XCTAssertEqual(appState.floatingIndicatorState, .error(message: "Already listening"))
    }

    func testBlockedStartMessagesForModelPhases() async {
        let appState = readyAppState()

        appState.phase = .downloadingModel
        appState.startRecordingFromUI()
        await drainScheduledTasks()
        XCTAssertEqual(appState.floatingIndicatorState, .error(message: "Model download in progress"))

        appState.phase = .loading
        appState.startRecordingFromUI()
        await drainScheduledTasks()
        XCTAssertEqual(appState.floatingIndicatorState, .error(message: "Still loading model"))
    }

    func testTransientErrorResetLeavesForeignIndicatorStateAlone() async {
        let appState = readyAppState()
        appState.phase = .loading

        appState.startRecordingFromUI()
        await drainScheduledTasks()
        XCTAssertEqual(appState.floatingIndicatorState, .error(message: "Still loading model"))

        // The pill moved on before the reset timer fired; the timer must not clobber it.
        appState.floatingIndicatorState = .processing(message: "busy elsewhere")
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        XCTAssertEqual(appState.floatingIndicatorState, .processing(message: "busy elsewhere"))
    }

    // MARK: - Stale audio events

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
            fallbackReason: nil
        )

        audioCapture.onEvent?(.routeChanged(sessionID: UUID(), route: newRoute))
        await drainScheduledTasks()
        XCTAssertNotEqual(appState.audioRouteSnapshot?.effectiveInputName, "BT Headset")

        audioCapture.onEvent?(.routeChanged(sessionID: sessionID, route: newRoute))
        await drainScheduledTasks()
        XCTAssertEqual(appState.audioRouteSnapshot?.effectiveInputName, "BT Headset")
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

    // MARK: - Onboarding practice failure epilogue

    func testOnboardingPracticeCaptureFailureShowsPracticeError() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = CapturedAudio(
            samples: Array(repeating: 0, count: 16_000),
            sampleRate: 16_000
        )
        let appState = readyAppState(audioCapture: audioCapture)
        appState.activeOnboardingStep = .speak
        await startRecording(appState, audioCapture: audioCapture)

        appState.stopRecordingFromUI()
        await waitUntil { appState.phase == .ready }
        await drainScheduledTasks()

        XCTAssertEqual(appState.onboardingPracticeText, "")
        XCTAssertEqual(appState.onboardingPracticeResult?.severity, .error)
        XCTAssertEqual(
            appState.onboardingPracticeResult?.message,
            "No speech was detected from the selected microphone."
        )
    }

    // MARK: - Auto submit

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

        appState.stopRecordingFromUI()
        await waitUntil { insertion.submitCallCount == 1 && appState.phase == .ready }

        XCTAssertEqual(insertion.submitCallCount, 1)
        XCTAssertTrue(insertion.insertedTexts.first?.contains("hello there") == true)
        XCTAssertEqual(appState.recentResults.first?.text, "hello there")
    }

    // MARK: - Edit mode hotkey wiring

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
        await waitUntil { appState.statusText == "Magic Format required" }
        XCTAssertEqual(appState.statusText, "Magic Format required")
        XCTAssertEqual(appState.lastError, "Edit Mode needs a working Magic Format provider")

        // Up: no active edit recording, so it is a no-op.
        hotkeyService.onEditModeHotkeyUp?()
        await drainScheduledTasks()
        XCTAssertNotEqual(appState.phase, .transcribing)
    }
}
