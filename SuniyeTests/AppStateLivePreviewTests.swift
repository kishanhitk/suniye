import XCTest
@testable import Suniye

@MainActor
final class AppStateLivePreviewTests: XCTestCase {
    func testPartialTranscriptsPublishInOrderWhileRecording() async throws {
        // A huge interval keeps the loop quiet so ticks are driven deterministically.
        let scheduler = PartialTranscriptionScheduler(tickInterval: 3_600)
        let audioCapture = StubAudioCaptureService()
        let transcription = StubTranscriptionService()
        transcription.scriptedTranscribeResults = [.success("hello"), .success("hello world")]
        let started = expectation(description: "capture started")
        audioCapture.onStartCapture = { _ in started.fulfill() }
        let appState = readyAppState(
            audioCapture: audioCapture,
            transcription: transcription,
            scheduler: scheduler
        )

        appState.startRecordingFromUI()
        await fulfillment(of: [started], timeout: 1)
        await drainScheduledTasks()
        XCTAssertTrue(scheduler.isActive)

        await scheduler.tickNow()
        XCTAssertEqual(appState.livePartialTranscript, "hello")

        await scheduler.tickNow()
        XCTAssertEqual(appState.livePartialTranscript, "hello world")
        XCTAssertEqual(audioCapture.lastSnapshotMaxDurationSeconds, PartialTranscriptionScheduler.maxWindowSeconds)
        XCTAssertEqual(transcription.transcribePurposes, [.partial, .partial])
        XCTAssertEqual(
            appState.floatingIndicatorState,
            .listening(
                levels: Array(repeating: 0, count: AudioLevelMeter.bandCount),
                source: .manual,
                preview: "hello world"
            )
        )
    }

    func testPartialsAreStabilizedAgainstPreviouslyShownText() async throws {
        let scheduler = PartialTranscriptionScheduler(tickInterval: 3_600)
        let audioCapture = StubAudioCaptureService()
        let transcription = StubTranscriptionService()
        // The re-decode rewrites casing/punctuation of already-shown words; the
        // shown prefix must stay put and only the tail may extend.
        transcription.scriptedTranscribeResults = [
            .success("Okay, so we"),
            .success("okay so we begin now")
        ]
        let started = expectation(description: "capture started")
        audioCapture.onStartCapture = { _ in started.fulfill() }
        let appState = readyAppState(
            audioCapture: audioCapture,
            transcription: transcription,
            scheduler: scheduler
        )

        appState.startRecordingFromUI()
        await fulfillment(of: [started], timeout: 1)
        await drainScheduledTasks()

        await scheduler.tickNow()
        XCTAssertEqual(appState.livePartialTranscript, "Okay, so we")

        await scheduler.tickNow()
        XCTAssertEqual(appState.livePartialTranscript, "Okay, so we begin now")
    }

    func testStabilizerAnchorResetsBetweenSessions() async throws {
        let scheduler = PartialTranscriptionScheduler(tickInterval: 3_600)
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = makeValidCapturedAudio()
        let transcription = StubTranscriptionService()
        transcription.scriptedTranscribeResults = [
            .success("Alpha, beta"), // session 1 partial
            .success("done"), // session 1 final
            .success("alpha beta gamma") // session 2 partial
        ]
        var captureStarted = expectation(description: "capture 1 started")
        audioCapture.onStartCapture = { _ in captureStarted.fulfill() }
        let appState = readyAppState(
            audioCapture: audioCapture,
            transcription: transcription,
            scheduler: scheduler
        )

        appState.startRecordingFromUI()
        await fulfillment(of: [captureStarted], timeout: 1)
        await drainScheduledTasks()
        await scheduler.tickNow()
        XCTAssertEqual(appState.livePartialTranscript, "Alpha, beta")

        appState.stopRecordingFromUI()
        try await waitUntil { appState.phase == .ready }

        captureStarted = expectation(description: "capture 2 started")
        appState.startRecordingFromUI()
        await fulfillment(of: [captureStarted], timeout: 1)
        await drainScheduledTasks()
        await scheduler.tickNow()

        // A stale anchor would resurrect session 1's "Alpha, beta" forms.
        XCTAssertEqual(appState.livePartialTranscript, "alpha beta gamma")
    }

    func testAudioLevelUpdateKeepsPartialPreview() async throws {
        let scheduler = PartialTranscriptionScheduler(tickInterval: 3_600)
        let audioCapture = StubAudioCaptureService()
        let transcription = StubTranscriptionService()
        transcription.transcribeResult = .success("partial words")
        let started = expectation(description: "capture started")
        audioCapture.onStartCapture = { _ in started.fulfill() }
        let appState = readyAppState(
            audioCapture: audioCapture,
            transcription: transcription,
            scheduler: scheduler
        )

        appState.startRecordingFromUI()
        await fulfillment(of: [started], timeout: 1)
        await drainScheduledTasks()
        await scheduler.tickNow()
        XCTAssertEqual(appState.livePartialTranscript, "partial words")

        let sessionID = try XCTUnwrap(audioCapture.lastStartedSessionID)
        let levels = Array(repeating: Float(0.42), count: AudioLevelMeter.bandCount)
        audioCapture.onEvent?(.levelsUpdated(sessionID: sessionID, levels: levels))
        await drainScheduledTasks()

        XCTAssertEqual(
            appState.floatingIndicatorState,
            .listening(levels: levels, source: .manual, preview: "partial words")
        )
    }

    func testWhisperModelFamilyDisablesLivePreview() async throws {
        let scheduler = PartialTranscriptionScheduler(tickInterval: 3_600)
        let audioCapture = StubAudioCaptureService()
        let transcription = StubTranscriptionService()
        let started = expectation(description: "capture started")
        audioCapture.onStartCapture = { _ in started.fulfill() }
        let appState = readyAppState(
            audioCapture: audioCapture,
            transcription: transcription,
            scheduler: scheduler
        )
        appState.loadedASRModelID = .whisperLargeV3

        appState.startRecordingFromUI()
        await fulfillment(of: [started], timeout: 1)
        await drainScheduledTasks()

        XCTAssertFalse(scheduler.isActive)
        await scheduler.tickNow()
        XCTAssertEqual(transcription.transcribeCallCount, 0)
        XCTAssertEqual(audioCapture.snapshotCallCount, 0)
        XCTAssertNil(appState.livePartialTranscript)
    }

    func testLatePartialAfterStopDoesNotClobberFinalTranscript() async throws {
        let scheduler = PartialTranscriptionScheduler(tickInterval: 3_600)
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = makeValidCapturedAudio()
        let transcription = StubTranscriptionService()
        transcription.scriptedTranscribeResults = [.success("stale partial"), .success("final text")]
        let gate = AsyncGate()
        let partialDecodeStarted = expectation(description: "partial decode started")
        transcription.onTranscribeAwait = { callNumber in
            guard callNumber == 1 else { return }
            partialDecodeStarted.fulfill()
            await gate.wait()
        }
        let textInsertion = SpyTextInsertionService()
        let started = expectation(description: "capture started")
        audioCapture.onStartCapture = { _ in started.fulfill() }
        let appState = readyAppState(
            audioCapture: audioCapture,
            transcription: transcription,
            textInsertion: textInsertion,
            scheduler: scheduler
        )

        appState.startRecordingFromUI()
        await fulfillment(of: [started], timeout: 1)
        await drainScheduledTasks()

        // A partial decode is in flight when the user stops.
        let blockedTick = Task { await scheduler.tickNow() }
        await fulfillment(of: [partialDecodeStarted], timeout: 1)

        appState.stopRecordingFromUI()
        try await waitUntil { appState.phase == .ready }
        XCTAssertEqual(textInsertion.insertedTexts.count, 1)
        XCTAssertTrue(try XCTUnwrap(textInsertion.insertedTexts.first).contains("final text"))

        // The stale partial finishes only now; it must be dropped entirely.
        gate.open()
        await blockedTick.value
        await drainScheduledTasks()

        XCTAssertNil(appState.livePartialTranscript)
        XCTAssertEqual(appState.floatingIndicatorState, .idle)
        XCTAssertEqual(textInsertion.insertedTexts.count, 1)
        XCTAssertEqual(transcription.transcribePurposes, [.partial, .final])
        XCTAssertFalse(scheduler.isActive)
    }

    func testPreviewDisabledLeavesFinalTranscriptionPathUnchanged() async throws {
        let scheduler = PartialTranscriptionScheduler(tickInterval: 3_600)
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = makeValidCapturedAudio()
        let transcription = StubTranscriptionService()
        transcription.transcribeResult = .success("final text")
        let textInsertion = SpyTextInsertionService()
        let started = expectation(description: "capture started")
        audioCapture.onStartCapture = { _ in started.fulfill() }
        let appState = readyAppState(
            audioCapture: audioCapture,
            transcription: transcription,
            textInsertion: textInsertion,
            scheduler: scheduler
        )
        appState.liveTranscriptionPreviewEnabled = false

        appState.startRecordingFromUI()
        await fulfillment(of: [started], timeout: 1)
        await drainScheduledTasks()
        XCTAssertFalse(scheduler.isActive)
        await scheduler.tickNow()
        XCTAssertEqual(transcription.transcribeCallCount, 0)
        XCTAssertNil(appState.livePartialTranscript)

        appState.stopRecordingFromUI()
        try await waitUntil { appState.phase == .ready }

        XCTAssertEqual(transcription.transcribeCallCount, 1)
        XCTAssertEqual(transcription.transcribePurposes, [.final])
        XCTAssertEqual(audioCapture.snapshotCallCount, 0)
        XCTAssertEqual(textInsertion.insertedTexts.count, 1)
        XCTAssertTrue(try XCTUnwrap(textInsertion.insertedTexts.first).contains("final text"))
    }

    func testCaptureInterruptionClearsPartialTranscript() async throws {
        let scheduler = PartialTranscriptionScheduler(tickInterval: 3_600)
        let audioCapture = StubAudioCaptureService()
        let transcription = StubTranscriptionService()
        transcription.transcribeResult = .success("partial words")
        let started = expectation(description: "capture started")
        audioCapture.onStartCapture = { _ in started.fulfill() }
        let appState = readyAppState(
            audioCapture: audioCapture,
            transcription: transcription,
            scheduler: scheduler
        )

        appState.startRecordingFromUI()
        await fulfillment(of: [started], timeout: 1)
        await drainScheduledTasks()
        await scheduler.tickNow()
        XCTAssertEqual(appState.livePartialTranscript, "partial words")

        let sessionID = try XCTUnwrap(audioCapture.lastStartedSessionID)
        audioCapture.onEvent?(.interrupted(sessionID: sessionID, reason: .inputMuted))
        try await waitUntil { appState.phase == .ready }

        XCTAssertNil(appState.livePartialTranscript)
        XCTAssertFalse(scheduler.isActive)
    }

    func testTogglingPreviewOffMidRecordingStopsPartialsImmediately() async throws {
        let scheduler = PartialTranscriptionScheduler(tickInterval: 3_600)
        let audioCapture = StubAudioCaptureService()
        let transcription = StubTranscriptionService()
        transcription.transcribeResult = .success("partial words")
        let started = expectation(description: "capture started")
        audioCapture.onStartCapture = { _ in started.fulfill() }
        let appState = readyAppState(
            audioCapture: audioCapture,
            transcription: transcription,
            scheduler: scheduler
        )

        appState.startRecordingFromUI()
        await fulfillment(of: [started], timeout: 1)
        await drainScheduledTasks()
        await scheduler.tickNow()
        XCTAssertEqual(appState.livePartialTranscript, "partial words")

        appState.liveTranscriptionPreviewEnabled = false

        XCTAssertFalse(scheduler.isActive)
        XCTAssertNil(appState.livePartialTranscript)
        XCTAssertEqual(
            appState.floatingIndicatorState,
            .listening(
                levels: Array(repeating: 0, count: AudioLevelMeter.bandCount),
                source: .manual,
                preview: nil
            )
        )
        let decodeCountAfterToggle = transcription.transcribeCallCount
        await scheduler.tickNow()
        XCTAssertEqual(transcription.transcribeCallCount, decodeCountAfterToggle)
    }

    func testLiveTranscriptionPreviewSettingPersistsAndDefaultsOn() {
        let settingsStore = TestGeneralSettingsStore()
        let appState = makeTestAppState(generalSettingsStore: settingsStore)

        XCTAssertTrue(appState.liveTranscriptionPreviewEnabled)

        appState.liveTranscriptionPreviewEnabled = false
        XCTAssertFalse(settingsStore.latest.liveTranscriptionPreviewEnabled)

        appState.liveTranscriptionPreviewEnabled = true
        XCTAssertTrue(settingsStore.latest.liveTranscriptionPreviewEnabled)
    }

    private func readyAppState(
        audioCapture: StubAudioCaptureService,
        transcription: StubTranscriptionService,
        textInsertion: SpyTextInsertionService = SpyTextInsertionService(),
        scheduler: PartialTranscriptionScheduler
    ) -> AppState {
        let appState = makeTestAppState(
            transcriptionService: transcription,
            audioCaptureService: audioCapture,
            textInsertionService: textInsertion,
            partialTranscriptionScheduler: scheduler
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        return appState
    }

    private func drainScheduledTasks() async {
        for _ in 0 ..< 8 {
            await Task.yield()
        }
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                throw FakeError(message: "condition not met within \(timeout)s")
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
