import Carbon
import XCTest
@testable import Suniye

/// Hands-free dictation from the keyboard: double-tap to lock, Esc to cancel.
@MainActor
final class AppStateHandsFreeTests: XCTestCase {
    private let firstPress = Date(timeIntervalSince1970: 1_000)
    private var now = Date(timeIntervalSince1970: 1_000)

    private let hotkey = StubHotkeyService()
    private let audio = StubAudioCaptureService()
    private let transcription = StubTranscriptionService()
    private let insertion = SpyTextInsertionService()
    private let sounds = SpySoundFeedbackService()

    private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func drain() async {
        for _ in 0 ..< 8 { await Task.yield() }
    }

    /// Longer than the double-tap window, in real time.
    private func waitPastSecondTapWindow() async {
        try? await Task.sleep(nanoseconds: UInt64((DictationShortcutGesture.tapInterval + 0.15) * 1_000_000_000))
        await drain()
    }

    private func readyState(globeKeyAction: SystemGlobeKeyAction = .doNothing) async -> AppState {
        let modelManager = StubModelManager()
        modelManager.installedModelIDs = [.parakeetV3]
        audio.stopCaptureResult = makeValidCapturedAudio()
        transcription.transcribeResult = .success("hello world")
        let appState = makeTestAppState(
            modelManager: modelManager,
            transcriptionService: transcription,
            audioCaptureService: audio,
            textInsertionService: insertion,
            hotkeyService: hotkey,
            soundFeedbackService: sounds,
            generalSettingsStore: TestGeneralSettingsStore(value: GeneralSettings(onboardingProgress: .finished)),
            nowProvider: { [unowned self] in self.now },
            systemGlobeKeyActionProvider: { globeKeyAction },
            startServices: true
        )
        await waitUntil { appState.phase == .ready }
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        return appState
    }

    private func press(at milliseconds: Int) async {
        now = firstPress.addingTimeInterval(Double(milliseconds) / 1_000)
        hotkey.onHotkeyDown?()
        await drain()
    }

    private func release(at milliseconds: Int) async {
        now = firstPress.addingTimeInterval(Double(milliseconds) / 1_000)
        hotkey.onHotkeyUp?()
        await drain()
    }

    private func doubleTap() async {
        await press(at: 0)
        await release(at: 120)
        await press(at: 260)
        await release(at: 380)
    }

    func testHoldStillTranscribesOnRelease() async {
        let appState = await readyState()

        await press(at: 0)
        await release(at: 1_800)
        await waitUntil { appState.phase == .ready }

        XCTAssertEqual(transcription.transcribeCallCount, 1)
        XCTAssertEqual(insertion.insertedTexts, ["hello world"])
    }

    func testDoubleTapKeepsRecordingUntilTheNextPressPastesIt() async {
        let appState = await readyState()

        await doubleTap()
        await waitPastSecondTapWindow()

        XCTAssertEqual(appState.phase, .recording, "a locked recording outlives the double-tap window")
        XCTAssertEqual(audio.startCaptureCallCount, 1, "the lock keeps the recording from the first press")
        XCTAssertEqual(audio.cancelCaptureCallCount, 0)
        XCTAssertEqual(transcription.transcribeCallCount, 0)
        XCTAssertTrue(hotkey.isCancelShortcutEnabled)
        guard case .listening(_, .manual, _) = appState.floatingIndicatorState else {
            return XCTFail("a locked recording shows the hands-free pill, got \(appState.floatingIndicatorState)")
        }

        await press(at: 9_000)
        XCTAssertEqual(appState.phase, .recording, "the finishing press waits for its release")
        await release(at: 9_100)
        await waitUntil { appState.phase == .ready }

        XCTAssertEqual(transcription.transcribeCallCount, 1)
        XCTAssertEqual(insertion.insertedTexts, ["hello world"])
        XCTAssertFalse(hotkey.isCancelShortcutEnabled)
    }

    func testSingleTapIsDroppedWithNoTextAndNoError() async {
        let appState = await readyState()

        await press(at: 0)
        await release(at: 120)
        XCTAssertEqual(appState.phase, .recording, "a tap waits for a possible second tap")
        await waitUntil { appState.phase == .ready }

        XCTAssertEqual(audio.cancelCaptureCallCount, 1)
        XCTAssertEqual(transcription.transcribeCallCount, 0)
        XCTAssertTrue(insertion.attemptedTexts.isEmpty)
        XCTAssertEqual(appState.floatingIndicatorState, .idle)
        XCTAssertNil(appState.lastError)
        XCTAssertTrue(sounds.playedEvents.isEmpty)
    }

    func testEscDiscardsALockedRecordingAndPastesNothing() async {
        let appState = await readyState()
        await doubleTap()

        hotkey.onCancel?()
        await waitUntil { appState.phase == .ready }

        XCTAssertEqual(audio.cancelCaptureCallCount, 1)
        XCTAssertEqual(transcription.transcribeCallCount, 0)
        XCTAssertTrue(insertion.attemptedTexts.isEmpty)
        XCTAssertTrue(appState.recentResults.isEmpty)
        XCTAssertEqual(appState.floatingIndicatorState, .error(message: "Dictation canceled"))
        XCTAssertFalse(hotkey.isCancelShortcutEnabled, "Esc goes back to the apps when the recording ends")

        await press(at: 5_000)
        XCTAssertEqual(appState.phase, .recording, "the next press starts a new recording")
    }

    func testEscDiscardsAHeldRecordingAndItsReleaseDoesNothing() async {
        let appState = await readyState()
        await press(at: 0)

        hotkey.onCancel?()
        await waitUntil { appState.phase == .ready }
        await release(at: 2_000)
        await waitPastSecondTapWindow()

        XCTAssertEqual(appState.phase, .ready)
        XCTAssertEqual(audio.stopCaptureCallCount, 0)
        XCTAssertEqual(transcription.transcribeCallCount, 0)
    }

    func testClickOnThePillFinishesALockedRecording() async {
        let appState = await readyState()
        await doubleTap()

        appState.toggleFloatingIndicatorRecording()
        await waitUntil { appState.phase == .ready }

        XCTAssertEqual(insertion.insertedTexts, ["hello world"])
    }

    func testGlobeDoubleTapDoesNotLockWhenMacOSDictationUsesIt() async {
        let appState = await readyState(globeKeyAction: .startDictation)
        XCTAssertEqual(appState.globeDoubleTapConflict, .startDictation)

        await press(at: 0)
        await release(at: 120)
        XCTAssertEqual(appState.phase, .ready, "with no lock to wait for, a tap is dropped at once")
        await press(at: 260)
        await release(at: 380)
        await waitPastSecondTapWindow()

        XCTAssertEqual(appState.phase, .ready)
        XCTAssertEqual(audio.cancelCaptureCallCount, 2)
        XCTAssertEqual(transcription.transcribeCallCount, 0)
    }

    func testGlobeDoubleTapDoesNotLockWhenATapOpensEmojiAndSymbols() async {
        let appState = await readyState(globeKeyAction: .showEmojiAndSymbols)
        XCTAssertEqual(appState.globeDoubleTapConflict, .showEmojiAndSymbols)

        await doubleTap()
        await waitPastSecondTapWindow()

        XCTAssertEqual(appState.phase, .ready)
        XCTAssertEqual(transcription.transcribeCallCount, 0)
    }

    func testKeyComboDoubleTapLocksWhateverTheGlobeSetting() async {
        let appState = await readyState(globeKeyAction: .startDictation)
        appState.updateDictationHotkey(.keyCombo(keyCode: UInt32(kVK_ANSI_D), carbonModifiers: UInt32(controlKey | optionKey)))
        XCTAssertNil(appState.globeDoubleTapConflict)

        await doubleTap()
        await waitPastSecondTapWindow()

        XCTAssertEqual(appState.phase, .recording)
    }

    func testFnChordsAreDroppedAndDoNotLock() async {
        let appState = await readyState()

        await press(at: 0)
        hotkey.onHotkeyChord?()
        await release(at: 150)
        XCTAssertEqual(appState.phase, .ready, "fn+Delete is dropped at once, with no wait for a second tap")
        await press(at: 250)
        hotkey.onHotkeyChord?()
        await release(at: 380)
        await waitPastSecondTapWindow()

        XCTAssertEqual(appState.phase, .ready)
        XCTAssertEqual(transcription.transcribeCallCount, 0)
        XCTAssertNil(appState.lastError)
    }

    func testFnChordWhileLockedKeepsRecording() async {
        let appState = await readyState()
        await doubleTap()

        await press(at: 5_000)
        hotkey.onHotkeyChord?()
        await release(at: 5_100)
        await waitPastSecondTapWindow()

        XCTAssertEqual(appState.phase, .recording)
        XCTAssertEqual(transcription.transcribeCallCount, 0)
    }

    func testSingleTapOnThePracticeScreenStillAsksForAHold() async {
        let appState = await readyState()
        appState.activeOnboardingStep = .speak

        await press(at: 0)
        await release(at: 120)
        await waitUntil { appState.phase == .ready }

        XCTAssertEqual(appState.onboardingPracticeResult?.message, AudioCaptureOutcome.tooShort.userMessage)
        XCTAssertEqual(transcription.transcribeCallCount, 0)
    }
}
