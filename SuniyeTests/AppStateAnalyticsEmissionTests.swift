import XCTest
import SuniyeAnalytics
@testable import Suniye

@MainActor
final class AppStateAnalyticsEmissionTests: XCTestCase {
    private func readyAppState(
        spy: SpyAnalytics,
        audioCapture: StubAudioCaptureService,
        transcription: StubTranscriptionService = StubTranscriptionService()
    ) -> AppState {
        let appState = makeTestAppState(
            transcriptionService: transcription,
            audioCaptureService: audioCapture,
            analytics: spy
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        return appState
    }

    private func drain() async {
        for _ in 0 ..< 8 { await Task.yield() }
    }

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
        let appState = readyAppState(spy: spy, audioCapture: audio, transcription: transcription)

        appState.startRecordingFromUI()
        await fulfillment(of: [started], timeout: 1)
        appState.stopRecordingFromUI()
        await fulfillment(of: [transcribed], timeout: 1)
        await drain()

        let metrics = completedMetrics(spy)
        XCTAssertNotNil(metrics, "dictation_completed should be emitted")
        XCTAssertEqual(metrics?.wordCount, 3)
        XCTAssertGreaterThan(metrics?.charCount ?? 0, 0)
        XCTAssertFalse(metrics?.wasLLMPolished ?? true) // Magic Format off in tests
        XCTAssertFalse(metrics?.language.value.isEmpty ?? true) // model-derived coverage, not empty
        XCTAssertEqual(metrics?.insertionMethod, .clipboard) // always clipboard paste
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
        let appState = readyAppState(spy: spy, audioCapture: audio)

        appState.startRecordingFromUI()
        await fulfillment(of: [started], timeout: 1)
        appState.stopRecordingFromUI()
        await fulfillment(of: [stopped], timeout: 1)
        await drain()

        XCTAssertTrue(spy.trackedEventNames.contains("audio_capture_failed"))
    }

    func testAudioInterruptionEmitted() async throws {
        let spy = SpyAnalytics()
        let audio = StubAudioCaptureService()
        let started = expectation(description: "started")
        let canceled = expectation(description: "canceled")
        audio.onStartCapture = { _ in started.fulfill() }
        audio.onCancelCapture = { _ in canceled.fulfill() }
        let appState = readyAppState(spy: spy, audioCapture: audio)

        appState.startRecordingFromUI()
        await fulfillment(of: [started], timeout: 1)
        let sessionID = try XCTUnwrap(audio.lastStartedSessionID)
        audio.onEvent?(.interrupted(sessionID: sessionID, reason: .inputMuted))
        await fulfillment(of: [canceled], timeout: 1)
        await drain()

        XCTAssertTrue(spy.trackedEventNames.contains("audio_capture_interrupted"))
    }
}
