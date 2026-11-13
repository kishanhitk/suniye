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
    private var summaryModel: GatedSummaryModel!
    private var clock: Date!
    private var noticeAnswer = true
    private var noticeCount = 0
    private var freeBytes: Int64 = 10_000_000_000

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
        summaryModel = GatedSummaryModel()
        clock = Date(timeIntervalSince1970: 1_800_000_000)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
        try await super.tearDown()
    }

    private func makeCoordinator() -> MeetingCoordinator {
        let environment = MeetingEnvironment(
            makeSources: { [unowned self] _, _ in [.you: you, .them: them] },
            confirmNotice: { [unowned self] in
                noticeCount += 1
                return noticeAnswer
            },
            freeDiskBytes: { [unowned self] in freeBytes },
            callPlaysOnSpeakers: { false },
            now: { [unowned self] in clock }
        )
        let coordinator = MeetingCoordinator(
            store: store,
            templates: MeetingTemplateStore(fileURL: root.appendingPathComponent("templates.json")),
            settingsStore: MeetingSettingsStore(userDefaults: defaults),
            engine: engine,
            environment: environment,
            canRecordCallAudio: true,
            summaryAvailability: { .ready(.localModel) },
            makeSummaryModel: { [unowned self] _ in summaryModel }
        )
        coordinator.host = host
        return coordinator
    }

    func testAMeetingAsksForTheNoticeOnceAndEndsWithItsSummary() async throws {
        let coordinator = makeCoordinator()
        coordinator.speechModelChanged(.parakeetV3)

        try await coordinator.startMeeting(source: .manual)
        let id = try XCTUnwrap(coordinator.live?.id)
        you.push(tone(2.5, level: 0.3) + silence(0.5))
        await coordinator.stop()
        let finished = await waitUntil { coordinator.record(id)?.status == .done }
        try await coordinator.startMeeting(source: .manual)

        XCTAssertTrue(finished)
        XCTAssertEqual(noticeCount, 1, "the notice shows before the first recording only")
        XCTAssertEqual(coordinator.record(id)?.title, "Release plan")
        XCTAssertEqual(coordinator.record(id)?.summaryProvider, .localModel)
        let summary = await store.summary(of: id)
        let audioLeft = await store.hasAudio(of: id)
        let segments = await store.segments(of: id)
        XCTAssertEqual(summary, "## Overview\nShip on Friday.")
        XCTAssertFalse(audioLeft, "the audio goes once the transcript is final")
        XCTAssertEqual(segments.map(\.text), [longSentence])
        XCTAssertGreaterThanOrEqual(host.idleCount, 1, "Magic Format can warm its prompt after the summary")
        await coordinator.stop()
    }

    func testACanceledNoticeOrTooLittleSpaceStartsNothing() async throws {
        let coordinator = makeCoordinator()
        noticeAnswer = false

        try await coordinator.startMeeting(source: .manual)
        let afterCancel = await store.loadAll()
        noticeAnswer = true
        freeBytes = 100_000_000
        do {
            try await coordinator.startMeeting(source: .manual)
            XCTFail("expected a refusal")
        } catch {
            XCTAssertEqual(error as? MeetingStartError, .notEnoughSpace)
        }

        XCTAssertNil(coordinator.live)
        XCTAssertTrue(afterCancel.isEmpty)
        XCTAssertEqual(you.startCount, 0)
    }

    func testADictationSilencesTheMicrophoneTrackAndHoldsDecoding() async throws {
        let coordinator = makeCoordinator()
        coordinator.speechModelChanged(.parakeetV3)
        try await coordinator.startMeeting(source: .manual)
        let id = try XCTUnwrap(coordinator.live?.id)

        coordinator.dictationChanged(active: true)
        you.push(tone(2.5, level: 0.3) + silence(0.5))
        them.push(tone(2.5, level: 0.5) + silence(0.5))
        try await Task.sleep(for: .milliseconds(200))
        let decodesDuringDictation = await engine.calls
        coordinator.dictationChanged(active: false)
        await coordinator.stop()
        let segments = await store.segments(of: id)

        XCTAssertEqual(decodesDuringDictation, 0)
        XCTAssertEqual(segments.map(\.track), [.them], "the dictated words are not meeting talk")
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

    func testAtLaunchARecordingThatAQuitLeftIsFinishedWithNoClick() async throws {
        let left = MeetingRecord(title: "Meeting", startedAt: clock, startSource: .manual, status: .recording, templateID: "general")
        try await store.create(left)
        let writer = try MeetingAudioFileWriter(url: store.audioURL(.you, for: left.id))
        try writer.append(tone(2.5, level: 0.3) + silence(0.5))
        try writer.close()
        let coordinator = makeCoordinator()
        coordinator.speechModelChanged(.parakeetV3)

        await coordinator.start()
        let finished = await waitUntil { coordinator.record(left.id)?.status == .done }

        XCTAssertTrue(finished)
        let segments = await store.segments(of: left.id)
        XCTAssertEqual(segments.map(\.text), [longSentence])
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
        let requests = await summaryModel.requests
        XCTAssertEqual(requests, 2)
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
        let rewritten = await waitUntil { await self.summaryModel.requests == 2 }
        let done = await waitUntil { coordinator.record(id)?.status == .done }

        XCTAssertTrue(rewritten)
        XCTAssertTrue(done)
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

    func testRecordAutomaticallyNeedsTheNoticeAndCancelKeepsAsk() async {
        let coordinator = makeCoordinator()
        noticeAnswer = false

        await coordinator.chooseCallStartAction(.recordAutomatically)
        let afterCancel = coordinator.settings
        noticeAnswer = true
        await coordinator.chooseCallStartAction(.recordAutomatically)

        XCTAssertEqual(afterCancel.callStartAction, .ask)
        XCTAssertEqual(coordinator.settings.callStartAction, .recordAutomatically)
        XCTAssertTrue(coordinator.settings.noticeAccepted)
        XCTAssertEqual(noticeCount, 2)
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
        defaults.set(Data(#"{"noticeAccepted":true}"#.utf8), forKey: "settings")
        let store = MeetingSettingsStore(userDefaults: defaults, key: "settings")

        var loaded = store.load()
        loaded.callStartAction = .recordAutomatically
        store.save(loaded)
        let reloaded = store.load()

        XCTAssertTrue(reloaded.noticeAccepted)
        XCTAssertEqual(reloaded.templateID, MeetingTemplate.general.id)
        XCTAssertEqual(reloaded.callStartAction, .recordAutomatically)
    }
}

// MARK: - Fakes

private final class PushSource: MeetingAudioSource, @unchecked Sendable {
    var onSamples: (([Float]) -> Void)?
    var onEvent: ((MeetingAudioSourceEvent) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() throws {
        startCount += 1
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
}

/// Answers by the audio's peak level.
private actor WordEngine: TranscriptionServiceProtocol {
    private(set) var calls = 0
    private let words: [Float: String]

    init(words: [Float: String]) {
        self.words = words
    }

    func loadModel(config: RecognizerConfig) async throws {}

    func unloadModel() async {}

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

/// Answers one summary; while closed, a request waits until it opens or its
/// task is canceled.
private actor GatedSummaryModel: MeetingSummaryModel {
    nonisolated let provider = MeetingSummaryProvider.localModel
    private(set) var requests = 0
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
        requests += 1
        waiting = true
        defer { waiting = false }
        while !isOpen {
            try await Task.sleep(for: .milliseconds(5))
        }
        return "Release plan\n## Overview\nShip on Friday."
    }
}
