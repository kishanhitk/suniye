import SuniyeAnalytics
import XCTest
@testable import Suniye

private let rate = MeetingAudioFormat.sampleRate

private func tone(_ seconds: Double, level: Float) -> [Float] {
    (0 ..< Int(seconds * Double(rate))).map { level * Float(sin(2 * Double.pi * 220 * Double($0) / Double(rate))) }
}

private func silence(_ seconds: Double) -> [Float] {
    Array(repeating: 0, count: Int(seconds * Double(rate)))
}

/// One sentence of 30 words: enough speech for a summary.
private let longSentence = (1 ... 30).map { "word\($0)" }.joined(separator: " ") + "."

@MainActor
final class MeetingCoordinatorTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var store: MeetingStore!
    private var you: PushSource!
    private var them: PushSource!
    private var host: FakeHost!
    private var engine: WordEngine!
    private var transcriptEngine: WordEngine!
    private var requestedTranscriptModels: [ASRModelID] = []
    /// The transcript engine's unload count at each load.
    private var unloadsAtEachLoad: [Int] = []
    private var transcriptEngineError: Error?
    private var summaryModel: GatedSummaryModel!
    private var clock: Date!
    private var freeBytes: Int64 = 10_000_000_000
    private var microphone: FakeMicrophoneUsers!
    private var analytics: SpyAnalytics!
    private var uptime: TimeInterval = 1000
    private var cardDurations = MeetingCallCard.Durations()
    private var summaryAvailability = MeetingSummaryAvailability.ready(.localModel)

    override func setUp() async throws {
        try await super.setUp()
        root = FileManager.default.temporaryDirectory.appendingPathComponent("MeetingCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
        suiteName = "MeetingCoordinatorTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = MeetingStore(rootDirectory: root.appendingPathComponent("meetings", isDirectory: true))
        you = PushSource()
        them = PushSource()
        host = FakeHost()
        engine = WordEngine(words: [0.3: longSentence, 0.5: "Them speaks here."])
        transcriptEngine = WordEngine(words: [0.3: longSentence, 0.5: "Them speaks here."])
        summaryModel = GatedSummaryModel()
        clock = Date(timeIntervalSince1970: 1_800_000_000)
        microphone = FakeMicrophoneUsers()
        analytics = SpyAnalytics()
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
        try await super.tearDown()
    }

    private func makeCoordinator(speechlessLimit: TimeInterval = 15 * 60) -> MeetingCoordinator {
        let environment = MeetingEnvironment(
            canRecordCallAudio: true,
            makeSources: { [unowned self] _ in [.you: you, .them: them] },
            freeDiskBytes: { [unowned self] in freeBytes },
            callPlaysOnSpeakers: { false },
            makeMicrophoneUsers: { [unowned self] in microphone },
            now: { [unowned self] in clock },
            uptime: { [unowned self] in uptime },
            liveCheckInterval: .milliseconds(20),
            speechlessLimit: speechlessLimit,
            makeSpeechDetector: { LoudSpeechDetector() },
            callCardDurations: cardDurations
        )
        let coordinator = MeetingCoordinator(
            store: store,
            templates: MeetingTemplateStore(fileURL: root.appendingPathComponent("templates.json")),
            settingsStore: MeetingSettingsStore(userDefaults: defaults),
            engine: engine,
            makeTranscriptEngine: { [unowned self] model in
                requestedTranscriptModels.append(model)
                unloadsAtEachLoad.append(await transcriptEngine.unloads)
                if let transcriptEngineError {
                    throw transcriptEngineError
                }
                return transcriptEngine
            },
            environment: environment,
            summaryAvailability: { [unowned self] in summaryAvailability },
            makeSummaryModel: { [unowned self] _ in summaryModel },
            analytics: analytics
        )
        coordinator.host = host
        return coordinator
    }

    func testAMeetingEndsWithItsSummary() async throws {
        let coordinator = makeCoordinator()
        coordinator.speechModelChanged(.parakeetV3)

        try await coordinator.startMeeting(source: .manual)
        let id = try XCTUnwrap(coordinator.live?.id)
        you.push(tone(2.5, level: 0.3) + silence(0.5))
        await coordinator.stop()
        let finished = await waitUntil { coordinator.record(id)?.status == .done }

        XCTAssertTrue(finished)
        XCTAssertEqual(coordinator.record(id)?.title, "Release plan")
        let summary = await store.summary(of: id)
        let audioLeft = !store.audioTracks(of: id).isEmpty
        let segments = await store.segments(of: id)
        XCTAssertEqual(summary, "## Overview\nThe team agreed to ship on Friday.\n\n## Decisions\n- Ship on Friday")
        XCTAssertFalse(audioLeft, "the audio goes once the transcript is final")
        XCTAssertEqual(segments.map(\.text), [longSentence])
        XCTAssertGreaterThanOrEqual(host.idleCount, 1, "Magic Format can warm its prompt after the summary")
        XCTAssertEqual(
            analytics.trackedEvents.map(\.name),
            ["meeting_started", "meeting_ended", "meeting_transcribed", "meeting_summarized"]
        )
        XCTAssertEqual(event("meeting_ended")?["tracks"], .label("you_them"))
        XCTAssertEqual(event("meeting_transcribed")?["outcome"], .label("done"))
        XCTAssertEqual(event("meeting_transcribed")?["segments"], .int(1))
        XCTAssertEqual(event("meeting_summarized")?["parts"], .int(1))
        XCTAssertEqual(event("meeting_summarized")?["provider"], .label("local_model"))
    }

    func testTooLittleSpaceStartsNothing() async throws {
        let coordinator = makeCoordinator()
        freeBytes = 100_000_000

        do {
            try await coordinator.startMeeting(source: .manual)
            XCTFail("expected a refusal")
        } catch {
            XCTAssertEqual(error as? MeetingStartError, .notEnoughSpace)
        }

        XCTAssertNil(coordinator.live)
        let saved = await store.loadAll()
        XCTAssertTrue(saved.isEmpty)
        XCTAssertEqual(you.startCount, 0)
    }

    func testADictationSilencesTheMicrophoneTrackAndTheTranscriptWaitsForIt() async throws {
        let coordinator = makeCoordinator()
        coordinator.speechModelChanged(.parakeetV3)
        try await coordinator.startMeeting(source: .manual)
        let id = try XCTUnwrap(coordinator.live?.id)

        coordinator.dictationChanged(active: true)
        you.push(tone(2.5, level: 0.3) + silence(0.5))
        them.push(tone(2.5, level: 0.5) + silence(0.5))
        coordinator.dictationCaptureEnded()
        you.push(tone(2.5, level: 0.3) + silence(0.5))
        let stopping = Task { await coordinator.stop() }
        let progressShown = await waitUntil { coordinator.transcriptProgress[id] != nil }
        try await Task.sleep(for: .milliseconds(200))
        let decodesDuringDictation = await engine.calls
        coordinator.dictationChanged(active: false)
        await stopping.value
        let segments = await store.segments(of: id)

        XCTAssertTrue(progressShown, "the page shows the progress while the transcript waits")
        XCTAssertEqual(decodesDuringDictation, 0)
        XCTAssertEqual(segments.map(\.track), [.them, .you], "the dictated words are not meeting talk; talk after the capture ends is")
        XCTAssertNil(coordinator.transcriptProgress[id])
    }

    func testAnotherTranscriptModelGetsAnEngineOfItsOwnThatAlsoWaitsForADictation() async throws {
        let coordinator = makeCoordinator()
        coordinator.speechModelChanged(.parakeetV3)
        coordinator.updateSettings { $0.transcriptModel = .cohereTranscribe }
        try await coordinator.startMeeting(source: .manual)
        let id = try XCTUnwrap(coordinator.live?.id)
        you.push(tone(2.5, level: 0.3) + silence(0.5))

        coordinator.dictationChanged(active: true)
        let stopping = Task { await coordinator.stop() }
        let started = await waitUntil { coordinator.transcriptProgress[id] != nil }
        try await Task.sleep(for: .milliseconds(200))
        let decodesDuringTheDictation = await transcriptEngine.calls
        coordinator.dictationChanged(active: false)
        await stopping.value
        let segments = await store.segments(of: id)
        let dictationEngineDecodes = await engine.calls
        let unloads = await transcriptEngine.unloads

        XCTAssertTrue(started)
        XCTAssertEqual(requestedTranscriptModels, [.cohereTranscribe])
        XCTAssertEqual(decodesDuringTheDictation, 0, "no piece starts while a dictation runs")
        XCTAssertEqual(segments.map(\.text), [longSentence])
        XCTAssertEqual(dictationEngineDecodes, 0, "the dictation model stays with dictation")
        XCTAssertEqual(unloads, 1, "the transcript model is unloaded after the pass")
        XCTAssertEqual(event("meeting_transcribed")?["asr_model"], .label("coheretranscribe"))
    }

    func testAChosenModelThatIsAlsoTheDictationModelStillGetsAnEngineOfItsOwn() async throws {
        let coordinator = makeCoordinator()
        coordinator.speechModelChanged(.parakeetV3)
        coordinator.updateSettings { $0.transcriptModel = .parakeetV3 }
        try await coordinator.startMeeting(source: .manual)
        you.push(tone(2.5, level: 0.3) + silence(0.5))

        await coordinator.stop()
        let dictationEngineDecodes = await engine.calls

        XCTAssertEqual(requestedTranscriptModels, [.parakeetV3], "a switch of the dictation model cannot change a chosen model")
        XCTAssertEqual(dictationEngineDecodes, 0)
    }

    func testATranscriptModelThatIsNotDownloadedStopsTheTranscriptWithThatCauseAndKeepsTheAudio() async throws {
        transcriptEngineError = MeetingTranscriptModelError.notDownloaded("Cohere Transcribe")
        let coordinator = makeCoordinator()
        coordinator.speechModelChanged(.parakeetV3)
        coordinator.updateSettings { $0.transcriptModel = .cohereTranscribe }
        try await coordinator.startMeeting(source: .manual)
        let id = try XCTUnwrap(coordinator.live?.id)
        you.push(tone(2.5, level: 0.3) + silence(0.5))

        await coordinator.stop()

        XCTAssertEqual(coordinator.record(id)?.status, .interrupted)
        XCTAssertEqual(
            coordinator.record(id)?.transcriptFailure,
            "Cohere Transcribe is not downloaded. Download it in Settings, or choose another transcript model."
        )
        XCTAssertEqual(store.audioTracks(of: id), [.you, .them], "Finish Transcript can use the audio later")
    }

    func testPausesAreKeptInTheRecordAndLeftOutOfTheTimer() async throws {
        let coordinator = makeCoordinator()
        try await coordinator.startMeeting(source: .manual)
        let session = try XCTUnwrap(coordinator.live)

        clock += 10
        await coordinator.pause()
        let paused = session.record
        clock += 5
        try await coordinator.resume()
        clock += 1

        XCTAssertEqual(paused.status, .paused)
        XCTAssertEqual(session.record.pauses, [MeetingPause(start: 10, end: 15)])
        XCTAssertEqual(session.record.status, .recording)
        XCTAssertEqual(session.elapsed(at: clock), 11)
        XCTAssertEqual(you.stopCount, 1)
        XCTAssertEqual(you.startCount, 2)
        await coordinator.stop()
    }

    func testTwoPausesAtOnceOpenOnePause() async throws {
        let coordinator = makeCoordinator()
        try await coordinator.startMeeting(source: .manual)
        let session = try XCTUnwrap(coordinator.live)

        clock += 10
        async let first: Void = coordinator.pause()
        async let second: Void = coordinator.pause()
        _ = await (first, second)
        clock += 5
        try await coordinator.resume()

        XCTAssertEqual(session.record.pauses, [MeetingPause(start: 10, end: 15)])
        await coordinator.stop()
    }

    func testAtLaunchARecordingThatAQuitLeftWaitsForFinishTranscript() async throws {
        let left = try await leftRecording(startedAt: clock)
        let coordinator = makeCoordinator()
        coordinator.speechModelChanged(.parakeetV3)

        await coordinator.start()
        try await Task.sleep(for: .milliseconds(100))
        let atLaunch = coordinator.record(left)?.status
        let decodesAtLaunch = await engine.calls
        coordinator.finishTranscript(left)
        let finished = await waitUntil { coordinator.record(left)?.status == .done }

        XCTAssertEqual(atLaunch, .notTranscribed)
        XCTAssertEqual(decodesAtLaunch, 0, "a launch loads no speech model and decodes nothing with no click")
        XCTAssertTrue(finished)
        let segments = await store.segments(of: left)
        XCTAssertEqual(segments.map(\.text), [longSentence])
    }

    func testTranscriptsRunOneAtATime() async throws {
        let first = try await leftRecording(startedAt: clock - 600)
        let second = try await leftRecording(startedAt: clock - 300)
        let coordinator = makeCoordinator()
        coordinator.updateSettings { $0.transcriptModel = .cohereTranscribe }
        await coordinator.start()

        coordinator.finishTranscript(first)
        coordinator.finishTranscript(second)
        let finished = await waitUntil {
            coordinator.record(first)?.status == .done && coordinator.record(second)?.status == .done
        }

        XCTAssertTrue(finished)
        XCTAssertEqual(requestedTranscriptModels, [.cohereTranscribe, .cohereTranscribe])
        XCTAssertEqual(unloadsAtEachLoad, [0, 1], "the second engine loads after the first one is unloaded")
    }

    func testARenameWhileTheSummaryRunsIsKept() async throws {
        await summaryModel.close()
        let coordinator = makeCoordinator()
        coordinator.speechModelChanged(.parakeetV3)
        try await coordinator.startMeeting(source: .manual)
        let id = try XCTUnwrap(coordinator.live?.id)
        you.push(tone(2.5, level: 0.3) + silence(0.5))
        await coordinator.stop()
        let summaryStarted = await waitUntil { await self.summaryModel.waiting }

        await coordinator.rename(id, to: "Hiring sync")
        await summaryModel.open()
        let finished = await waitUntil { coordinator.record(id)?.status == .done }

        XCTAssertTrue(summaryStarted)
        XCTAssertTrue(finished)
        XCTAssertEqual(coordinator.record(id)?.title, "Hiring sync")
        XCTAssertEqual(coordinator.record(id)?.titleSource, .user)
    }

    func testADictationStopsTheSummaryAndItRunsAgainAfterwards() async throws {
        await summaryModel.close()
        let coordinator = makeCoordinator()
        coordinator.speechModelChanged(.parakeetV3)
        try await coordinator.startMeeting(source: .manual)
        let id = try XCTUnwrap(coordinator.live?.id)
        you.push(tone(2.5, level: 0.3) + silence(0.5))
        await coordinator.stop()
        _ = await waitUntil { await self.summaryModel.waiting }

        coordinator.dictationChanged(active: true)
        let stopped = await waitUntil { await !self.summaryModel.waiting }
        await summaryModel.open()
        coordinator.dictationChanged(active: false)
        let finished = await waitUntil { coordinator.record(id)?.status == .done }

        XCTAssertTrue(stopped)
        XCTAssertTrue(finished)
        let kinds = await summaryModel.kinds
        XCTAssertEqual(kinds, [.part(number: 1, count: 1), .part(number: 1, count: 1), .overview], "the stopped request runs again")
    }

    func testRegenerateWithAnotherTemplateRemembersItAndWritesTheSummaryAgain() async throws {
        let coordinator = makeCoordinator()
        coordinator.speechModelChanged(.parakeetV3)
        try await coordinator.startMeeting(source: .manual)
        let id = try XCTUnwrap(coordinator.live?.id)
        you.push(tone(2.5, level: 0.3) + silence(0.5))
        await coordinator.stop()
        _ = await waitUntil { coordinator.record(id)?.status == .done }

        await coordinator.regenerate(id, templateID: MeetingTemplate.standUp.id)
        let rewritten = await waitUntil { await self.summaryModel.kinds.count == 4 }
        let done = await waitUntil { coordinator.record(id)?.status == .done }

        XCTAssertTrue(rewritten)
        XCTAssertTrue(done)
        let kinds = await summaryModel.kinds
        XCTAssertEqual(kinds, [.part(number: 1, count: 1), .overview, .part(number: 1, count: 1), .overview])
        let summary = await coordinator.summary(of: id)
        XCTAssertEqual(summary, "## Done\n- Shipped the beta", "the Stand-up sections")
        XCTAssertEqual(coordinator.record(id)?.templateID, MeetingTemplate.standUp.id)
        XCTAssertEqual(coordinator.settings.templateID, MeetingTemplate.standUp.id, "the next meeting starts with the last template")
    }

    func testDeleteRemovesAFinishedMeetingButNotTheOneThatRecords() async throws {
        let coordinator = makeCoordinator()
        coordinator.speechModelChanged(.parakeetV3)
        try await coordinator.startMeeting(source: .manual)
        let first = try XCTUnwrap(coordinator.live?.id)
        await coordinator.stop()
        try await coordinator.startMeeting(source: .manual)
        let recording = try XCTUnwrap(coordinator.live?.id)

        try await coordinator.delete(first)
        try await coordinator.delete(recording)

        XCTAssertNil(coordinator.record(first))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.folder(for: first).path))
        XCTAssertNotNil(coordinator.record(recording))
        await coordinator.stop()
    }

    func testARecordingStopsAtTheTimeLimit() async throws {
        let coordinator = makeCoordinator()
        var notices: [MeetingNotice] = []
        coordinator.onNotice = { notices.append($0) }
        try await coordinator.startMeeting(source: .manual)
        let id = try XCTUnwrap(coordinator.live?.id)

        clock += MeetingCoordinator.recordingLimit
        let stopped = await waitUntil { coordinator.live == nil }

        XCTAssertTrue(stopped)
        XCTAssertEqual(coordinator.record(id)?.endedAt, clock)
        XCTAssertEqual(notices.first, .stoppedAtTimeLimit(id, after: 4 * 60 * 60))
        XCTAssertEqual(event("meeting_ended")?["reason"], .label("time_limit"))
        XCTAssertEqual(event("meeting_ended")?["duration_ms"], .int(240 * 60_000))
    }

    func testARecordingStopsWhenNobodySpeaksForTheLimitOnEveryTrack() async throws {
        let coordinator = makeCoordinator(speechlessLimit: 20)
        coordinator.speechModelChanged(.parakeetV3)
        var notices: [MeetingNotice] = []
        coordinator.onNotice = { notices.append($0) }
        try await coordinator.startMeeting(source: .manual)
        let session = try XCTUnwrap(coordinator.live)

        // Speech ends at 10 s. The microphone track is checked to 40 s, the
        // call track to 20 s only.
        you.push(tone(10, level: 0.3) + silence(30))
        them.push(silence(20))
        try await Task.sleep(for: .milliseconds(300))
        let recordingWhileTheCallTrackIsBehind = coordinator.live != nil
        them.push(silence(20))
        let stopped = await waitUntil { coordinator.live == nil }

        XCTAssertTrue(recordingWhileTheCallTrackIsBehind)
        XCTAssertTrue(stopped)
        XCTAssertEqual(notices.first, .stoppedWithoutSpeech(session.id, after: 20))
    }

    func testAskOffersACallAndRecordStartsAMeetingForIt() async throws {
        let coordinator = makeCoordinator()
        await coordinator.start()

        hold(holding(zoom))
        hold(holding(zoom), after: 2)
        let offered = coordinator.callCard
        await coordinator.recordOfferedCall()
        let record = coordinator.live?.record

        XCTAssertEqual(offered, .offer(zoom))
        XCTAssertNil(coordinator.callCard)
        XCTAssertEqual(cardAnswers, ["offer record"])
        XCTAssertEqual(event("meeting_started")?["source"], .label("offer"))
        XCTAssertEqual(record?.title, "Zoom call")
        XCTAssertEqual(record?.callAppBundleID, zoom.bundleID)
        await coordinator.stop()
    }

    func testTheOfferClosesWhenTheCallEndsAndNeverShowsForANeverAskApp() async {
        let coordinator = makeCoordinator()
        await coordinator.start()

        hold(holding(teams))
        hold(holding(teams), after: 2)
        let offered = coordinator.callCard
        hold([], after: 1)
        let afterTheCall = coordinator.callCard
        hold(holding(zoom), after: 1)
        hold(holding(zoom), after: 2)
        coordinator.neverAsk(for: zoom)
        hold([], after: 1)
        hold(holding(zoom), after: 1)
        hold(holding(zoom), after: 2)

        XCTAssertEqual(offered, .offer(teams))
        XCTAssertNil(afterTheCall)
        XCTAssertEqual(coordinator.settings.neverAskBundleIDs, [zoom.bundleID])
        XCTAssertNil(coordinator.callCard)
        XCTAssertEqual(cardAnswers, ["offer call_ended", "offer never"])
    }

    func testRecordAutomaticallyStartsTheRecordingAndCancelDeletesIt() async throws {
        let coordinator = makeCoordinator()
        await coordinator.start()
        coordinator.chooseCallStartAction(.recordAutomatically)

        hold(holding(zoom))
        hold(holding(zoom), after: 2)
        let started = await waitUntil {
            if case .startedAutomatically(zoom, _) = coordinator.callCard {
                return true
            }
            return false
        }
        let id = try XCTUnwrap(coordinator.live?.id)
        await coordinator.cancelAutomaticRecording()
        let stored = await store.loadAll()

        XCTAssertTrue(started)
        XCTAssertEqual(event("meeting_started")?["source"], .label("automatic"))
        XCTAssertNil(coordinator.live)
        XCTAssertNil(coordinator.record(id))
        XCTAssertTrue(stored.isEmpty)
        XCTAssertEqual(cardAnswers, ["started cancel"])
        XCTAssertNil(event("meeting_ended"), "a canceled recording is no meeting")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.folder(for: id).path))
    }

    func testABrowserWithoutACallTitleIsOnlyOfferedWhenRecordingAutomatically() async {
        let coordinator = makeCoordinator()
        await coordinator.start()
        coordinator.chooseCallStartAction(.recordAutomatically)

        hold(holding(chrome))
        hold(holding(chrome), after: 2)
        let atTwoSeconds = coordinator.callCard
        hold(holding(chrome), after: 18)

        XCTAssertNil(atTwoSeconds)
        XCTAssertEqual(coordinator.callCard, .offer(chrome))
        XCTAssertNil(coordinator.live)
    }

    func testStopNowEndsTheMeetingWhereTheCallEnded() async throws {
        let coordinator = makeCoordinator()
        coordinator.speechModelChanged(.parakeetV3)
        await coordinator.start()
        let start = clock!
        hold(holding(zoom))
        hold(holding(zoom), after: 2)
        await coordinator.recordOfferedCall()
        let id = try XCTUnwrap(coordinator.live?.id)

        // Words from 0 to 2.8 s; Zoom releases the microphone at 4.5 s; more
        // words from 4.8 s.
        you.push(tone(2.5, level: 0.3) + silence(2))
        clock += 4.5
        hold([], after: 4.5)
        let card = coordinator.callCard
        you.push(silence(0.3) + tone(2.5, level: 0.5) + silence(0.5))
        clock += 5
        await coordinator.stopEndedCall()
        let segments = await store.segments(of: id)
        let decoded = await engine.calls

        XCTAssertEqual(card, .callEnded(zoom, silent: false, endedAt: start + 4.5, stopsAt: start + 4.5 + 30))
        XCTAssertEqual(decoded, 2, "the words after the call were recorded and decoded")
        XCTAssertEqual(cardAnswers, ["offer record", "call_ended stop_now"])
        XCTAssertEqual(event("meeting_ended")?["reason"], .label("call_ended"))
        XCTAssertEqual(try XCTUnwrap(coordinator.record(id)?.endedAt).timeIntervalSince(start), 4.5, accuracy: 0.001)
        XCTAssertEqual(segments.map(\.text), [longSentence], "the words after the call ended go")
    }

    func testAfterKeepRecordingTheMeetingFollowsTheNextCallAndStopsWhenItEnds() async throws {
        cardDurations.stop = 0.05
        let coordinator = makeCoordinator()
        await coordinator.start()
        hold(holding(zoom))
        hold(holding(zoom), after: 2)
        coordinator.declineOffer()
        try await coordinator.startMeeting(source: .manual)
        let followed = await waitUntil { coordinator.live?.record.callAppBundleID == zoom.bundleID }

        hold([], after: 5)
        coordinator.keepRecording()
        try await Task.sleep(for: .milliseconds(150))
        let keptRecording = coordinator.live != nil
        hold(holding(zoom), after: 1)
        hold(holding(zoom), after: 2)
        hold([], after: 5)
        let stopped = await waitUntil { coordinator.live == nil }

        XCTAssertTrue(followed, "a meeting that starts during a call follows it")
        XCTAssertTrue(keptRecording)
        XCTAssertTrue(stopped, "the call-ended card stops the recording by itself")
        XCTAssertEqual(cardAnswers, ["offer not_now", "call_ended keep_recording", "call_ended timeout"])
    }

    func testTheCallEndedCardClosesWhenTheCallPlaysSoundAgain() async throws {
        cardDurations.stop = 0.05
        let coordinator = makeCoordinator()
        await coordinator.start()
        hold(holding(zoom))
        hold(holding(zoom), after: 2)
        await coordinator.recordOfferedCall()

        hold(holding(zoom, output: false), after: MeetingCallWatch.silentCallLimit + 1)
        let silentCard = coordinator.callCard
        hold(holding(zoom), after: 1)
        try await Task.sleep(for: .milliseconds(150))

        guard case .callEnded(zoom, silent: true, _, _) = silentCard else {
            return XCTFail("expected the silent call-ended card, got \(String(describing: silentCard))")
        }
        XCTAssertNil(coordinator.callCard)
        XCTAssertNotNil(coordinator.live, "the recording goes on")
        await coordinator.stop()
    }

    func testDoNothingStopsCallDetection() async {
        let coordinator = makeCoordinator()
        await coordinator.start()
        let listensWithAsk = microphone.listening

        coordinator.chooseCallStartAction(.doNothing)
        hold(holding(zoom))
        hold(holding(zoom), after: 2)

        XCTAssertTrue(listensWithAsk)
        XCTAssertFalse(microphone.listening)
        XCTAssertEqual(microphone.reads, 0)
        XCTAssertNil(coordinator.callCard)
    }

    func testWithDoNothingARecordingStillFollowsItsCall() async throws {
        let coordinator = makeCoordinator()
        await coordinator.start()
        coordinator.chooseCallStartAction(.doNothing)

        try await coordinator.startMeeting(source: .manual)
        hold(holding(zoom))
        hold(holding(zoom), after: 2)
        let followed = await waitUntil { coordinator.live?.record.callAppBundleID == zoom.bundleID }
        await coordinator.stop()

        XCTAssertTrue(followed, "the no-call-audio warning needs the call app")
        XCTAssertFalse(microphone.listening, "detection stops again with the recording")
    }

    func testTooLittleSpeechNeedsNoSummaryModel() async throws {
        summaryAvailability = .unavailable
        let coordinator = makeCoordinator()
        coordinator.speechModelChanged(.parakeetV3)
        try await coordinator.startMeeting(source: .manual)
        let id = try XCTUnwrap(coordinator.live?.id)

        them.push(tone(2.5, level: 0.5) + silence(0.5))
        await coordinator.stop()

        XCTAssertEqual(coordinator.record(id)?.status, .noSpeech)
    }

    func testRegenerateNeedsAFinalTranscript() async throws {
        let left = MeetingRecord(title: "Meeting", startedAt: clock, tracks: [.you], status: .interrupted, templateID: "general")
        try await store.create(left)
        let coordinator = makeCoordinator()
        await coordinator.start()

        await coordinator.regenerate(left.id)

        XCTAssertEqual(coordinator.record(left.id)?.status, .interrupted)
    }

    func testATrackThatStartsAgainNoLongerShowsAsFailed() async throws {
        let coordinator = makeCoordinator()
        them.failsToStart = true
        try await coordinator.startMeeting(source: .manual)
        let session = try XCTUnwrap(coordinator.live)
        let failed = await waitUntil { session.failedTracks[.them] != nil }

        await coordinator.pause()
        them.failsToStart = false
        try await coordinator.resume()
        let cleared = await waitUntil { session.failedTracks.isEmpty }

        XCTAssertTrue(failed)
        XCTAssertTrue(cleared)
        await coordinator.stop()
    }

    func testSourceProblemsShowOnTheLiveMeeting() async throws {
        let coordinator = makeCoordinator()
        try await coordinator.startMeeting(source: .manual)
        let session = try XCTUnwrap(coordinator.live)

        you.onEvent?(.inputChanged(deviceName: "AirPods Pro"))
        them.onEvent?(.failed("The tap stopped."))
        let shown = await waitUntil { session.changedInput != nil && !session.failedTracks.isEmpty }

        XCTAssertTrue(shown)
        XCTAssertEqual(session.changedInput, "AirPods Pro")
        XCTAssertEqual(session.failedTracks, [.them: "The tap stopped."])
        await coordinator.stop()
    }

    func testAQuitSavesTheRecordingForFinishTranscriptAtTheNextLaunch() async throws {
        let first = makeCoordinator()
        first.speechModelChanged(.parakeetV3)
        try await first.startMeeting(source: .manual)
        let id = try XCTUnwrap(first.live?.id)
        you.push(tone(2.5, level: 0.3) + silence(0.5))
        clock += 3

        await first.stopForQuit()
        let saved = await store.record(id)
        let next = makeCoordinator()
        next.speechModelChanged(.parakeetV3)
        await next.start()
        let atLaunch = next.record(id)?.status
        next.finishTranscript(id)
        let finished = await waitUntil { next.record(id)?.status == .done }

        XCTAssertNil(first.live)
        XCTAssertEqual(saved?.endedAt, saved?.startedAt.addingTimeInterval(3))
        XCTAssertEqual(atLaunch, .notTranscribed, "the next launch shows it with Finish Transcript")
        XCTAssertTrue(finished)
    }

    /// A meeting that a quit left during the recording, with 3 s of audio:
    /// one sentence.
    private func leftRecording(startedAt: Date) async throws -> UUID {
        let left = MeetingRecord(title: "Meeting", startedAt: startedAt, tracks: [.you], status: .recording, templateID: "general")
        try await store.create(left)
        let writer = try MeetingAudioFileWriter(url: store.audioURL(.you, for: left.id))
        try writer.append(tone(2.5, level: 0.3) + silence(0.5))
        try writer.close()
        return left.id
    }

    /// The props of the last event with this name.
    private func event(_ name: String) -> [String: AnalyticsValue]? {
        analytics.trackedEvents.last { $0.name == name }?.props
    }

    /// "card action" for each call card that closed.
    private var cardAnswers: [String] {
        analytics.trackedEvents.filter { $0.name == "meeting_call_card" }.map { event in
            [event.props["kind"], event.props["action"]].map { value in
                if case let .label(text) = value {
                    return text
                }
                return "?"
            }.joined(separator: " ")
        }
    }

    /// The call apps that hold the microphone from now on, `seconds` later,
    /// as the read after a Core Audio listener sees them.
    private func hold(_ users: [MicrophoneUser], after seconds: TimeInterval = 0) {
        uptime += seconds
        microphone.anyInputRunning = !users.isEmpty
        microphone.users = users
        microphone.inputActivityChanged()
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool) async -> Bool {
        for _ in 0 ..< 500 {
            if await condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await condition()
    }
}

final class MeetingCallOutputTests: XCTestCase {
    func testOnlyBluetoothAndTheHeadphoneJackCountAsHeadphones() {
        let speakers: UInt32 = 0x6973_706B // 'ispk'

        XCTAssertFalse(MeetingCallOutput.playsOnSpeakers(transport: .bluetooth, dataSource: nil))
        XCTAssertFalse(MeetingCallOutput.playsOnSpeakers(transport: .builtIn, dataSource: MeetingCallOutput.headphonesDataSource))
        XCTAssertTrue(MeetingCallOutput.playsOnSpeakers(transport: .builtIn, dataSource: speakers))
        XCTAssertTrue(MeetingCallOutput.playsOnSpeakers(transport: .usb, dataSource: nil))
    }
}

final class MeetingSettingsStoreTests: XCTestCase {
    func testSettingsFromAnOlderBuildKeepTheirValuesAndDefaultTheRest() throws {
        let suite = "MeetingSettingsStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data(#"{"noticeAccepted":true,"neverAskBundleIDs":["us.zoom.xos"],"transcriptModel":"retiredModel"}"#.utf8), forKey: "settings")
        let store = MeetingSettingsStore(userDefaults: defaults, key: "settings")

        var loaded = store.load()
        let unknownModel = loaded.transcriptModel
        loaded.callStartAction = .recordAutomatically
        loaded.transcriptModel = .cohereTranscribe
        store.save(loaded)
        let reloaded = store.load()

        XCTAssertEqual(reloaded.neverAskBundleIDs, ["us.zoom.xos"], "a key that a later build dropped does not stop the load")
        XCTAssertNil(unknownModel, "a transcript model that this build does not know is the dictation model")
        XCTAssertEqual(reloaded.templateID, MeetingTemplate.general.id)
        XCTAssertEqual(reloaded.callStartAction, .recordAutomatically)
        XCTAssertEqual(reloaded.transcriptModel, .cohereTranscribe)
    }
}

// MARK: - Fakes

private final class PushSource: MeetingAudioSource, @unchecked Sendable {
    var onSamples: (([Float]) -> Void)?
    var onEvent: ((MeetingAudioSourceEvent) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    var failsToStart = false

    func start() throws {
        startCount += 1
        if failsToStart {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    func stop() {
        stopCount += 1
    }

    func push(_ samples: [Float]) {
        onSamples?(samples)
    }
}

@MainActor
private final class FakeHost: MeetingHost {
    private(set) var idleCount = 0

    var meetingInputDeviceID: String? {
        nil
    }

    func requestMeetingMicrophoneAccess() async -> Bool {
        true
    }

    func meetingSummaryModelIsIdle() {
        idleCount += 1
    }

    func meetingCouldNotStart(_ error: Error) {}
}

/// Hears speech in audio that peaks at 0.25 or more.
private final class LoudSpeechDetector: SpeechDetecting {
    func containsSpeech(_ samples: [Float]) -> Bool {
        samples.contains { abs($0) >= 0.25 }
    }
}

/// Answers by the audio's peak level.
private actor WordEngine: TranscriptionServiceProtocol {
    private(set) var calls = 0
    private(set) var unloads = 0
    private let words: [Float: String]

    init(words: [Float: String]) {
        self.words = words
    }

    func loadModel(config: RecognizerConfig) async throws {}

    func unloadModel() async {
        unloads += 1
    }

    func transcribe(
        samples: [Float],
        sampleRate: Int,
        purpose: TranscriptionPurpose,
        onProgress: @escaping @Sendable (TranscriptionProgress) -> Void
    ) async throws -> String {
        calls += 1
        let peak = samples.map(abs).max() ?? 0
        return words.first { abs($0.key - peak) < 0.02 }?.value ?? ""
    }
}

/// Answers each summary request by its kind; while closed, a request waits
/// until it opens or its task is canceled.
private actor GatedSummaryModel: MeetingSummaryModel {
    private(set) var kinds: [MeetingSummaryRequest.Kind] = []
    private(set) var waiting = false
    private var isOpen = true

    func close() {
        isOpen = false
    }

    func open() {
        isOpen = true
    }

    func contextTokens() async -> Int {
        4_096
    }

    func tokenCount(_ text: String) async -> Int? {
        text.split(whereSeparator: \.isWhitespace).count
    }

    func generate(_ request: MeetingSummaryRequest) async throws -> String {
        kinds.append(request.kind)
        waiting = true
        defer { waiting = false }
        while !isOpen {
            try await Task.sleep(for: .milliseconds(5))
        }
        switch request.kind {
        case .part, .userNotes:
            return request.input.contains("\nDone:") ? "Done: Shipped the beta" : "Decisions: Ship on Friday"
        case .overview:
            return "Title: Release plan\nThe team agreed to ship on Friday."
        case .summary, .join:
            return "Release plan\n## Overview\nShip on Friday."
        }
    }
}
