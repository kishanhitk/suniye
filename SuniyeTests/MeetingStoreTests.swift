import XCTest
@testable import Suniye

final class MeetingStoreTests: XCTestCase {
    private var root: URL!
    private var store: MeetingStore!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingStoreTests-\(UUID().uuidString)", isDirectory: true)
        store = MeetingStore(rootDirectory: root)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func makeRecord(startedAt: Date = Date(timeIntervalSince1970: 1_800_000_000), status: MeetingStatus = .recording) -> MeetingRecord {
        MeetingRecord(title: "Zoom call", startedAt: startedAt, startSource: .manual, status: status, templateID: "general")
    }

    func testRecordsRoundTripNewestFirst() async throws {
        let older = makeRecord(startedAt: Date(timeIntervalSince1970: 1_800_000_000), status: .done)
        var newer = makeRecord(startedAt: Date(timeIntervalSince1970: 1_800_003_600))
        newer.callAppName = "Zoom"
        try await store.create(older)
        try await store.create(newer)

        let loaded = await store.loadAll()

        XCTAssertEqual(loaded.map(\.id), [newer.id, older.id])
        XCTAssertEqual(loaded.first, newer)
    }

    func testSaveOfUnknownMeetingFails() async {
        do {
            try await store.save(makeRecord())
            XCTFail("expected unknownMeeting")
        } catch {
            XCTAssertTrue(error is MeetingStore.StoreError)
        }
    }

    func testSegmentsAppendInTimeOrderAndSkipATornLine() async throws {
        let record = makeRecord()
        try await store.create(record)
        let later = MeetingSegment(id: UUID(), track: .them, start: 11, end: 15.2, text: "QA found one crash.", engine: "parakeetV3")
        let earlier = MeetingSegment(id: UUID(), track: .you, start: 4, end: 9, text: "The build is ready.", engine: "parakeetV3")
        try await store.appendSegment(later, to: record.id)
        try await store.appendSegment(earlier, to: record.id)

        let segmentsFile = store.folder(for: record.id).appendingPathComponent("segments.jsonl")
        let handle = try FileHandle(forWritingTo: segmentsFile)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"id\":\"cut-by-a-cra".utf8))
        try handle.close()

        let segments = await store.segments(of: record.id)

        XCTAssertEqual(segments, [earlier, later])
    }

    func testReplaceSegmentsRewritesTheTranscript() async throws {
        let record = makeRecord()
        try await store.create(record)
        try await store.appendSegment(MeetingSegment(id: UUID(), track: .you, start: 1, end: 2, text: "echo", engine: "e"), to: record.id)
        let kept = MeetingSegment(id: UUID(), track: .them, start: 1, end: 2, text: "Hello.", engine: "e")

        try await store.replaceSegments([kept], of: record.id)

        let segments = await store.segments(of: record.id)
        XCTAssertEqual(segments, [kept])
    }

    func testNotesAndSummaryRoundTrip() async throws {
        let record = makeRecord()
        try await store.create(record)

        let emptyNotes = await store.notes(of: record.id)
        let missingSummary = await store.summary(of: record.id)
        XCTAssertEqual(emptyNotes, "")
        XCTAssertNil(missingSummary)

        try await store.saveNotes("Release\n- Ship Thursday", for: record.id)
        try await store.saveSummary("## Summary\nShip Thursday.", for: record.id)

        let notes = await store.notes(of: record.id)
        let summary = await store.summary(of: record.id)
        XCTAssertEqual(notes, "Release\n- Ship Thursday")
        XCTAssertEqual(summary, "## Summary\nShip Thursday.")
    }

    func testDeleteAudioKeepsTheTranscriptAndDeleteRemovesTheMeeting() async throws {
        let record = makeRecord()
        try await store.create(record)
        let writer = try MeetingAudioFileWriter(url: store.audioURL(.you, for: record.id))
        try writer.append([0.1, 0.2])
        try writer.close()
        try await store.saveNotes("notes", for: record.id)

        let hadAudio = await store.hasAudio(of: record.id)
        await store.deleteAudio(of: record.id)
        let hasAudio = await store.hasAudio(of: record.id)
        let notes = await store.notes(of: record.id)
        XCTAssertTrue(hadAudio)
        XCTAssertFalse(hasAudio)
        XCTAssertEqual(notes, "notes")

        try await store.delete(record.id)
        let remaining = await store.loadAll()
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.folder(for: record.id).path))
    }

    func testRecoveryMarksUnfinishedMeetingsAndRepairsTheirAudio() async throws {
        var paused = makeRecord(status: .paused)
        paused.pauses = [MeetingPause(start: 30, end: 40), MeetingPause(start: 90, end: nil)]
        let done = makeRecord(startedAt: Date(timeIntervalSince1970: 1_700_000_000), status: .done)
        try await store.create(paused)
        try await store.create(done)

        let audio = store.audioURL(.them, for: paused.id)
        let writer = try MeetingAudioFileWriter(url: audio, headerRefreshSeconds: 3600)
        try writer.append(Array(repeating: 0.25, count: 16_000))
        // No close: the header still says zero samples, as after a crash.
        let samplesBeforeRepair = try MeetingAudioFileReader.samples(at: audio).count

        let recovered = await store.recoverInterruptedMeetings()

        XCTAssertEqual(recovered.map(\.id), [paused.id])
        XCTAssertEqual(recovered.first?.status, .interrupted)
        XCTAssertEqual(recovered.first?.pauses, [MeetingPause(start: 30, end: 40)])
        let reloaded = await store.record(done.id)
        XCTAssertEqual(reloaded?.status, .done)
        XCTAssertEqual(samplesBeforeRepair, 16_000, "the reader uses the file length, not the header")
        let header = try Data(contentsOf: audio).subdata(in: 40 ..< 44)
        XCTAssertEqual(header.withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian, 32_000)
    }
}

final class MeetingAudioFileTests: XCTestCase {
    private var url: URL!

    override func setUp() {
        super.setUp()
        url = FileManager.default.temporaryDirectory.appendingPathComponent("meeting-audio-\(UUID().uuidString).wav")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
        super.tearDown()
    }

    func testWrittenSamplesReadBackAsSixteenBitWithClipping() throws {
        let writer = try MeetingAudioFileWriter(url: url)
        try writer.append([0, 0.5, -0.5, 1.5, -2])
        try writer.close()

        let samples = try MeetingAudioFileReader.samples(at: url)

        XCTAssertEqual(samples.count, 5)
        XCTAssertEqual(samples[1], 0.5, accuracy: 0.001)
        XCTAssertEqual(samples[2], -0.5, accuracy: 0.001)
        XCTAssertEqual(samples[3], 1, accuracy: 0.001)
        XCTAssertEqual(samples[4], -1, accuracy: 0.001)
        XCTAssertEqual(try MeetingAudioFileReader.sampleCount(at: url), 5)
    }

    func testRangeReadsOnlyThatPartAndStopsAtTheEnd() throws {
        let writer = try MeetingAudioFileWriter(url: url)
        try writer.append((0 ..< 100).map { Float($0) / 1000 })
        try writer.close()

        let middle = try MeetingAudioFileReader.samples(at: url, range: 10 ..< 13)
        let pastEnd = try MeetingAudioFileReader.samples(at: url, range: 95 ..< 400)

        XCTAssertEqual(middle.count, 3)
        XCTAssertEqual(middle[0], 0.010, accuracy: 0.0002)
        XCTAssertEqual(pastEnd.count, 5)
    }

    func testHeaderIsRefreshedWhileWritingSoACrashLosesLittleAudio() throws {
        let writer = try MeetingAudioFileWriter(url: url, headerRefreshSeconds: 1)
        try writer.append(Array(repeating: 0.1, count: 16_000))
        try writer.append(Array(repeating: 0.1, count: 8_000))

        let header = try Data(contentsOf: url).subdata(in: 40 ..< 44)
        let dataBytes = header.withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian

        XCTAssertEqual(dataBytes, 32_000, "the header covers the first full second; the last half second waits for the next refresh")
    }

    func testReaderRejectsAFileThatIsNotAWave() throws {
        try Data("hello".utf8).write(to: url)

        XCTAssertThrowsError(try MeetingAudioFileReader.samples(at: url))
        XCTAssertThrowsError(try MeetingAudioFileWriter.repairHeader(at: url))
    }
}

final class MeetingTimelineTests: XCTestCase {
    func testAudioAfterAPauseMapsLaterOnTheWallClock() {
        let timeline = MeetingTimeline(pauses: [
            MeetingPause(start: 60, end: 90),
            MeetingPause(start: 200, end: 210),
        ])

        XCTAssertEqual(timeline.wallSeconds(forAudioSeconds: 10), 10)
        XCTAssertEqual(timeline.wallSeconds(forAudioSeconds: 60), 90)
        XCTAssertEqual(timeline.wallSeconds(forAudioSeconds: 100), 130)
        XCTAssertEqual(timeline.wallSeconds(forAudioSeconds: 170), 200 + 10)
    }

    func testAnOpenPauseMovesNothing() {
        let timeline = MeetingTimeline(pauses: [MeetingPause(start: 60, end: nil)])

        XCTAssertEqual(timeline.wallSeconds(forAudioSeconds: 59), 59)
    }
}
