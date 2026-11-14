import Foundation
import SuniyeAnalytics

/// The card about a call at the top right of the screen.
enum MeetingCallCard: Equatable {
    /// Asks to record the call. It closes by itself after a while.
    case offer(MeetingCallApp)
    /// A recording that started by itself. Cancel deletes it until
    /// `cancelEndsAt`.
    case startedAutomatically(MeetingCallApp, cancelEndsAt: Date)
    /// The call of the recording ended at `endedAt`: its app released the
    /// microphone, or, when `silent`, played no sound. A recording that
    /// started by itself stops at `stopsAt` and keeps nothing after
    /// `endedAt`. A recording that the user started has no `stopsAt`: it goes
    /// on until the user answers.
    case callEnded(MeetingCallApp, silent: Bool, endedAt: Date, stopsAt: Date?)

    struct Durations {
        var offer: TimeInterval = 20
        var cancel: TimeInterval = 5
        var stop: TimeInterval = 30
    }
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

/// A write error that stopped a recording, for the meeting page's banner.
struct MeetingWriteFailure: Equatable {
    let meetingID: UUID
    let outOfSpace: Bool
}

/// Something that happened to a meeting, for a toast.
enum MeetingNotice: Equatable {
    case callAudioNeverHeard
    case callAudioStopped
    case microphoneChanged(String)
    case trackFailed(MeetingTrack)
    /// `after` is the limit that stopped the recording.
    case stoppedAtTimeLimit(UUID, after: TimeInterval)
    case stoppedWithoutSpeech(UUID, after: TimeInterval)
    case stoppedByDiskFull(UUID)
    case stoppedByWriteError(UUID)
    case summaryReady(UUID)
    case transcribedAgain(UUID)
    /// Transcribe Again failed, and the transcript did not change.
    case notTranscribedAgain(UUID)
}

/// A transcript pass of one meeting, from the moment it is asked for until it
/// ends.
struct MeetingTranscriptPass: Equatable {
    enum Kind: Equatable {
        /// The transcript after the recording, or after Finish Transcript.
        case first
        /// Transcribe Again: a draft that replaces a final transcript.
        case again
    }

    let kind: Kind
    /// The pass waits until the passes asked before it end.
    var waiting: Bool
    /// Nil until the pass reports its first step.
    var progress: MeetingTranscriptProgress?
}

/// The meeting that records now, as the meeting page and the pill show it.
@MainActor
@Observable
final class MeetingSession {
    enum CallAudioProblem: Equatable {
        /// No sound came from the call yet, which often means that the system
        /// audio permission is off.
        case neverHeard
        /// The call had sound, then went silent at `since`, in recorded time.
        case stopped(since: TimeInterval)
    }

    fileprivate(set) var record: MeetingRecord
    /// How the recording started: one that started by itself also stops by
    /// itself when its call ends.
    let source: MeetingSource
    fileprivate(set) var youLevel: Float = 0
    fileprivate(set) var themLevel: Float = 0
    fileprivate(set) var callAudioProblem: CallAudioProblem?
    fileprivate(set) var failedTracks: [MeetingTrack: String] = [:]
    /// The new microphone, for a few seconds after the device changed.
    fileprivate(set) var changedInput: String?

    @ObservationIgnored fileprivate let recorder: MeetingRecorder
    @ObservationIgnored fileprivate let speech: MeetingSpeechWatch
    /// Set by the first stop, so that a second one does nothing.
    @ObservationIgnored fileprivate var isStopping = false

    fileprivate init(record: MeetingRecord, source: MeetingSource, recorder: MeetingRecorder, speech: MeetingSpeechWatch) {
        self.record = record
        self.source = source
        self.recorder = recorder
        self.speech = speech
    }

    var id: UUID {
        record.id
    }

    var hasCallTrack: Bool {
        record.hasCallTrack
    }

    var isPaused: Bool {
        record.status == .paused
    }

    /// No sound comes from the call, or a track failed.
    var hasTrackProblem: Bool {
        callAudioProblem != nil || !failedTracks.isEmpty
    }

    fileprivate var workingTracks: [MeetingTrack] {
        recorder.tracks.filter { failedTracks[$0] == nil }
    }

    /// Recorded time: the wall clock since the start, without the pauses.
    func elapsed(at date: Date) -> TimeInterval {
        MeetingTimeline(pauses: record.pauses).audioSeconds(forWallSeconds: date.timeIntervalSince(record.startedAt))
    }
}

/// Meetings for the whole app: the list, the meeting that records now, the
/// transcripts that are written after a recording, and the summaries.
@MainActor
@Observable
final class MeetingCoordinator {
    /// Recording needs at least this much free space: two tracks for the
    /// 4-hour limit take about 1 GB.
    static let minimumFreeBytes: Int64 = 1_000_000_000
    /// Recorded time after which a recording stops.
    static let recordingLimit: TimeInterval = 4 * 60 * 60
    static let changedInputSeconds: Duration = .seconds(5)

    /// Newest first.
    private(set) var meetings: [MeetingRecord] = []
    private(set) var live: MeetingSession? {
        didSet {
            if oldValue !== live {
                onLiveChange?(live)
                updateCallDetection()
                blockPlayback()
            }
        }
    }
    /// A meeting that a disk write error stopped, for its banner.
    private(set) var writeFailure: MeetingWriteFailure?
    /// The transcript passes that wait or run, by meeting. One runs at a
    /// time, in the order they were asked for.
    private(set) var transcriptPasses: [UUID: MeetingTranscriptPass] = [:]
    /// The meetings whose audio is on the Mac.
    private(set) var audioOnMac: Set<UUID> = []
    /// Goes up each time a meeting, its notes or its transcript change, so a
    /// list-text read that began before does not cache, and the list reads
    /// its text again.
    private(set) var listTextRevision = 0
    /// The meeting that the Meetings section shows; nil shows the list.
    var openMeetingID: UUID?
    /// The meeting whose page is on screen, so a notice does not repeat it.
    var pageOnScreen: UUID?
    private(set) var settings: MeetingSettings
    @ObservationIgnored private(set) var callCard: MeetingCallCard? {
        didSet {
            if oldValue != callCard {
                onCallCardChange?(callCard)
            }
        }
    }
    @ObservationIgnored weak var host: MeetingHost?
    /// Called when a meeting starts recording (with it) and when it stops (nil).
    @ObservationIgnored var onLiveChange: ((MeetingSession?) -> Void)?
    @ObservationIgnored var onCallCardChange: ((MeetingCallCard?) -> Void)?
    @ObservationIgnored var onNotice: ((MeetingNotice) -> Void)?
    @ObservationIgnored let summaries: MeetingSummaries
    @ObservationIgnored let store: MeetingStore
    /// The text that the meeting page saves; a quit waits for it.
    @ObservationIgnored let textSaves = MeetingTextSaves()
    @ObservationIgnored let playback: MeetingPlayback
    @ObservationIgnored let templates: MeetingTemplateStore

    @ObservationIgnored private let settingsStore: MeetingSettingsStore
    /// The dictation engine.
    @ObservationIgnored private let engine: TranscriptionServiceProtocol
    /// A loaded engine of its own for a transcript model that is not the
    /// dictation model.
    @ObservationIgnored private let makeTranscriptEngine: (ASRModelID) async throws -> TranscriptionServiceProtocol
    @ObservationIgnored private let environment: MeetingEnvironment
    @ObservationIgnored private let analytics: Analytics
    @ObservationIgnored private let detector: MeetingCallDetector
    @ObservationIgnored private var launched = false
    @ObservationIgnored private var isStarting = false
    @ObservationIgnored private var cardTimer: Task<Void, Never>?
    /// The pass asked for last: each pass starts when the one before it ends.
    @ObservationIgnored private var lastPass: Task<Void, Never>?
    /// The passes that decode now. Each one waits while a dictation runs.
    @ObservationIgnored private var transcribers: [UUID: MeetingTranscriber] = [:]
    @ObservationIgnored private var dictating = false
    /// The dictation's audio capture runs: the microphone track gets silence.
    @ObservationIgnored private var dictationCaptures = false {
        didSet {
            live?.recorder.setMicrophoneMuted(dictationCaptures)
            blockPlayback()
        }
    }
    @ObservationIgnored private var loadedModel: ASRModelID?
    @ObservationIgnored private var listTexts: [UUID: MeetingListText] = [:]
    @ObservationIgnored private var liveCheck: Task<Void, Never>?
    @ObservationIgnored private var changedInputReset: Task<Void, Never>?

    init(
        store: MeetingStore,
        templates: MeetingTemplateStore,
        settingsStore: MeetingSettingsStore,
        engine: TranscriptionServiceProtocol,
        makeTranscriptEngine: @escaping (ASRModelID) async throws -> TranscriptionServiceProtocol,
        environment: MeetingEnvironment,
        summaryAvailability: @escaping () -> MeetingSummaryAvailability,
        makeSummaryModel: @escaping (MeetingSummaryEngine) -> MeetingSummaryModel?,
        analytics: Analytics
    ) {
        self.store = store
        self.templates = templates
        self.settingsStore = settingsStore
        self.engine = engine
        self.makeTranscriptEngine = makeTranscriptEngine
        self.environment = environment
        self.analytics = analytics
        settings = settingsStore.load()
        playback = MeetingPlayback(store: store, makePlayer: environment.makePlayer)
        detector = MeetingCallDetector(reader: environment.makeMicrophoneUsers(), uptime: environment.uptime)
        summaries = MeetingSummaries(
            store: store,
            templates: templates,
            availability: summaryAvailability,
            makeModel: makeSummaryModel,
            analytics: analytics
        )
        summaries.onFinished = { [weak self] record in
            self?.apply(record)
            if record.status == .done {
                self?.onNotice?(.summaryReady(record.id))
            }
        }
        summaries.onModelIdle = { [weak self] in self?.host?.meetingSummaryModelIsIdle() }
        detector.onEvent = { [weak self] in self?.handle($0) }
    }

    var canRecordCallAudio: Bool {
        environment.canRecordCallAudio
    }

    /// At launch: repair what a quit or a crash left, queue the summaries
    /// that are not written yet, and delete the audio whose time is over. A
    /// transcript that a quit or a crash left waits for Finish Transcript.
    func start() async {
        _ = await store.recoverInterruptedMeetings()
        meetings = await store.loadAll()
        audioOnMac = await store.meetingsWithAudio(meetings.map(\.id))
        for record in meetings where record.status == .summarizing {
            summaries.enqueue(record.id)
        }
        launched = true
        updateCallDetection()
        await deleteExpiredAudio()
    }

    /// The summary, notes and transcript of a meeting, read from disk once.
    func listText(for id: UUID) async -> MeetingListText {
        if let cached = listTexts[id] {
            return cached
        }
        let revision = listTextRevision
        let text = MeetingListText(
            summary: await store.summary(of: id),
            notes: await store.notes(of: id) ?? "",
            transcript: await transcript(of: id).map(\.text)
        )
        if revision == listTextRevision {
            listTexts[id] = text
        }
        return text
    }

    private func dropListText(_ id: UUID) {
        listTexts[id] = nil
        listTextRevision += 1
    }

    /// The transcript as a reader sees it, also while the app still finishes
    /// it: see `MeetingTranscript.final(_:of:)`.
    func transcript(of id: UUID) async -> [MeetingSegment] {
        let segments = await store.segments(of: id)
        guard let record = record(id) else { return segments }
        return MeetingTranscript.final(segments, of: record)
    }

    func summary(of id: UUID) async -> String? {
        await store.summary(of: id)
    }

    /// nil when the notes cannot be read.
    func notes(of id: UUID) async -> String? {
        await store.notes(of: id)
    }

    /// Writes the summary, notes and transcript to `url` as Markdown.
    /// The text that the user typed is saved first, so the file has it.
    func export(_ record: MeetingRecord, to url: URL) async throws {
        await textSaves.finish(record.id)
        let record = self.record(record.id) ?? record
        let markdown = MeetingExport.markdown(
            record: record,
            summary: await summary(of: record.id),
            notes: await notes(of: record.id) ?? "",
            segments: await transcript(of: record.id)
        )
        try markdown.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Settings

    func updateSettings(_ change: (inout MeetingSettings) -> Void) {
        change(&settings)
        settingsStore.save(settings)
        updateCallDetection()
    }

    func chooseCallStartAction(_ action: MeetingCallStartAction) {
        updateSettings { $0.callStartAction = action }
    }

    /// Saves the list that the template editor shows. When the Default
    /// template is not in it any more, General is the default again.
    func saveTemplates(_ list: [MeetingTemplate]) async throws {
        try await templates.replace(with: list)
        if !list.contains(where: { $0.id == settings.templateID }) {
            updateSettings { $0.templateID = MeetingTemplate.general.id }
        }
    }

    // MARK: - Recording

    func startMeeting(source: MeetingSource, callApp: MeetingCallApp? = nil) async throws {
        guard live == nil, !isStarting else { throw MeetingStartError.alreadyRecording }
        isStarting = true
        defer { isStarting = false }
        if let free = environment.freeDiskBytes(), free < Self.minimumFreeBytes {
            throw MeetingStartError.notEnoughSpace
        }
        guard await host?.requestMeetingMicrophoneAccess() == true else {
            throw MeetingStartError.noMicrophoneAccess
        }

        let id = UUID()
        let recorder = MeetingRecorder(
            sources: environment.makeSources(host?.meetingInputDeviceID),
            audioURL: { [store] in store.audioURL($0, for: id) }
        )
        let record = MeetingRecord(
            id: id,
            title: callApp?.title ?? "Meeting",
            startedAt: environment.now(),
            tracks: recorder.tracks,
            callAppName: callApp?.name,
            callAppBundleID: callApp?.bundleID,
            templateID: settings.templateID,
            callPlayedOnSpeakers: environment.callPlaysOnSpeakers()
        )
        try await store.create(record)
        let speech = MeetingSpeechWatch(makeDetector: environment.makeSpeechDetector)
        let session = MeetingSession(record: record, source: source, recorder: recorder, speech: speech)
        // The recorder's queue keeps its output and events in order, and so
        // do the speech watch's stream and the main queue.
        recorder.onOutput = { speech.enqueue($0) }
        recorder.onEvent = { [weak self, weak session] event in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let session else { return }
                    self?.handle(event, from: session)
                }
            }
        }
        await speech.start()
        recorder.setMicrophoneMuted(dictationCaptures)
        // The microphone would hear the playback. No await from here to
        // `live`, so no Play comes in between.
        playback.close()
        do {
            try recorder.start()
        } catch {
            speech.stop()
            try? await store.delete(record.id)
            throw MeetingStartError.couldNotStart(error.localizedDescription)
        }
        // No await between the start and `live`: `handle` drops the events of
        // a session that is not live, and the recorder sends some at once.
        live = session
        meetings.insert(record, at: 0)
        audioOnMac.insert(record.id)
        closeCallCard()
        detector.recordingStarted(call: callApp)
        checkLive(session)
        analytics.track(.meetingStarted(source: source))
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
            if let last = $0.pauses.indices.last, $0.pauses[last].end == nil {
                $0.pauses[last].end = now
            }
            $0.status = .recording
        }
    }

    /// Stops the recording, then writes the transcript and queues the summary.
    func stop(_ reason: MeetingStopReason = .user) async {
        await stop(reason, endingAt: nil)
    }

    /// `cut` ends the meeting before now: the transcript keeps no line that
    /// starts after it.
    private func stop(_ reason: MeetingStopReason, endingAt cut: Date?) async {
        guard let session = beginStop() else { return }
        let now = wallSeconds(of: session)
        let end = cut.map { min(now, max(0, $0.timeIntervalSince(session.record.startedAt))) } ?? now
        await update(session.id) {
            $0.end(atWallSeconds: end)
            if cut != nil {
                $0.transcriptEnd = MeetingTimeline(pauses: $0.pauses).audioPosition(forWallSeconds: end)
            }
            $0.status = .finishing
        }
        live = nil
        AppLogger.shared.log(.info, "meeting stopped id=\(session.id.uuidString) reason=\(reason.rawValue)")
        trackEnd(of: session, atWallSeconds: end, reason: reason)
        switch reason {
        case .timeLimit:
            onNotice?(.stoppedAtTimeLimit(session.id, after: Self.recordingLimit))
        case .noSpeech:
            onNotice?(.stoppedWithoutSpeech(session.id, after: environment.speechlessLimit))
        case .diskFull:
            onNotice?(.stoppedByDiskFull(session.id))
        case .writeFailed:
            onNotice?(.stoppedByWriteError(session.id))
        case .user, .callEnded, .sleep, .quit:
            break
        }
        if let callEnd = record(session.id)?.transcriptEnd {
            await store.cutAudio(of: session.id, afterSample: callEnd)
        }
        await queuePass(session.id, kind: .first)?.value
    }

    /// A call track that cannot start again shows as a failed track.
    func restartCallAudio() {
        live?.recorder.restartCallAudio()
    }

    /// Before the app quits: stops the recording and saves it. The next
    /// launch shows it with Finish Transcript.
    func stopForQuit() async {
        guard let session = beginStop() else { return }
        let end = wallSeconds(of: session)
        await update(session.id) { $0.end(atWallSeconds: end) }
        live = nil
        AppLogger.shared.log(.info, "meeting stopped for quit id=\(session.id.uuidString)")
        trackEnd(of: session, atWallSeconds: end, reason: .quit)
    }

    /// Finishes the transcript of a meeting from its audio files: after a
    /// quit or a crash, or when the user asks again after a failed finish.
    func finishTranscript(_ id: UUID) {
        queuePass(id, kind: .first)
    }

    /// The audio is on the Mac, the transcript is final, and no new
    /// transcript is being written for the meeting.
    func canTranscribeAgain(_ record: MeetingRecord) -> Bool {
        audioOnMac.contains(record.id) && record.status.hasFinalTranscript && transcriptPasses[record.id] == nil
    }

    /// Writes the transcript again from the kept audio, with the transcript
    /// model set now. The transcript stays until the new one is complete, and
    /// the summary is not written again.
    func transcribeAgain(_ id: UUID) {
        guard let record = record(id), canTranscribeAgain(record) else { return }
        queuePass(id, kind: .again)
    }

    /// The model that a transcript pass started now uses, by name.
    var transcriptModelName: String? {
        (settings.transcriptModel ?? loadedModel).map { ASRModelCatalog.entry(for: $0).displayName }
    }

    // MARK: - Calls

    /// Record on the offer card.
    func recordOfferedCall() async {
        guard case let .offer(app) = callCard else { return }
        answerCallCard(.record)
        await startForCall(app, source: .offer)
    }

    /// Not Now on the offer card.
    func declineOffer() {
        guard case .offer = callCard else { return }
        answerCallCard(.notNow)
    }

    func neverAsk(for app: MeetingCallApp) {
        guard callCard == .offer(app) else { return }
        answerCallCard(.never)
        guard !settings.neverAskBundleIDs.contains(app.bundleID) else { return }
        updateSettings { $0.neverAskBundleIDs.append(app.bundleID) }
    }

    /// Cancel on the card of a recording that started by itself: the
    /// recording and its files go.
    func cancelAutomaticRecording() async {
        guard case .startedAutomatically = callCard else { return }
        answerCallCard(.cancel)
        guard let session = beginStop() else { return }
        live = nil
        meetings.removeAll { $0.id == session.id }
        audioOnMac.remove(session.id)
        do {
            try await store.delete(session.id)
        } catch {
            AppLogger.shared.log(.error, "canceled meeting not deleted id=\(session.id.uuidString) error=\(error.localizedDescription)")
        }
        AppLogger.shared.log(.info, "meeting canceled id=\(session.id.uuidString)")
    }

    /// Stop Now on the countdown of a recording that started by itself: the
    /// meeting ends when the call did. Stop Recording on the card of a
    /// recording that the user started: it stops now, and keeps the talk
    /// after the call.
    func stopEndedCall() async {
        guard case let .callEnded(_, _, endedAt, stopsAt) = callCard else { return }
        answerCallCard(.stopNow)
        await stop(.callEnded, endingAt: stopsAt == nil ? nil : endedAt)
    }

    /// Keep Recording on the call-ended card.
    func keepRecording() {
        guard case .callEnded = callCard else { return }
        answerCallCard(.keepRecording)
    }

    /// Do Nothing turns call detection off, except while a meeting records:
    /// the recording follows its call.
    private func updateCallDetection() {
        guard launched else { return }
        if settings.callStartAction == .doNothing, live == nil {
            detector.stop()
        } else {
            detector.start()
        }
    }

    private func handle(_ event: MeetingCallWatch.Event) {
        switch event {
        case let .callStarted(app, confirmed):
            guard live == nil, !isStarting, !settings.neverAskBundleIDs.contains(app.bundleID) else { return }
            if settings.callStartAction == .recordAutomatically, confirmed {
                Task { await startAutomatically(app) }
            } else {
                showCard(.offer(app), for: environment.callCardDurations.offer)
            }
        case let .followed(app):
            guard let session = live else { return }
            if case .callEnded = callCard {
                closeCallCard()
            }
            if session.record.callAppBundleID == nil {
                Task {
                    await update(session.id) {
                        $0.callAppName = app.name
                        $0.callAppBundleID = app.bundleID
                    }
                    // A silence that the recorder reported before is a problem now.
                    session.recorder.rearmCallSilence()
                }
            }
        case let .callEnded(app):
            if callCard == .offer(app) {
                answerCallCard(.callEnded)
            }
        case let .recordedCallEnded(app, endedAt, silent):
            guard let session = live else { return }
            let now = environment.now()
            let ended = now.addingTimeInterval(endedAt - environment.uptime())
            guard session.source == .automatic else {
                showCard(.callEnded(app, silent: silent, endedAt: ended, stopsAt: nil), for: nil)
                return
            }
            let delay = environment.callCardDurations.stop
            showCard(.callEnded(app, silent: silent, endedAt: ended, stopsAt: now.addingTimeInterval(delay)), for: delay)
        case .recordedCallResumed:
            if case .callEnded(_, silent: true, _, _) = callCard {
                closeCallCard()
            }
        }
    }

    private func startAutomatically(_ app: MeetingCallApp) async {
        await startForCall(app, source: .automatic)
        guard live != nil else { return }
        let window = environment.callCardDurations.cancel
        showCard(.startedAutomatically(app, cancelEndsAt: environment.now().addingTimeInterval(window)), for: window)
    }

    private func startForCall(_ app: MeetingCallApp, source: MeetingSource) async {
        do {
            try await startMeeting(source: source, callApp: app)
        } catch {
            host?.meetingCouldNotStart(error)
        }
    }

    /// Shows `card` until an answer, or for `seconds`: then the card closes
    /// by itself, and the call-ended card stops the recording. With no
    /// `seconds`, the card stays until an answer.
    private func showCard(_ card: MeetingCallCard, for seconds: TimeInterval?) {
        cardTimer?.cancel()
        cardTimer = nil
        callCard = card
        guard let seconds else { return }
        cardTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, self.callCard == card else { return }
            self.cardTimer = nil
            self.answerCallCard(.timeout)
            if case let .callEnded(_, _, endedAt, _) = card {
                await self.stop(.callEnded, endingAt: endedAt)
            }
        }
    }

    private func answerCallCard(_ action: MeetingCallCardAction) {
        guard let card = callCard else { return }
        analytics.track(.meetingCallCard(card: card.analyticsKind, action: action))
        closeCallCard()
    }

    private func closeCallCard() {
        cardTimer?.cancel()
        cardTimer = nil
        callCard = nil
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

    /// Writes the text that the user changed in transcript lines; the times
    /// and the speakers stay. An empty text deletes its line when the edit
    /// ended (`deleteEmpty`); until then the line keeps its old text on disk,
    /// so a line that the user empties to retype it does not go.
    func editTranscript(_ id: UUID, texts: [UUID: String], deleteEmpty: Bool) async {
        guard record(id)?.status.hasFinalTranscript == true else { return }
        let segments = await store.segments(of: id).compactMap { segment -> MeetingSegment? in
            guard let text = texts[segment.id] else { return segment }
            if text.isEmpty {
                return deleteEmpty ? nil : segment
            }
            return segment.withText(text)
        }
        do {
            try await store.replaceSegments(segments, of: id)
        } catch {
            AppLogger.shared.log(.error, "meeting transcript edit not saved id=\(id.uuidString) error=\(error.localizedDescription)")
            return
        }
        if record(id)?.transcriptEditedAt == nil {
            let now = environment.now()
            await update(id) { $0.transcriptEditedAt = now }
        }
        dropListText(id)
    }

    /// The user changed this part of a meeting's text, for the first time in
    /// this visit of its page.
    func textEdited(_ part: MeetingEditedText) {
        analytics.track(.meetingEdited(part: part))
    }

    /// The audio of a meeting started to play, for the first time in this
    /// visit of its page.
    func playbackStarted() {
        analytics.track(.meetingPlayed)
    }

    /// Writes the summary that the user changed, as Markdown.
    func editSummary(_ id: UUID, markdown: String) async {
        guard record(id)?.status == .done else { return }
        do {
            try await store.saveSummary(markdown, for: id)
        } catch {
            AppLogger.shared.log(.error, "meeting summary edit not saved id=\(id.uuidString) error=\(error.localizedDescription)")
            return
        }
        if record(id)?.summaryEditedAt == nil {
            let now = environment.now()
            await update(id) { $0.summaryEditedAt = now }
        }
        dropListText(id)
    }

    /// The cached list text goes after the write, so no read that ran
    /// during it keeps the old notes.
    func saveNotes(_ notes: String, for id: UUID) async {
        do {
            try await store.saveNotes(notes, for: id)
        } catch {
            AppLogger.shared.log(.error, "meeting notes not saved id=\(id.uuidString) error=\(error.localizedDescription)")
        }
        dropListText(id)
    }

    func regenerate(_ id: UUID, templateID: String? = nil) async {
        guard record(id)?.status.canRegenerate == true else { return }
        await textSaves.finish(id)
        if let templateID {
            updateSettings { $0.templateID = templateID }
        }
        let enough = await hasEnoughSpeech(id, segments: transcript(of: id))
        await update(id) {
            if let templateID {
                $0.templateID = templateID
            }
            $0.status = enough ? .summarizing : .noSpeech
            $0.summaryFailure = nil
        }
        if enough {
            summaries.enqueue(id)
        }
    }

    func delete(_ id: UUID) async throws {
        guard live?.id != id, transcriptPasses[id] == nil else { return }
        playback.close(id)
        summaries.remove(id)
        try await store.delete(id)
        meetings.removeAll { $0.id == id }
        audioOnMac.remove(id)
    }

    func record(_ id: UUID) -> MeetingRecord? {
        meetings.first { $0.id == id }
    }

    // MARK: - Dictation and the speech model

    /// From the start of a dictation to its end, no meeting chunk starts
    /// decoding and the summary waits. The microphone track gets silence from
    /// the start until `dictationCaptureEnded()`: the dictated words are not
    /// meeting talk. Playback stops for the capture, so the dictation does
    /// not hear it, and it does not start again by itself.
    func dictationChanged(active: Bool) {
        dictating = active
        dictationCaptures = active
        summaries.hold(active)
        detector.dictationChanged(active: active)
        wakeTranscribers()
    }

    /// The dictation's capture ended, its release tail included. Talk during
    /// the rest of the dictation (transcription, Magic Format) is meeting talk.
    func dictationCaptureEnded() {
        dictationCaptures = false
    }

    /// Meeting chunks decode only while a speech model is loaded.
    func speechModelChanged(_ model: ASRModelID?) {
        loadedModel = model
        wakeTranscribers()
    }

    private var speechEngineFree: Bool {
        loadedModel != nil && !dictating
    }

    /// Each pass asks its own `mayDecode` again.
    private func wakeTranscribers() {
        for transcriber in transcribers.values {
            Task { await transcriber.wake() }
        }
    }

    // MARK: - Private

    /// The live meeting with its capture stopped, marked so that a second
    /// stop does nothing; nil when nothing records or a stop already runs.
    private func beginStop() -> MeetingSession? {
        guard let session = live, !session.isStopping else { return nil }
        session.isStopping = true
        session.recorder.stop()
        session.speech.stop()
        liveCheck?.cancel()
        liveCheck = nil
        closeCallCard()
        detector.recordingStopped()
        return session
    }

    private func trackEnd(of session: MeetingSession, atWallSeconds end: Double, reason: MeetingStopReason) {
        let recorded = MeetingTimeline(pauses: session.record.pauses).audioSeconds(forWallSeconds: end)
        analytics.track(.meetingEnded(
            durationMs: Int(recorded / 60) * 60_000,
            tracks: MeetingTracks(session.workingTracks),
            reason: reason
        ))
    }

    /// Queues the transcript pass of `id` behind the passes asked before it,
    /// with the transcript model set now, and returns it; nil when a pass of
    /// `id` already waits or runs. One pass at a time: two passes with a
    /// chosen model would each load an engine of their own beside the
    /// dictation model.
    @discardableResult
    private func queuePass(_ id: UUID, kind: MeetingTranscriptPass.Kind) -> Task<Void, Never>? {
        guard transcriptPasses[id] == nil else { return nil }
        transcriptPasses[id] = MeetingTranscriptPass(kind: kind, waiting: !transcriptPasses.isEmpty)
        let model = settings.transcriptModel
        let previous = lastPass
        let pass = Task { [weak self] in
            if kind == .first {
                await self?.update(id) { $0.status = .finishing }
            }
            await previous?.value
            self?.transcriptPasses[id]?.waiting = false
            switch kind {
            case .first:
                await self?.transcribe(id, model: model)
            case .again:
                await self?.writeTranscriptAgain(id, model: model)
            }
            await self?.endPass(id)
        }
        lastPass = pass
        return pass
    }

    /// Every pass ends here, and then the audio whose time is over goes.
    private func endPass(_ id: UUID) async {
        transcriptPasses[id] = nil
        await deleteExpiredAudio()
    }

    /// Writes the transcript, then queues the summary.
    private func transcribe(_ id: UUID, model chosenModel: ASRModelID?) async {
        let started = ContinuousClock.now
        let outcome: MeetingOutcome
        var segments = 0
        do {
            let transcript = try await runPass(id, model: chosenModel, lines: .transcript)
            segments = transcript.count
            outcome = segments == 0 ? .noSpeech : .done
            let enough = await hasEnoughSpeech(id, segments: transcript)
            await update(id) {
                $0.status = enough ? .summarizing : .noSpeech
                $0.transcriptFailure = nil
            }
            if enough {
                summaries.enqueue(id)
            }
        } catch {
            AppLogger.shared.log(.error, "meeting transcript not finished id=\(id.uuidString) error=\(error.localizedDescription)")
            outcome = .failed
            let cause = error.localizedDescription
            await update(id) {
                $0.status = .interrupted
                $0.transcriptFailure = cause
            }
        }
        analytics.track(.meetingTranscribed(
            outcome: outcome,
            model: SafeLabel((chosenModel ?? loadedModel)?.rawValue ?? ""),
            segments: segments,
            durationMs: Int((ContinuousClock.now - started) / .milliseconds(1))
        ))
    }

    /// Writes a draft from the kept audio, and the draft replaces the
    /// transcript only when it is complete and has a line: a model that hears
    /// nothing keeps the transcript. The notes, the summary and the meeting's
    /// state stay.
    private func writeTranscriptAgain(_ id: UUID, model chosenModel: ASRModelID?) async {
        // A track whose audio is gone would lose its lines in the new transcript.
        guard await Set(store.segments(of: id).map(\.track)).isSubset(of: store.audioTracks(of: id)) else {
            AppLogger.shared.log(.error, "meeting transcript not written again id=\(id.uuidString) error=the audio of a track is gone")
            onNotice?(.notTranscribedAgain(id))
            return
        }
        await store.deleteDraft(of: id)
        do {
            let transcript = try await runPass(id, model: chosenModel, lines: .draft)
            guard !transcript.isEmpty else { throw TranscribeAgainError.noLines }
            try await store.keepDraft(of: id)
            await update(id) { $0.transcriptEditedAt = nil }
            dropListText(id)
            onNotice?(.transcribedAgain(id))
        } catch {
            AppLogger.shared.log(.error, "meeting transcript not written again id=\(id.uuidString) error=\(error.localizedDescription)")
            await store.deleteDraft(of: id)
            onNotice?(.notTranscribedAgain(id))
        }
    }

    private enum TranscribeAgainError: LocalizedError {
        case noLines

        var errorDescription: String? {
            "the new transcript has no line"
        }
    }

    /// Deletes the audio whose time is over: at launch and after each
    /// transcript, never on a timer. A meeting with no final transcript keeps
    /// its audio for Finish Transcript, and a meeting in a pass or with its
    /// audio open in the player keeps it until the next check.
    private func deleteExpiredAudio() async {
        let now = environment.now()
        for record in meetings where audioOnMac.contains(record.id) && record.status.hasFinalTranscript
            && transcriptPasses[record.id] == nil && playback.meetingID != record.id {
            if let days = settings.audioRetention.days,
               now < (record.endedAt ?? record.startedAt).addingTimeInterval(TimeInterval(days) * 24 * 60 * 60) {
                continue
            }
            // Off the list before the await, so no pass starts on audio that goes.
            audioOnMac.remove(record.id)
            if await !store.deleteAudio(of: record.id) {
                audioOnMac.insert(record.id)
            }
        }
    }

    /// With no model ("Same as dictation"), the pass runs on the dictation
    /// engine with the model that engine has. A chosen model, the dictation
    /// model too, gets an engine of its own that is unloaded after the pass,
    /// so a switch of the dictation model does not change the pass. On either
    /// engine, no piece of audio starts decoding while a dictation runs.
    private func runPass(_ id: UUID, model: ASRModelID?, lines: MeetingStore.SegmentFile) async throws -> [MeetingSegment] {
        guard let model else {
            return try await run(makeTranscriber(for: id, lines: lines, engine: engine) { [weak self] in await self?.speechEngineFree ?? false }, for: id)
        }
        let ownEngine = try await makeTranscriptEngine(model)
        let transcriber = makeTranscriber(for: id, lines: lines, engine: ownEngine) { [weak self] in await self?.dictating == false }
        do {
            let transcript = try await run(transcriber, for: id)
            await ownEngine.unloadModel()
            return transcript
        } catch {
            await ownEngine.unloadModel()
            throw error
        }
    }

    private func run(_ transcriber: MeetingTranscriber, for id: UUID) async throws -> [MeetingSegment] {
        transcribers[id] = transcriber
        defer { transcribers[id] = nil }
        return try await transcriber.transcribe()
    }

    private func makeTranscriber(
        for id: UUID,
        lines: MeetingStore.SegmentFile,
        engine: TranscriptionServiceProtocol,
        mayDecode: @escaping @Sendable () async -> Bool
    ) -> MeetingTranscriber {
        MeetingTranscriber(
            meetingID: id,
            tracks: store.audioTracks(of: id),
            store: store,
            lines: lines,
            engine: engine,
            mayDecode: mayDecode,
            onProgress: { [weak self] progress in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.show(progress, of: id) } }
            }
        )
    }

    private func show(_ progress: MeetingTranscriptProgress, of id: UUID) {
        transcriptPasses[id]?.progress = progress
    }

    private func handle(_ event: MeetingRecorderEvent, from session: MeetingSession) {
        guard live === session else { return }
        switch event {
        case let .levels(you, them):
            session.youLevel = you
            session.themLevel = them
        case let .callAudioSilent(heardBefore, since):
            // A meeting in the room has no call, so its silent call track is
            // no problem.
            guard session.record.callAppBundleID != nil else { return }
            session.callAudioProblem = heardBefore ? .stopped(since: since) : .neverHeard
            onNotice?(heardBefore ? .callAudioStopped : .callAudioNeverHeard)
        case .callAudioReturned:
            session.callAudioProblem = nil
        case let .inputChanged(name):
            session.changedInput = name
            onNotice?(.microphoneChanged(name))
            changedInputReset?.cancel()
            changedInputReset = Task { [weak session] in
                try? await Task.sleep(for: Self.changedInputSeconds)
                guard !Task.isCancelled else { return }
                session?.changedInput = nil
            }
        case let .trackStarted(track):
            session.failedTracks[track] = nil
            if track == .them {
                session.callAudioProblem = nil
            }
        case let .trackFailed(track, message):
            session.failedTracks[track] = message
            onNotice?(.trackFailed(track))
        case let .storageFailed(message, outOfSpace):
            AppLogger.shared.log(.error, "meeting stopped by a write error id=\(session.id.uuidString) error=\(message)")
            writeFailure = MeetingWriteFailure(meetingID: session.id, outOfSpace: outOfSpace)
            Task { await stop(outOfSpace ? .diskFull : .writeFailed) }
        }
    }

    /// Every few seconds while the meeting records: stops it at the time
    /// limit and after a long time with no speech, and notes when the call
    /// plays on speakers, for the echo filter.
    private func checkLive(_ session: MeetingSession) {
        liveCheck?.cancel()
        liveCheck = Task { [weak self, weak session] in
            while !Task.isCancelled {
                guard let self, let session else { return }
                if session.elapsed(at: self.environment.now()) >= Self.recordingLimit {
                    Task { await self.stop(.timeLimit) }
                    return
                }
                if await session.speech.secondsWithoutSpeech(on: session.workingTracks) >= self.environment.speechlessLimit {
                    Task { await self.stop(.noSpeech) }
                    return
                }
                if !session.record.callPlayedOnSpeakers, self.environment.callPlaysOnSpeakers() {
                    await self.update(session.id) { $0.callPlayedOnSpeakers = true }
                }
                try? await Task.sleep(for: self.environment.liveCheckInterval)
            }
        }
    }

    private func wallSeconds(of session: MeetingSession) -> Double {
        environment.now().timeIntervalSince(session.record.startedAt)
    }

    /// Memory holds the change at once, so the next action sees it, and also
    /// when the write fails. The store's copy does not replace it: an update
    /// that started later may not be on disk yet.
    private func update(_ id: UUID, _ change: @escaping (inout MeetingRecord) -> Void) async {
        if var record = live?.id == id ? live?.record : record(id) {
            change(&record)
            apply(record)
        }
        do {
            _ = try await store.update(id, change)
        } catch {
            AppLogger.shared.log(.error, "meeting not saved id=\(id.uuidString) error=\(error.localizedDescription)")
        }
    }

    private func blockPlayback() {
        playback.block(live != nil || dictationCaptures)
    }

    private func hasEnoughSpeech(_ id: UUID, segments: [MeetingSegment]) async -> Bool {
        MeetingSummaryWriter.hasEnoughSpeech(segments, notes: await store.notes(of: id) ?? "")
    }

    private func apply(_ record: MeetingRecord) {
        dropListText(record.id)
        if let index = meetings.firstIndex(where: { $0.id == record.id }) {
            meetings[index] = record
        }
        if let live, live.id == record.id {
            live.record = record
        }
    }
}
