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

private let zoom = MeetingCallApp(name: "Zoom", bundleID: "us.zoom.xos", isBrowser: false)

private func holding(_ apps: MeetingCallApp...) -> [MicrophoneUser] {
    apps.map { MicrophoneUser(app: $0, runsOutput: true) }
}

/// One sentence of 30 words: enough speech for a summary.
private let longSentence = (1 ... 30).map { "word\($0)" }.joined(separator: " ") + "."

@MainActor
final class MeetingFlowTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var store: MeetingStore!
    private var you: PushSource!
    private var them: PushSource!
    private var host: FakeHost!
    private var engine: WordEngine!
    private var transcriptEngine: WordEngine!
    private var transcriptEngineError: Error?
    private var summaryModel: GatedSummaryModel!
    private var hostedSummaryModel: GatedSummaryModel!
    private var clock: Date!
    private var freeBytes: Int64 = 10_000_000_000
    private var callOnSpeakers = false
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
        hostedSummaryModel = GatedSummaryModel()
        clock = Date(timeIntervalSince1970: 1_800_000_000)
        microphone = FakeMicrophoneUsers()
        analytics = SpyAnalytics()
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
        try await super.tearDown()
    }

    private func makeCoordinator() -> MeetingCoordinator {
        let environment = MeetingEnvironment(
            canRecordCallAudio: true,
            makeSources: { [unowned self] _ in [.you: you, .them: them] },
            freeDiskBytes: { [unowned self] in freeBytes },
            callPlaysOnSpeakers: { [unowned self] in callOnSpeakers },
            makeMicrophoneUsers: { [unowned self] in microphone },
            now: { [unowned self] in clock },
            uptime: { [unowned self] in uptime },
            liveCheckInterval: .milliseconds(20),
            speechlessLimit: 15 * 60,
            makeSpeechDetector: { LoudSpeechDetector() },
            callCardDurations: cardDurations,
            makePlayer: { _ in SilentMeetingAudioPlayer(duration: 3) }
        )
        let coordinator = MeetingCoordinator(
            store: store,
            templates: MeetingTemplateStore(fileURL: root.appendingPathComponent("templates.json")),
            settingsStore: MeetingSettingsStore(userDefaults: defaults),
            engine: engine,
            makeTranscriptEngine: { [unowned self] _ in
                if let transcriptEngineError {
                    throw transcriptEngineError
                }
                return transcriptEngine
            },
            environment: environment,
            summaryAvailability: { [unowned self] choice in choice == .automatic ? summaryAvailability : .ready(.apiEndpoint) },
            makeSummaryModel: { [unowned self] engine in engine.isOnDevice ? summaryModel : hostedSummaryModel },
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
        let progressShown = await waitUntil { coordinator.transcriptPasses[id]?.progress != nil }
        try await Task.sleep(for: .milliseconds(200))
        let decodesDuringDictation = await engine.calls
        coordinator.dictationChanged(active: false)
        await stopping.value
        let segments = await store.segments(of: id)

        XCTAssertTrue(progressShown, "the page shows the progress while the transcript waits")
        XCTAssertEqual(decodesDuringDictation, 0)
        XCTAssertEqual(segments.map(\.track), [.them, .you], "the dictated words are not meeting talk; talk after the capture ends is")
        XCTAssertNil(coordinator.transcriptPasses[id])
    }

    func testAMeetingShowsItsLinesWhileItRecordsAndStopDecodesOnlyTheRest() async throws {
        let coordinator = makeCoordinator()
        coordinator.speechModelChanged(.parakeetV3)
        try await coordinator.startMeeting(source: .manual)
        let session = try XCTUnwrap(coordinator.live)
        var snapshots: [[MeetingSegment]] = []
        func shows(_ count: Int) async -> Bool {
            await waitUntil {
                if snapshots.last != session.transcript.lines {
                    snapshots.append(session.transcript.lines)
                }
                return session.transcript.lines.count == count
            }
        }

        you.push(tone(2.5, level: 0.3) + silence(0.5))
        them.push(silence(3))
        let youShown = await shows(1)
        them.push(tone(2.5, level: 0.5) + silence(0.5))
        let themShown = await shows(2)
        let fromStart = await coordinator.transcript(of: session.id, from: 0)
        let fromOneSecond = await coordinator.transcript(of: session.id, from: 1)
        let decodesDuringTheCall = await engine.calls
        await coordinator.stop()
        let decodesAfterStop = await engine.calls
        let final = await coordinator.transcript(of: session.id, from: 0)

        XCTAssertTrue(youShown)
        XCTAssertTrue(themShown)
        XCTAssertEqual(fromStart.lines.map(\.track), [.you, .them])
        XCTAssertEqual(fromStart.state, .recording(completeThrough: 2.8), "the You track has its talk up to 2.8 s, the Them track more")
        XCTAssertEqual(fromOneSecond.lines.map(\.text), ["Them speaks here."])
        for (earlier, later) in zip(snapshots, snapshots.dropFirst()) {
            XCTAssertTrue(later.starts(with: earlier), "a shown line never changes, moves or goes")
        }
        XCTAssertEqual(decodesDuringTheCall, 2)
        XCTAssertEqual(decodesAfterStop, 2, "the lines of the call are stored; the rest of the audio is silence")
        XCTAssertEqual(final.lines.map(\.text), [longSentence, "Them speaks here."])
        XCTAssertEqual(final.state, .final, "a reader reads the final transcript again")
    }

    func testOnSpeakersAnEchoOfTheCallNeverShowsDuringTheCall() async throws {
        callOnSpeakers = true
        let coordinator = makeCoordinator()
        coordinator.speechModelChanged(.parakeetV3)
        try await coordinator.startMeeting(source: .manual)
        let session = try XCTUnwrap(coordinator.live)

        you.push(tone(2.5, level: 0.5) + silence(0.5))
        them.push(tone(2.5, level: 0.5) + silence(0.5))
        let bothDecoded = await waitUntil { await self.engine.calls == 2 }
        try await Task.sleep(for: .milliseconds(50))
        let shownBeforeTheCallTrackMovesOn = session.transcript.lines
        them.push(silence(3))
        let released = await waitUntil { !session.transcript.lines.isEmpty }
        await coordinator.stop()
        let final = await coordinator.transcript(of: session.id)

        XCTAssertTrue(bothDecoded)
        XCTAssertEqual(shownBeforeTheCallTrackMovesOn, [], "the You line waits for the call lines near it")
        XCTAssertTrue(released)
        XCTAssertEqual(session.transcript.lines.map(\.track), [.them], "the microphone heard the call: its line never shows")
        XCTAssertEqual(final.map(\.track), [.them])
    }

    func testAQuitKeepsTheLinesOfTheCallAndFinishTranscriptDecodesOnlyTheRest() async throws {
        let first = makeCoordinator()
        first.speechModelChanged(.parakeetV3)
        try await first.startMeeting(source: .manual)
        let session = try XCTUnwrap(first.live)
        you.push(tone(2.5, level: 0.3) + silence(0.5))
        them.push(silence(3))
        let shown = await waitUntil { session.transcript.lines.count == 1 }

        await first.stopForQuit()
        let next = makeCoordinator()
        next.speechModelChanged(.parakeetV3)
        await next.start()
        next.finishTranscript(session.id)
        let finished = await waitUntil { next.record(session.id)?.status == .done }
        let segments = await store.segments(of: session.id)
        let decodes = await engine.calls

        XCTAssertTrue(shown)
        XCTAssertTrue(finished)
        XCTAssertEqual(segments.map(\.text), [longSentence])
        XCTAssertEqual(decodes, 1, "Finish Transcript starts after the stored line")
    }

    func testATranscriptModelThatDoesNotLoadSaysWhyAndStopTriesItAgain() async throws {
        transcriptEngineError = MeetingTranscriptModelError.notDownloaded("Cohere Transcribe")
        let coordinator = makeCoordinator()
        coordinator.speechModelChanged(.parakeetV3)
        coordinator.updateSettings { $0.transcriptModel = .cohereTranscribe }
        try await coordinator.startMeeting(source: .manual)
        let session = try XCTUnwrap(coordinator.live)
        let failed = await waitUntil { session.transcriptFailure != nil }

        transcriptEngineError = nil
        you.push(tone(2.5, level: 0.3) + silence(0.5))
        them.push(silence(3))
        await coordinator.stop()
        let segments = await store.segments(of: session.id)
        let dictationEngineDecodes = await engine.calls

        XCTAssertTrue(failed)
        XCTAssertEqual(session.transcriptFailure, "Cohere Transcribe is not downloaded. Download it in Settings, or choose another transcript model.")
        XCTAssertEqual(segments.map(\.text), [longSentence], "the stop loads the transcript model again")
        XCTAssertEqual(dictationEngineDecodes, 0)
    }

    func testAMeetingStoppedWhileAnEarlierTranscriptRunsGetsItsTranscriptAfterIt() async throws {
        let earlier = try await finishedMeeting(status: .notTranscribed, endedDaysAgo: 0)
        let coordinator = makeCoordinator()
        coordinator.speechModelChanged(.parakeetV3)
        await coordinator.start()
        coordinator.dictationChanged(active: true)
        coordinator.finishTranscript(earlier.id)
        try await coordinator.startMeeting(source: .manual)
        let id = try XCTUnwrap(coordinator.live?.id)
        them.push(tone(2.5, level: 0.5) + silence(0.5))

        let stopping = Task { await coordinator.stop() }
        let waits = await waitUntil { coordinator.transcriptPasses[id]?.waiting == true }
        coordinator.dictationChanged(active: false)
        await stopping.value
        let segments = await store.segments(of: id)
        let earlierDone = await waitUntil { coordinator.record(earlier.id)?.status == .done }

        XCTAssertTrue(waits, "the stopped meeting waits for the earlier transcript")
        XCTAssertTrue(earlierDone)
        XCTAssertEqual(segments.map(\.text), ["Them speaks here."])
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

    func testStopNowEndsAnAutomaticRecordingWhereTheCallEnded() async throws {
        let coordinator = makeCoordinator()
        coordinator.speechModelChanged(.parakeetV3)
        coordinator.updateSettings { $0.audioRetention = .sevenDays }
        await coordinator.start()
        let start = clock!
        await startAutomatically(coordinator)
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
        let keptSamples = try MeetingAudioFileReader.sampleCount(at: store.audioURL(.you, for: id))

        XCTAssertEqual(card, .callEnded(zoom, silent: false, endedAt: start + 4.5, stopsAt: start + 4.5 + 30))
        XCTAssertEqual(decoded, 1, "the words after the call ended leave the audio, so they are never decoded")
        XCTAssertEqual(keptSamples, Int(4.5 * Double(rate)), "the kept audio ends where the call ended")
        XCTAssertEqual(cardAnswers, ["call_ended stop_now"])
        XCTAssertEqual(event("meeting_ended")?["reason"], .label("call_ended"))
        XCTAssertEqual(try XCTUnwrap(coordinator.record(id)?.endedAt).timeIntervalSince(start), 4.5, accuracy: 0.001)
        XCTAssertEqual(segments.map(\.text), [longSentence], "the words after the call ended go")
    }

    func testKeptAudioGoesAtTheFirstLaunchAfterItsTime() async throws {
        let cases: [(status: MeetingStatus, keep: MeetingAudioRetention, endedDaysAgo: Double, kept: Bool)] = [
            (.done, .untilTranscript, 0, false),
            (.done, .sevenDays, 6, true),
            (.done, .sevenDays, 8, false),
            (.noSpeech, .thirtyDays, 29, true),
            (.summaryFailed, .thirtyDays, 31, false),
            (.notTranscribed, .untilTranscript, 31, true),
        ]
        for (status, keep, days, kept) in cases {
            let meeting = try await finishedMeeting(status: status, endedDaysAgo: days)
            let coordinator = makeCoordinator()
            coordinator.updateSettings { $0.audioRetention = keep }

            await coordinator.start()

            let label = "\(status) with \(keep), \(days) days after the meeting"
            XCTAssertEqual(!store.audioTracks(of: meeting.id).isEmpty, kept, label)
            XCTAssertEqual(coordinator.audioOnMac.contains(meeting.id), kept, label)
        }
    }

    func testTranscribeAgainReplacesTheTranscriptAndKeepsTheNotesAndTheSummary() async throws {
        let meeting = try await finishedMeeting(status: .done, endedDaysAgo: 1)
        try await store.appendSegment(MeetingSegment(id: UUID(), track: .you, audioStart: 0, audioEnd: 40_000, text: "Old words."), to: meeting.id)
        try await store.saveNotes("Ask legal.", for: meeting.id)
        try await store.saveSummary("## Overview\nShip Friday.", for: meeting.id)
        let coordinator = makeCoordinator()
        coordinator.speechModelChanged(.parakeetV3)
        coordinator.updateSettings { $0.audioRetention = .sevenDays }
        await coordinator.start()
        let listedBefore = await coordinator.listText(for: meeting.id)

        coordinator.transcribeAgain(meeting.id)
        let asked = coordinator.transcriptPasses[meeting.id]?.kind == .again
        let finished = await waitUntil { coordinator.transcriptPasses[meeting.id] == nil }
        let transcript = await coordinator.transcript(of: meeting.id)
        let listedAfter = await coordinator.listText(for: meeting.id)
        let notes = await coordinator.notes(of: meeting.id)
        let summary = await coordinator.summary(of: meeting.id)
        let summaryRequests = await summaryModel.kinds

        XCTAssertTrue(asked)
        XCTAssertTrue(finished)
        XCTAssertEqual(transcript.map(\.text), [longSentence])
        XCTAssertEqual(listedBefore.transcript, ["Old words."])
        XCTAssertEqual(listedAfter.transcript, [longSentence], "the list and its search show the new transcript")
        XCTAssertEqual(notes, "Ask legal.")
        XCTAssertEqual(summary, "## Overview\nShip Friday.")
        XCTAssertEqual(summaryRequests, [], "Regenerate writes the summary again, not Transcribe Again")
        XCTAssertEqual(coordinator.record(meeting.id)?.status, .done)
    }

    func testNotesTypedJustBeforeTheStopCountForTheSummary() async throws {
        let coordinator = makeCoordinator()
        coordinator.speechModelChanged(.parakeetV3)
        try await coordinator.startMeeting(source: .manual)
        let id = try XCTUnwrap(coordinator.live?.id)
        you.push(silence(3))
        coordinator.textSaves.stage(.notes, of: id) {
            await coordinator.saveNotes("Ask legal about the pricing copy.", for: id)
        }
        await summaryModel.close()

        await coordinator.stop()
        let asked = await waitUntil { await self.summaryModel.waiting }
        let inputs = await summaryModel.inputs
        await summaryModel.open()
        let finished = await waitUntil { coordinator.record(id)?.status == .done }

        XCTAssertTrue(asked, "the notes are enough for a summary")
        XCTAssertTrue(inputs.contains { $0.contains("Ask legal about the pricing copy.") }, "the notes typed just before the stop reach the summary")
        XCTAssertTrue(finished)
    }

    func testAFailedTranscribeAgainKeepsTheTranscript() async throws {
        let meeting = try await finishedMeeting(status: .done, endedDaysAgo: 1)
        try await store.appendSegment(MeetingSegment(id: UUID(), track: .you, audioStart: 0, audioEnd: 40_000, text: "Old words."), to: meeting.id)
        transcriptEngineError = MeetingTranscriptModelError.notDownloaded("Cohere Transcribe")
        let coordinator = makeCoordinator()
        coordinator.updateSettings {
            $0.audioRetention = .sevenDays
            $0.transcriptModel = .cohereTranscribe
        }
        var notices: [MeetingNotice] = []
        coordinator.onNotice = { notices.append($0) }
        await coordinator.start()

        coordinator.transcribeAgain(meeting.id)
        let finished = await waitUntil { coordinator.transcriptPasses[meeting.id] == nil }
        let transcript = await coordinator.transcript(of: meeting.id)

        XCTAssertTrue(finished)
        XCTAssertEqual(transcript.map(\.text), ["Old words."])
        XCTAssertEqual(notices, [.notTranscribedAgain(meeting.id)])
        XCTAssertTrue(coordinator.audioOnMac.contains(meeting.id), "the audio stays for another try")
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

    /// A meeting that ended `days` days before the clock, with 3 s of audio:
    /// one sentence at the default level, no words at a level the engine does
    /// not know.
    private func finishedMeeting(status: MeetingStatus, endedDaysAgo days: Double, level: Float = 0.3) async throws -> MeetingRecord {
        let end = clock.addingTimeInterval(-days * 24 * 60 * 60)
        var meeting = MeetingRecord(title: "Design sync", startedAt: end.addingTimeInterval(-1_800), tracks: [.you], status: status, templateID: "general")
        meeting.endedAt = end
        try await store.create(meeting)
        let writer = try MeetingAudioFileWriter(url: store.audioURL(.you, for: meeting.id))
        try writer.append(tone(2.5, level: level) + silence(0.5))
        try writer.close()
        return meeting
    }

    /// Record Automatically, then a Zoom call that holds the microphone for 2 s.
    private func startAutomatically(_ coordinator: MeetingCoordinator) async {
        coordinator.chooseCallStartAction(.recordAutomatically)
        hold(holding(zoom))
        hold(holding(zoom), after: 2)
        let started = await waitUntil { coordinator.live != nil }
        XCTAssertTrue(started, "Record Automatically starts the recording")
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

    func meetingSummaryAskedAgain() async {}

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
    private(set) var inputs: [String] = []
    private(set) var waiting = false
    private var isOpen = true
    private var failure: MeetingSummaryFailure?

    func fail(with failure: MeetingSummaryFailure) {
        self.failure = failure
    }

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
        inputs.append(request.input)
        waiting = true
        defer { waiting = false }
        while !isOpen {
            try await Task.sleep(for: .milliseconds(5))
        }
        if let failure {
            throw MeetingSummaryError.failed(failure)
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
