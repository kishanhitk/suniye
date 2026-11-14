import XCTest
import SuniyeAnalytics
@testable import Suniye

@MainActor
final class AppStateAnalyticsEmissionTests: XCTestCase {
    private func completedMetrics(_ spy: SpyAnalytics) -> DictationMetrics? {
        spy.trackedEvents.compactMap { event -> DictationMetrics? in
            if case let .dictationCompleted(metrics) = event { return metrics }
            return nil
        }.last
    }

    func testDictationCompletedEmittedWithMetrics() async {
        let spy = SpyAnalytics()
        let audio = StubAudioCaptureService()
        audio.stopCaptureResult = makeValidCapturedAudio()
        let transcription = StubTranscriptionService()
        transcription.transcribeResult = .success("hello there friend")
        let started = expectation(description: "started")
        let transcribed = expectation(description: "transcribed")
        audio.onStartCapture = { _ in started.fulfill() }
        transcription.onTranscribe = { transcribed.fulfill() }
        let appState = makeReadyTestAppState(transcriptionService: transcription, audioCaptureService: audio, analytics: spy)

        appState.toggleFloatingIndicatorRecording()
        await fulfillment(of: [started], timeout: 1)
        appState.toggleFloatingIndicatorRecording()
        await fulfillment(of: [transcribed], timeout: 1)
        await drainScheduledTasks()

        let metrics = completedMetrics(spy)
        XCTAssertNotNil(metrics, "dictation_completed should be emitted")
        XCTAssertEqual(metrics?.wordCount, 3)
        XCTAssertGreaterThan(metrics?.charCount ?? 0, 0)
        XCTAssertFalse(metrics?.wasLLMPolished ?? true) // Magic Format off in tests
        XCTAssertFalse(metrics?.language.value.isEmpty ?? true) // model-derived coverage, not empty
        XCTAssertEqual(metrics?.insertionMethod, .clipboard) // always clipboard paste
    }

    func testEmptyDictationSaysWhetherSpeechWasDetected() async {
        let results: [(Result<String, Error>, DictationEmptyReason)] = [
            (.failure(NoSpeechDetected()), .noSpeech),
            (.success("  "), .emptyTranscript),
        ]
        for (result, expectedReason) in results {
            let spy = SpyAnalytics()
            let audio = StubAudioCaptureService()
            audio.stopCaptureResult = makeValidCapturedAudio()
            let transcription = StubTranscriptionService()
            transcription.transcribeResult = result
            let started = expectation(description: "started")
            let transcribed = expectation(description: "transcribed")
            audio.onStartCapture = { _ in started.fulfill() }
            transcription.onTranscribe = { transcribed.fulfill() }
            let appState = makeReadyTestAppState(transcriptionService: transcription, audioCaptureService: audio, analytics: spy)

            appState.toggleFloatingIndicatorRecording()
            await fulfillment(of: [started], timeout: 1)
            appState.toggleFloatingIndicatorRecording()
            await fulfillment(of: [transcribed], timeout: 1)
            await drainScheduledTasks()

            let reasons = spy.trackedEvents.compactMap { event -> DictationEmptyReason? in
                if case let .dictationEmpty(reason) = event { return reason }
                return nil
            }
            XCTAssertEqual(reasons, [expectedReason])
            XCTAssertFalse(spy.trackedEventNames.contains("error"), "no speech is not a transcription failure")
            XCTAssertEqual(appState.phase, .ready)
        }
    }

    func testAudioCaptureFailureEmitted() async {
        let spy = SpyAnalytics()
        let audio = StubAudioCaptureService()
        // Silent/short audio → capture outcome is a failure, not .complete.
        audio.stopCaptureResult = CapturedAudio(samples: Array(repeating: 0, count: 1_600), sampleRate: 16_000)
        let started = expectation(description: "started")
        let stopped = expectation(description: "stopped")
        audio.onStartCapture = { _ in started.fulfill() }
        audio.onStopCapture = { _ in stopped.fulfill() }
        let appState = makeReadyTestAppState(audioCaptureService: audio, analytics: spy)

        appState.toggleFloatingIndicatorRecording()
        await fulfillment(of: [started], timeout: 1)
        appState.toggleFloatingIndicatorRecording()
        await fulfillment(of: [stopped], timeout: 1)
        await drainScheduledTasks()

        XCTAssertTrue(spy.trackedEventNames.contains("audio_capture_failed"))
    }

    func testAudioInterruptionEmitted() async throws {
        let spy = SpyAnalytics()
        let audio = StubAudioCaptureService()
        let started = expectation(description: "started")
        let canceled = expectation(description: "canceled")
        audio.onStartCapture = { _ in started.fulfill() }
        audio.onCancelCapture = { _ in canceled.fulfill() }
        let appState = makeReadyTestAppState(audioCaptureService: audio, analytics: spy)

        appState.toggleFloatingIndicatorRecording()
        await fulfillment(of: [started], timeout: 1)
        let sessionID = try XCTUnwrap(audio.lastStartedSessionID)
        audio.onEvent?(.interrupted(sessionID: sessionID, reason: .inputMuted))
        await fulfillment(of: [canceled], timeout: 1)
        await drainScheduledTasks()

        XCTAssertTrue(spy.trackedEventNames.contains("audio_capture_interrupted"))
    }
}
