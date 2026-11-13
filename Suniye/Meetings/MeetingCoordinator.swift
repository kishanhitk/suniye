import Foundation

/// A call app that holds the microphone, as call detection reports it.
struct MeetingCallApp: Equatable, Sendable {
    let name: String
    let bundleID: String
}

enum MeetingStartError: LocalizedError, Equatable {
    case alreadyRecording
    case notEnoughSpace
    case noMicrophoneAccess
    case couldNotStart(String)

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "A meeting is already recording."
        case .notEnoughSpace:
            return "Not enough free space to record a meeting."
        case .noMicrophoneAccess:
            return "Suniye needs microphone access to record a meeting."
        case let .couldNotStart(reason):
            return reason
        }
    }
}

/// Something the user should see while the meeting page is not on screen.
enum MeetingNotice: Equatable {
    case callAudioNeverHeard
    case callAudioStopped(since: TimeInterval)
    case microphoneChanged(String)
    case trackFailed(MeetingTrack)
    case stoppedByDiskFull
    case summaryReady(UUID)
}

/// The meeting that records now, as the meeting page and the pill show it.
@MainActor
@Observable
final class MeetingSession {
    enum CallAudioProblem: Equatable {
        /// No sound came from the call yet, which often means that the system
        /// audio permission is off.
        case neverHeard
        /// The call had sound, then went silent.
        case stopped
    }

    let hasCallTrack: Bool
    fileprivate(set) var record: MeetingRecord
    fileprivate(set) var youLevel: Float = 0
    fileprivate(set) var themLevel: Float = 0
    fileprivate(set) var segments: [MeetingSegment] = []
    /// Every call chunk before this sample position is decoded.
    fileprivate(set) var callDecodedThrough = 0
    fileprivate(set) var callAudioProblem: CallAudioProblem?
    /// Recorded time when the call went silent, for "No sound since 16:30".
    fileprivate(set) var callSilentSince: TimeInterval?
    fileprivate(set) var failedTracks: [MeetingTrack: String] = [:]
    /// The new microphone, for a few seconds after the device changed.
    fileprivate(set) var changedInput: String?

    @ObservationIgnored fileprivate let recorder: MeetingRecorder
    @ObservationIgnored fileprivate let transcriber: MeetingTranscriber

    fileprivate init(record: MeetingRecord, recorder: MeetingRecorder, transcriber: MeetingTranscriber) {
        self.record = record
        self.recorder = recorder
        self.transcriber = transcriber
        hasCallTrack = recorder.tracks.contains(.them)
    }

    var id: UUID {
        record.id
    }

    var isPaused: Bool {
        record.status == .paused
    }

    /// The lines that the live transcript shows.
    var visibleSegments: [MeetingSegment] {
        MeetingTranscript.live(
            segments,
            callDecodedThrough: hasCallTrack ? callDecodedThrough : nil,
            callPlayedOnSpeakers: record.callPlayedOnSpeakers
        )
    }

    /// Recorded time: the wall clock since the start, without the pauses.
    func elapsed(at date: Date) -> TimeInterval {
        let wall = date.timeIntervalSince(record.startedAt)
        let paused = record.pauses.reduce(0) { total, pause in
            total + ((pause.end ?? wall) - pause.start)
        }
        return max(0, wall - paused)
    }
}

/// Meetings for the whole app: the list, the meeting that records now, the
/// transcripts that are being finished, and the summaries.
@MainActor
@Observable
final class MeetingCoordinator {
    /// Recording needs at least this much free space: two tracks for the
    /// 4-hour limit take about 1 GB.
    static let minimumFreeBytes: Int64 = 1_000_000_000
    static let changedInputSeconds: Duration = .seconds(5)

    /// Newest first.
    private(set) var meetings: [MeetingRecord] = []
    private(set) var live: MeetingSession? {
        didSet {
            if oldValue !== live {
                onLiveChange?(live)
            }
        }
    }
    /// Meetings whose transcript is being finished now.
    private(set) var finishing: Set<UUID> = []
    /// A meeting that a disk write error stopped, for its banner.
    private(set) var stoppedByWriteError: UUID?
    /// The meeting that the Meetings section shows; nil shows the list.
    var openMeetingID: UUID?
    /// Set when something outside the window asks to show a meeting.
    private(set) var pendingShow = false
    /// The meeting whose page is on screen, so a notice does not repeat it.
    var pageOnScreen: UUID?
    private(set) var settings: MeetingSettings
    let canRecordCallAudio: Bool
    @ObservationIgnored weak var host: MeetingHost?
    /// Called when a meeting starts recording (with it) and when it stops (nil).
    @ObservationIgnored var onLiveChange: ((MeetingSession?) -> Void)?
    @ObservationIgnored var onNotice: ((MeetingNotice) -> Void)?
    @ObservationIgnored let summaries: MeetingSummaries
    @ObservationIgnored let store: MeetingStore
    @ObservationIgnored let templates: MeetingTemplateStore

    @ObservationIgnored private let settingsStore: MeetingSettingsStore
    @ObservationIgnored private let engine: TranscriptionServiceProtocol
    @ObservationIgnored private let environment: MeetingEnvironment
    @ObservationIgnored private var transcribers: [UUID: MeetingTranscriber] = [:]
    @ObservationIgnored private var dictating = false
    @ObservationIgnored private var loadedModel: ASRModelID?
    @ObservationIgnored private var listTexts: [UUID: MeetingListText] = [:]
    @ObservationIgnored private var outputCheck: Task<Void, Never>?
    @ObservationIgnored private var changedInputReset: Task<Void, Never>?

    init(
        store: MeetingStore,
        templates: MeetingTemplateStore,
        settingsStore: MeetingSettingsStore,
        engine: TranscriptionServiceProtocol,
        environment: MeetingEnvironment,
        canRecordCallAudio: Bool,
        summaryAvailability: @escaping () -> MeetingSummaryAvailability,
        makeSummaryModel: @escaping (MeetingSummaryProvider) -> MeetingSummaryModel?
    ) {
        self.store = store
        self.templates = templates
        self.settingsStore = settingsStore
        self.engine = engine
        self.environment = environment
        self.canRecordCallAudio = canRecordCallAudio
        settings = settingsStore.load()
        summaries = MeetingSummaries(
            store: store,
            templates: templates,
            availability: summaryAvailability,
            makeModel: makeSummaryModel
        )
        summaries.onFinished = { [weak self] record in
            self?.apply(record)
            if record.status == .done {
                self?.onNotice?(.summaryReady(record.id))
            }
        }
        summaries.onModelIdle = { [weak self] in self?.host?.meetingSummaryModelIsIdle() }
    }

    /// At launch: finish the transcripts that a quit or a crash left, and
    /// queue the summaries that are not written yet.
    func start() async {
        let recovered = await store.recoverInterruptedMeetings()
        meetings = await store.loadAll()
        for record in recovered where record.status == .finishing {
            finishTranscript(record.id)
        }
        for record in meetings where record.status == .summarizing {
            summaries.enqueue(record.id)
        }
    }

    // MARK: - Navigation

    /// Shows a meeting's page, or the list for nil, in the main window.
    func show(_ id: UUID?) {
        openMeetingID = id
        pendingShow = true
    }

    /// True once for each `show(_:)`, so the window switches to Meetings then.
    func takeShowRequest() -> Bool {
        defer { pendingShow = false }
        return pendingShow
    }

    /// The summary, notes and transcript of a meeting, read from disk once.
    func listText(for id: UUID) async -> MeetingListText {
        if let cached = listTexts[id] {
            return cached
        }
        let text = MeetingListText(
            summary: await store.summary(of: id),
            notes: await store.notes(of: id),
            transcript: await store.segments(of: id).map(\.text)
        )
        listTexts[id] = text
        return text
    }

    // MARK: - Settings

    func updateSettings(_ change: (inout MeetingSettings) -> Void) {
        change(&settings)
        settingsStore.save(settings)
    }

    /// Record Automatically shows the recording notice first, because no
    /// later recording asks; Cancel keeps the earlier choice.
    func chooseCallStartAction(_ action: MeetingCallStartAction) async {
        if action == .recordAutomatically, settings.callStartAction != .recordAutomatically {
            guard await environment.confirmNotice() else { return }
            updateSettings { $0.noticeAccepted = true }
        }
        updateSettings { $0.callStartAction = action }
    }

    // MARK: - Recording

    func startMeeting(source: MeetingStartSource, callApp: MeetingCallApp? = nil) async throws {
        guard live == nil else { throw MeetingStartError.alreadyRecording }
        if !settings.noticeAccepted {
            guard await environment.confirmNotice() else { return }
            updateSettings { $0.noticeAccepted = true }
        }
        if let free = environment.freeDiskBytes(), free < Self.minimumFreeBytes {
            throw MeetingStartError.notEnoughSpace
        }
        guard await host?.requestMeetingMicrophoneAccess() == true else {
            throw MeetingStartError.noMicrophoneAccess
        }

        let record = MeetingRecord(
            title: callApp.map { "\($0.name) call" } ?? "Meeting",
            startedAt: environment.now(),
            callAppName: callApp?.name,
            callAppBundleID: callApp?.bundleID,
            startSource: source,
            templateID: settings.templateID,
            callPlayedOnSpeakers: environment.callPlaysOnSpeakers()
        )
        try await store.create(record)
        let recorder = MeetingRecorder(
            sources: environment.makeSources(canRecordCallAudio, host?.meetingInputDeviceID),
            fileURLs: Dictionary(uniqueKeysWithValues: MeetingTrack.allCases.map { ($0, store.audioURL($0, for: record.id)) })
        )
        let transcriber = makeTranscriber(for: record.id, tracks: recorder.tracks)
        let session = MeetingSession(record: record, recorder: recorder, transcriber: transcriber)
        // The recorder's queue keeps its events in order, and so does the main queue.
        recorder.onOutput = { transcriber.enqueue($0) }
        recorder.onEvent = { [weak self] event in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.handle(event, from: session) } }
        }
        do {
            try recorder.start()
        } catch {
            transcribers[record.id] = nil
            try? await store.delete(record.id)
            throw MeetingStartError.couldNotStart(error.localizedDescription)
        }
        await transcriber.start()
        recorder.setMicrophoneMuted(dictating)
        live = session
        meetings.insert(record, at: 0)
        watchOutputRoute(of: session)
        AppLogger.shared.log(.info, "meeting started id=\(record.id.uuidString) source=\(source.rawValue) tracks=\(recorder.tracks.map(\.rawValue).joined(separator: ","))")
    }

    func pause() async {
        guard let session = live, !session.isPaused else { return }
        session.recorder.pause()
        let now = wallSeconds(of: session)
        await update(session.id) {
            $0.pauses.append(MeetingPause(start: now))
            $0.status = .paused
        }
    }

    /// Stays paused when no track starts again.
    func resume() async throws {
        guard let session = live, session.isPaused else { return }
        try session.recorder.resume()
        let now = wallSeconds(of: session)
        await update(session.id) {
            $0.pauses[$0.pauses.count - 1].end = now
            $0.status = .recording
        }
    }

    /// Stops the recording, then finishes the transcript and queues the summary.
    func stop() async {
        guard let session = live else { return }
        session.recorder.stop()
        outputCheck?.cancel()
        outputCheck = nil
        let now = wallSeconds(of: session)
        await update(session.id) {
            if let last = $0.pauses.indices.last, $0.pauses[last].end == nil {
                $0.pauses[last].end = now
            }
            $0.endedAt = $0.startedAt.addingTimeInterval(now)
            $0.status = .finishing
        }
        live = nil
        AppLogger.shared.log(.info, "meeting stopped id=\(session.id.uuidString)")
        await finish(session.id, transcriber: session.transcriber) { try await $0.finish() }
    }

    /// A call track that cannot start again shows as a failed track.
    func restartCallAudio() {
        guard let session = live else { return }
        do {
            try session.recorder.restartCallAudio()
            session.callAudioProblem = nil
            session.callSilentSince = nil
        } catch {
            AppLogger.shared.log(.error, "meeting call audio restart failed id=\(session.id.uuidString) error=\(error.localizedDescription)")
            session.failedTracks[.them] = error.localizedDescription
        }
    }

    /// Finishes the transcript of a meeting from its audio files: after a
    /// quit or a crash, or when the user asks again after a failed finish.
    func finishTranscript(_ id: UUID) {
        guard transcribers[id] == nil else { return }
        let tracks = MeetingTrack.allCases.filter { FileManager.default.fileExists(atPath: store.audioURL($0, for: id).path) }
        let transcriber = makeTranscriber(for: id, tracks: tracks)
        Task {
            await finish(id, transcriber: transcriber) { try await $0.recover() }
        }
    }

    // MARK: - The finished meeting

    func rename(_ id: UUID, to title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await update(id) {
            $0.title = trimmed
            $0.titleSource = .user
        }
    }

    func saveNotes(_ notes: String, for id: UUID) async {
        listTexts[id] = nil
        do {
            try await store.saveNotes(notes, for: id)
        } catch {
            AppLogger.shared.log(.error, "meeting notes not saved id=\(id.uuidString) error=\(error.localizedDescription)")
        }
    }

    /// Writes the summary again, with `templateID` when it is given.
    func regenerate(_ id: UUID, templateID: String? = nil) async {
        guard live?.id != id, !finishing.contains(id) else { return }
        if let templateID {
            updateSettings { $0.templateID = templateID }
        }
        await update(id) {
            if let templateID {
                $0.templateID = templateID
            }
            $0.status = .summarizing
            $0.summaryFailure = nil
        }
        summaries.enqueue(id)
    }

    /// A meeting that records or whose transcript is being finished stays.
    func delete(_ id: UUID) async throws {
        guard live?.id != id, !finishing.contains(id) else { return }
        summaries.remove(id)
        try await store.delete(id)
        meetings.removeAll { $0.id == id }
    }

    func record(_ id: UUID) -> MeetingRecord? {
        meetings.first { $0.id == id }
    }

    // MARK: - Dictation and the speech model

    /// From the start of a dictation to its end, the meeting's microphone
    /// track gets silence (the dictated words are not meeting talk), no
    /// meeting chunk starts decoding, and the summary waits.
    func dictationChanged(active: Bool) {
        dictating = active
        live?.recorder.setMicrophoneMuted(active)
        summaries.hold(active)
        wakeTranscribers()
    }

    /// Meeting chunks decode only while a speech model is loaded.
    func speechModelChanged(_ model: ASRModelID?) {
        loadedModel = model
        wakeTranscribers()
    }

    private var speechEngineFree: Bool {
        loadedModel != nil && !dictating
    }

    private func wakeTranscribers() {
        guard speechEngineFree else { return }
        for transcriber in transcribers.values {
            Task { await transcriber.wake() }
        }
    }

    // MARK: - Private

    private func makeTranscriber(for id: UUID, tracks: [MeetingTrack]) -> MeetingTranscriber {
        let transcriber = MeetingTranscriber(
            meetingID: id,
            tracks: tracks,
            store: store,
            engine: engine,
            engineName: { [weak self] in await self?.loadedModel?.rawValue ?? "" },
            mayDecode: { [weak self] in await self?.speechEngineFree ?? false },
            onEvent: { [weak self] event in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.handle(event, of: id) } }
            }
        )
        transcribers[id] = transcriber
        return transcriber
    }

    private func finish(
        _ id: UUID,
        transcriber: MeetingTranscriber,
        run: (MeetingTranscriber) async throws -> [MeetingSegment]
    ) async {
        finishing.insert(id)
        defer {
            finishing.remove(id)
            transcribers[id] = nil
        }
        do {
            _ = try await run(transcriber)
            await store.deleteAudio(of: id)
            await update(id) { $0.status = .summarizing }
            summaries.enqueue(id)
        } catch {
            AppLogger.shared.log(.error, "meeting transcript not finished id=\(id.uuidString) error=\(error.localizedDescription)")
            await update(id) { $0.status = .interrupted }
        }
    }

    private func handle(_ event: MeetingRecorderEvent, from session: MeetingSession) {
        guard live === session else { return }
        switch event {
        case let .levels(you, them):
            session.youLevel = you
            session.themLevel = them
        case let .callAudioSilent(heardBefore):
            // A meeting in the room has no call, so its silent call track is
            // no problem.
            guard session.record.callAppBundleID != nil else { return }
            let since = max(0, session.elapsed(at: environment.now()) - MeetingRecorder.callSilenceLimit)
            session.callAudioProblem = heardBefore ? .stopped : .neverHeard
            session.callSilentSince = since
            onNotice?(heardBefore ? .callAudioStopped(since: since) : .callAudioNeverHeard)
        case .callAudioReturned:
            session.callAudioProblem = nil
            session.callSilentSince = nil
        case let .inputChanged(name):
            session.changedInput = name
            onNotice?(.microphoneChanged(name))
            changedInputReset?.cancel()
            changedInputReset = Task { [weak session] in
                try? await Task.sleep(for: Self.changedInputSeconds)
                guard !Task.isCancelled else { return }
                session?.changedInput = nil
            }
        case let .trackFailed(track, message):
            session.failedTracks[track] = message
            onNotice?(.trackFailed(track))
        case let .storageFailed(message):
            AppLogger.shared.log(.error, "meeting stopped by a write error id=\(session.id.uuidString) error=\(message)")
            stoppedByWriteError = session.id
            onNotice?(.stoppedByDiskFull)
            Task { await stop() }
        }
    }

    private func handle(_ event: MeetingTranscriber.Event, of id: UUID) {
        guard let session = live, session.id == id else { return }
        switch event {
        case let .segment(segment):
            session.segments.append(segment)
        case let .decodedThrough(track, position):
            if track == .them {
                session.callDecodedThrough = position
            }
        }
    }

    /// The echo filter needs to know whether the call ever played on speakers.
    private func watchOutputRoute(of session: MeetingSession) {
        outputCheck?.cancel()
        outputCheck = Task { [weak self, weak session] in
            while !Task.isCancelled {
                guard let self, let session, !session.record.callPlayedOnSpeakers else { return }
                if self.environment.callPlaysOnSpeakers() {
                    await self.update(session.id) { $0.callPlayedOnSpeakers = true }
                    return
                }
                try? await Task.sleep(for: self.environment.outputCheckInterval)
            }
        }
    }

    private func wallSeconds(of session: MeetingSession) -> Double {
        environment.now().timeIntervalSince(session.record.startedAt)
    }

    private func update(_ id: UUID, _ change: @escaping (inout MeetingRecord) -> Void) async {
        do {
            apply(try await store.update(id, change))
        } catch {
            AppLogger.shared.log(.error, "meeting not saved id=\(id.uuidString) error=\(error.localizedDescription)")
        }
    }

    /// Puts a saved record into the list and the live meeting.
    private func apply(_ record: MeetingRecord) {
        listTexts[record.id] = nil
        if let index = meetings.firstIndex(where: { $0.id == record.id }) {
            meetings[index] = record
        }
        if let live, live.id == record.id {
            live.record = record
        }
    }
}
