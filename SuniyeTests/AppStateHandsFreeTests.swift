import Carbon
import SuniyeAnalytics
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
    private let analytics = SpyAnalytics()

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
            analytics: analytics,
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

    private var completedSources: [DictationSource] {
        analytics.trackedEvents.compactMap { event -> DictationSource? in
            if case let .dictationCompleted(metrics) = event { return metrics.source }
            return nil
        }
    }

    func testAnalyticsTellALockedDictationFromAHeldOne() async {
        let appState = await readyState()

        await doubleTap()
        await press(at: 9_000)
        await release(at: 9_100)
        await waitUntil { appState.phase == .ready && completedSources.count == 1 }
        await press(at: 20_000)
        await release(at: 21_000)
        await waitUntil { appState.phase == .ready && completedSources.count == 2 }

        XCTAssertEqual(completedSources, [.hotkeyLock, .hotkey], "the lock label does not carry over to the next dictation")
    }

    func testAnalyticsCountAnEscCancelOnlyWhenTheRecordingWasDiscarded() async {
        let appState = await readyState()

        await press(at: 0)
        hotkey.onCancel?()
        await waitUntil { appState.phase == .ready && audio.cancelCaptureCallCount == 1 }
        XCTAssertEqual(analytics.trackedEventNames.filter { $0 == "dictation_cancelled" }.count, 1)
        XCTAssertTrue(completedSources.isEmpty)

        // The release ends the recording first, so the late Esc cancels nothing.
        await press(at: 5_000)
        await release(at: 6_000)
        hotkey.onCancel?()
        await waitUntil { appState.phase == .ready && completedSources.count == 1 }
        await drain()
        XCTAssertEqual(analytics.trackedEventNames.filter { $0 == "dictation_cancelled" }.count, 1)
    }

    func testLaunchReportsWhetherDoubleTapIsAvailable() async {
        _ = await readyState(globeKeyAction: .startDictation)

        let launch = analytics.trackedEvents.first { $0.name == "app_launch" }
        XCTAssertEqual(launch?.props["setting_double_tap"], .label("globe_starts_dictation"))
    }

    func testSingleTapIsDroppedWithNoTextAndNoError() async {
        let appState = await readyState()

        await press(at: 0)
        await release(at: 120)
        await waitUntil { appState.phase == .ready && audio.cancelCaptureCallCount == 1 }

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
        await waitUntil { appState.phase == .ready && audio.cancelCaptureCallCount == 1 }

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

    func testGlobeDoubleTapDoesNotLockWhenATapAlsoRunsAMacOSAction() async {
        for action in [SystemGlobeKeyAction.startDictation, .showEmojiAndSymbols, .changeInputSource] {
            let appState = await readyState(globeKeyAction: action)
            XCTAssertEqual(appState.globeDoubleTapConflict, action)

            await doubleTap()
            await waitUntil { appState.phase == .ready }
            await waitPastSecondTapWindow()

            XCTAssertEqual(appState.phase, .ready, "\(action)")
            XCTAssertEqual(transcription.transcribeCallCount, 0, "\(action)")
            XCTAssertEqual(
                appState.floatingIndicatorState,
                .error(message: "Double-tap is off. See Settings."),
                "the pill says why the double-tap did nothing"
            )
        }
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
        await waitUntil { appState.phase == .ready }
        await press(at: 250)
        hotkey.onHotkeyChord?()
        await release(at: 380)
        await waitPastSecondTapWindow()

        XCTAssertEqual(appState.phase, .ready)
        XCTAssertEqual(transcription.transcribeCallCount, 0)
        XCTAssertNil(appState.lastError)
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
