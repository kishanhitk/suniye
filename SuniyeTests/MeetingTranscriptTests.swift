import XCTest
@testable import Suniye

private let rate = MeetingAudioFormat.sampleRate

/// A 220 Hz tone whose peak is `level`; level 0 gives silence.
private func tone(_ seconds: Double, level: Float = 0.3) -> [Float] {
    let count = Int(seconds * Double(rate))
    guard level > 0 else { return Array(repeating: 0, count: count) }
    return (0 ..< count).map { level * Float(sin(2 * Double.pi * 220 * Double($0) / Double(rate))) }
}

private func silence(_ seconds: Double) -> [Float] {
    tone(seconds, level: 0)
}

private func samples(_ seconds: Double) -> Int {
    Int(seconds * Double(rate))
}

final class MeetingSegmenterTests: XCTestCase {
    func testAPauseAfterTwoSecondsEndsTheChunkThreeQuietWindowsIn() {
        var segmenter = MeetingSegmenter(track: .you)

        let chunks = segmenter.append(tone(2.5) + silence(1) + tone(1), at: 0)
        let rest = segmenter.flush()

        XCTAssertEqual(chunks.map(\.start), [0])
        XCTAssertEqual(chunks.first?.end, samples(2.8))
        XCTAssertEqual(rest?.start, samples(2.8))
        XCTAssertEqual(rest?.end, samples(4.5))
        XCTAssertEqual(rest?.hasSound, true)
    }

    func testAPauseBeforeTwoSecondsDoesNotEndTheChunk() {
        var segmenter = MeetingSegmenter(track: .you)

        let chunks = segmenter.append(tone(0.8) + silence(0.5) + tone(1.5) + silence(0.5), at: 0)

        XCTAssertEqual(chunks.map(\.end), [samples(3.1)], "the short reply joins the next sentence")
    }

    func testSpeechWithNoPauseIsCutAtTheQuietestPointBeforeTwelveSeconds() {
        var segmenter = MeetingSegmenter(track: .them)
        let quieter = tone(0.1, level: 0.05)
        let audio = tone(9) + quieter + tone(4.9)

        let chunks = segmenter.append(audio, at: 0)

        XCTAssertEqual(chunks.map(\.end), [samples(9)], "the softer 100 ms is not a pause, but it is the best place to cut")
    }

    func testSilenceMovesForwardInTwoSecondChunksThatAreNotDecoded() {
        var segmenter = MeetingSegmenter(track: .them)

        let chunks = segmenter.append(silence(5), at: 0)
        let rest = segmenter.flush()

        XCTAssertEqual(chunks.map(\.start), [0, samples(2)])
        XCTAssertEqual(chunks.map(\.hasSound), [false, false])
        XCTAssertEqual(rest?.end, samples(5))
    }

    func testAudioThatDoesNotContinueTheChunkEndsItFirst() {
        var segmenter = MeetingSegmenter(track: .you)
        _ = segmenter.append(tone(1), at: 0)

        let chunks = segmenter.append(tone(1), at: samples(5))
        let rest = segmenter.flush()

        XCTAssertEqual(chunks.map(\.start), [0])
        XCTAssertEqual(chunks.first?.end, samples(1))
        XCTAssertEqual(rest?.start, samples(5))
    }
}

final class MeetingTranscriptRulesTests: XCTestCase {
    private func segment(_ track: MeetingTrack, _ start: Double, _ end: Double, _ text: String) -> MeetingSegment {
        MeetingSegment(id: UUID(), track: track, audioStart: samples(start), audioEnd: samples(end), text: text)
    }

    func testAMicrophoneLineThatRepeatsTheCallIsDroppedOnlyWhenTheCallPlayedOnSpeakers() {
        let call = segment(.them, 0, 3, "We ship the release on Friday.")
        let echo = segment(.you, 0.5, 2.5, "ship the release on friday")

        XCTAssertEqual(MeetingTranscript.final([echo, call], callPlayedOnSpeakers: true), [call])
        XCTAssertEqual(MeetingTranscript.final([echo, call], callPlayedOnSpeakers: false), [call, echo])
    }

    func testNoLineAfterTheEndOfTheFollowedCallIsKept() {
        let during = segment(.you, 0, 3, "See you on Friday.")
        let after = segment(.you, 5, 7, "That went well.")
        var record = MeetingRecord(title: "Call", startedAt: Date(), tracks: [.you, .them], templateID: "general")
        record.transcriptEnd = 4 * MeetingAudioFormat.sampleRate

        XCTAssertEqual(MeetingTranscript.final([after, during], of: record), [during])
    }

    func testOwnWordsDuringTheCallAreKept() {
        let call = segment(.them, 0, 3, "We ship the release on Friday.")
        let reply = segment(.you, 1, 3, "I can take the docs.")

        XCTAssertEqual(MeetingTranscript.final([reply, call], callPlayedOnSpeakers: true), [call, reply])
    }

    func testTheSameWordsFarFromTheCallLineAreNotAnEcho() {
        let call = segment(.them, 20, 23, "We ship the release on Friday.")
        let repeated = segment(.you, 0, 3, "We ship the release on Friday.")

        XCTAssertEqual(MeetingTranscript.final([repeated, call], callPlayedOnSpeakers: true), [repeated, call])
    }

    func testTurnsJoinOneSpeakersLinesAndShowTheWallClock() {
        let segments = [
            segment(.you, 0, 2, "Morning."),
            segment(.you, 2, 4, "Ready?"),
            segment(.them, 70, 72, "Yes."),
        ]
        let timeline = MeetingTimeline(pauses: [MeetingPause(start: 30, end: 90)])

        XCTAssertEqual(MeetingTranscript.turns(segments, timeline: timeline, speakerLabels: true), ["[00:00] You: Morning. Ready?", "[02:10] Them: Yes."])
        XCTAssertEqual(MeetingTranscript.turns(segments, timeline: nil, speakerLabels: false), ["Morning. Ready?", "Yes."])
    }

    func testTheLiveViewHoldsAMicrophoneLineUntilTheCallIsDecodedPastIt() {
        let mine = segment(.you, 0, 2, "Morning, everyone.")
        let theirs = segment(.them, 2, 4, "Hi.")

        let early = MeetingTranscript.live([mine, theirs], callDecodedThrough: samples(3), callPlayedOnSpeakers: true)
        let later = MeetingTranscript.live([mine, theirs], callDecodedThrough: samples(3.5), callPlayedOnSpeakers: true)
        let noCall = MeetingTranscript.live([mine], callDecodedThrough: nil, callPlayedOnSpeakers: false)

        XCTAssertEqual(early, [theirs])
        XCTAssertEqual(later, [mine, theirs])
        XCTAssertEqual(noCall, [mine])
    }
}

final class MeetingTranscriberTests: XCTestCase {
    private var root: URL!
    private var store: MeetingStore!
    private var record: MeetingRecord!

    override func setUp() async throws {
        try await super.setUp()
        root = FileManager.default.temporaryDirectory.appendingPathComponent("MeetingTranscriberTests-\(UUID().uuidString)", isDirectory: true)
        store = MeetingStore(rootDirectory: root)
        record = MeetingRecord(title: "Zoom call", startedAt: Date(timeIntervalSince1970: 1_800_000_000), tracks: [.you, .them], templateID: "general")
        try await store.create(record)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
        try await super.tearDown()
    }

    private func makeTranscriber(
        engine: FakeMeetingEngine,
        tracks: [MeetingTrack] = [.you, .them],
        gate: DecodeGate = DecodeGate(),
        events: Collected<MeetingTranscriber.Event> = Collected()
    ) -> MeetingTranscriber {
        MeetingTranscriber(
            meetingID: record.id,
            tracks: tracks,
            store: store,
            engine: engine,
            mayDecode: { await gate.isOpen },
            retryDelay: .milliseconds(5),
            onEvent: { events.append($0) }
        )
    }

    private func writeAudio(_ samples: [Float], track: MeetingTrack) throws {
        let writer = try MeetingAudioFileWriter(url: store.audioURL(track, for: record.id))
        try writer.append(samples)
        try writer.close()
    }

    func testRecoveryDecodesBothTracksInTimeOrderAndDropsTheEcho() async throws {
        _ = try await store.update(record.id) { $0.callPlayedOnSpeakers = true }
        // Them speaks first; the microphone hears it, then the user answers.
        try writeAudio(silence(0.5) + tone(2.5, level: 0.05) + silence(0.5) + tone(2.5, level: 0.4) + silence(0.5), track: .you)
        try writeAudio(tone(2.5, level: 0.2) + silence(4), track: .them)
        let engine = FakeMeetingEngine(words: [0.2: "We ship on Friday.", 0.05: "we ship on friday", 0.4: "I will write the notes."])

        let transcript = try await makeTranscriber(engine: engine).recover()
        let stored = await store.segments(of: record.id)
        let decoded = await engine.decodedPeaks
        let purposes = await engine.purposes

        XCTAssertEqual(transcript.map(\.text), ["We ship on Friday.", "I will write the notes."])
        XCTAssertEqual(stored, transcript)
        XCTAssertEqual(decoded.map { ($0 * 100).rounded() / 100 }, [0.2, 0.05, 0.4], "earliest chunk first across both tracks; silent chunks are not decoded")
        XCTAssertEqual(Set(purposes), [.meeting])
    }

    func testRecoveryDecodesOnlyTheAudioAfterTheLastStoredSegment() async throws {
        try writeAudio(tone(2.5, level: 0.2) + silence(0.5) + tone(2.5, level: 0.4) + silence(0.5), track: .you)
        let first = MeetingSegment(id: UUID(), track: .you, audioStart: 0, audioEnd: samples(2.8), text: "Alpha.")
        try await store.appendSegment(first, to: record.id)
        let engine = FakeMeetingEngine(words: [0.2: "Alpha.", 0.4: "Bravo."])

        let transcript = try await makeTranscriber(engine: engine, tracks: [.you]).recover()
        let decoded = await engine.decodedPeaks

        XCTAssertEqual(transcript.map(\.text), ["Alpha.", "Bravo."])
        XCTAssertEqual(decoded.count, 1)
    }

    func testLiveAudioIsStoredAndReportedAsItDecodes() async throws {
        let events = Collected<MeetingTranscriber.Event>()
        let engine = FakeMeetingEngine(words: [0.3: "Morning, everyone."])
        let transcriber = makeTranscriber(engine: engine, tracks: [.you], events: events)
        await transcriber.start()

        let audio = tone(2.5) + silence(0.5)
        try writeAudio(audio, track: .you)
        transcriber.enqueue(.samples(.you, Array(audio[..<samples(1)]), position: 0))
        transcriber.enqueue(.samples(.you, Array(audio[samples(1)...]), position: samples(1)))
        let transcript = try await transcriber.finish()

        let segment = try XCTUnwrap(transcript.first)
        XCTAssertEqual(segment.text, "Morning, everyone.")
        XCTAssertEqual(segment.audioStart, 0)
        XCTAssertEqual(events.items, [.segment(segment), .decodedThrough(.you, samples(2.8)), .decodedThrough(.you, samples(3))])
    }

    func testNoChunkDecodesUntilDecodingIsAllowedAgain() async throws {
        let engine = FakeMeetingEngine(words: [0.3: "Hello."])
        let gate = DecodeGate()
        await gate.set(open: false)
        let transcriber = makeTranscriber(engine: engine, tracks: [.you], gate: gate)
        await transcriber.start()

        try writeAudio(tone(2.5) + silence(0.5), track: .you)
        transcriber.enqueue(.samples(.you, tone(2.5) + silence(0.5), position: 0))
        try await Task.sleep(for: .milliseconds(200))
        let callsWhileHeld = await engine.decodedPeaks.count
        await gate.set(open: true)
        await transcriber.wake()
        let transcript = try await transcriber.finish()

        XCTAssertEqual(callsWhileHeld, 0)
        XCTAssertEqual(transcript.map(\.text), ["Hello."])
    }

    func testAPauseEndsTheChunkInProgress() async throws {
        let engine = FakeMeetingEngine(words: [0.2: "Before the break.", 0.4: "After the break."])
        let transcriber = makeTranscriber(engine: engine, tracks: [.you])
        await transcriber.start()

        try writeAudio(tone(1, level: 0.2) + tone(1, level: 0.4), track: .you)
        transcriber.enqueue(.samples(.you, tone(1, level: 0.2), position: 0))
        transcriber.enqueue(.paused)
        transcriber.enqueue(.samples(.you, tone(1, level: 0.4), position: samples(1)))
        let transcript = try await transcriber.finish()

        XCTAssertEqual(transcript.map(\.text), ["Before the break.", "After the break."])
    }

    func testAFailedDecodeIsTriedAgainAndAChunkThatKeepsFailingIsSkipped() async throws {
        try writeAudio(tone(2.5, level: 0.2) + silence(0.5) + tone(2.5, level: 0.4) + silence(0.5), track: .you)
        let engine = FakeMeetingEngine(words: [0.2: "Alpha.", 0.4: "Bravo."])
        await engine.fail(level: 0.2, times: 2)
        await engine.fail(level: 0.4, times: 100)

        let transcript = try await makeTranscriber(engine: engine, tracks: [.you]).recover()
        let decoded = await engine.decodedPeaks.map { ($0 * 10).rounded() / 10 }

        XCTAssertEqual(transcript.map(\.text), ["Alpha."])
        XCTAssertEqual(decoded.filter { $0 == 0.2 }.count, 3)
        XCTAssertEqual(decoded.filter { $0 == 0.4 }.count, MeetingTranscriber.maximumAttempts)
    }
}

// MARK: - Fakes

private actor DecodeGate {
    private(set) var isOpen = true

    func set(open: Bool) {
        isOpen = open
    }
}

private struct FakeDecodeError: Error {}

/// Answers by the peak level of the audio, so a test can tell its chunks apart.
private actor FakeMeetingEngine: TranscriptionServiceProtocol {
    private(set) var decodedPeaks: [Float] = []
    private(set) var purposes: [TranscriptionPurpose] = []
    private let words: [Float: String]
    private var failures: [Float: Int] = [:]

    init(words: [Float: String]) {
        self.words = words
    }

    func fail(level: Float, times: Int) {
        failures[level] = times
    }

    func loadModel(config: RecognizerConfig) async throws {}

    func unloadModel() async {}

    func transcribe(
        samples: [Float],
        sampleRate: Int,
        purpose: TranscriptionPurpose,
        onProgress: @escaping @Sendable (TranscriptionProgress) -> Void
    ) async throws -> String {
        let peak = samples.map(abs).max() ?? 0
        decodedPeaks.append(peak)
        purposes.append(purpose)
        guard let level = words.keys.first(where: { abs($0 - peak) < 0.02 }) else { return "" }
        if let left = failures[level], left > 0 {
            failures[level] = left - 1
            throw FakeDecodeError()
        }
        return words[level] ?? ""
    }
}

private final class Collected<Element>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Element] = []

    func append(_ item: Element) {
        lock.lock()
        storage.append(item)
        lock.unlock()
    }

    var items: [Element] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
