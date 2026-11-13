import AppKit
import SuniyeAnalytics
import XCTest
@testable import Suniye

@MainActor
final class AppStateDictationTests: XCTestCase {
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

    func testDictationWithoutAccessibilityPromptsOnceAndSaysItWasNotPasted() async {
        // After a signing-identity change the grant goes stale with the app in
        // the background: the hotkey is the only moment the user can be told.
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = makeValidCapturedAudio()
        let transcriptionService = StubTranscriptionService()
        transcriptionService.transcribeResult = .success("Hello without access")
        let textInsertionService = SpyTextInsertionService()
        let sound = SpySoundFeedbackService()
        var promptCount = 0
        let appState = makeTestAppState(
            transcriptionService: transcriptionService,
            audioCaptureService: audioCapture,
            textInsertionService: textInsertionService,
            soundFeedbackService: sound,
            micAuthorizationStatusProvider: { .authorized },
            accessibilityTrustProvider: { false },
            accessibilityTrustPrompter: {
                promptCount += 1
                return false
            }
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = false
        appState.soundFeedbackEnabled = true

        for _ in 0..<2 {
            appState.toggleFloatingIndicatorRecording()
            try? await Task.sleep(nanoseconds: 50_000_000)
            appState.toggleFloatingIndicatorRecording()
            try? await Task.sleep(nanoseconds: 50_000_000)

            XCTAssertEqual(appState.floatingIndicatorState, .error(message: appState.clipboardOnlyNoticeMessage))
        }

        XCTAssertEqual(promptCount, 1, "the system dialog is raised once per launch, not on every dictation")
        XCTAssertEqual(textInsertionService.copiedTexts, ["Hello without access", "Hello without access"])
        XCTAssertTrue(textInsertionService.insertedTexts.isEmpty)
        XCTAssertEqual(sound.playedEvents, [.error, .error])
        XCTAssertTrue(appState.clipboardOnlyNoticeMessage.contains("Not pasted: Accessibility is off."))
    }

    func testDictationWithAccessibilityNeitherPromptsNorWarns() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = makeValidCapturedAudio()
        let transcriptionService = StubTranscriptionService()
        transcriptionService.transcribeResult = .success("Hello with access")
        let textInsertionService = SpyTextInsertionService()
        let sound = SpySoundFeedbackService()
        var promptCount = 0
        let appState = makeTestAppState(
            transcriptionService: transcriptionService,
            audioCaptureService: audioCapture,
            textInsertionService: textInsertionService,
            soundFeedbackService: sound,
            micAuthorizationStatusProvider: { .authorized },
            accessibilityTrustProvider: { true },
            accessibilityTrustPrompter: {
                promptCount += 1
                return true
            }
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        appState.soundFeedbackEnabled = true

        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)
        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(promptCount, 0)
        XCTAssertFalse(textInsertionService.insertedTexts.isEmpty)
        XCTAssertEqual(sound.playedEvents, [.transcriptionSucceeded])
        XCTAssertEqual(appState.floatingIndicatorState, .idle)
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
        let didPaste = await appState.pasteLastTranscript()
        XCTAssertTrue(didPaste)
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
}
