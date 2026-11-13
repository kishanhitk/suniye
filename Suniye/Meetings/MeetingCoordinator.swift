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
    /// microphone, or, when `silent`, played no sound. The recording stops at
    /// `stopsAt` and keeps nothing after `endedAt`.
    case callEnded(MeetingCallApp, silent: Bool, endedAt: Date, stopsAt: Date)

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
    fileprivate(set) var youLevel: Float = 0
    fileprivate(set) var themLevel: Float = 0
    fileprivate(set) var segments: [MeetingSegment] = []
    /// For each track: every chunk before this sample position is decoded.
    fileprivate(set) var decodedThrough: [MeetingTrack: Int] = [:]
    fileprivate(set) var callAudioProblem: CallAudioProblem?
    fileprivate(set) var failedTracks: [MeetingTrack: String] = [:]
    /// The new microphone, for a few seconds after the device changed.
    fileprivate(set) var changedInput: String?

    @ObservationIgnored fileprivate let recorder: MeetingRecorder
    @ObservationIgnored fileprivate let transcriber: MeetingTranscriber
    /// Set by the first stop, so that a second one does nothing.
    @ObservationIgnored fileprivate var isStopping = false

    fileprivate init(record: MeetingRecord, recorder: MeetingRecorder, transcriber: MeetingTranscriber) {
        self.record = record
        self.recorder = recorder
        self.transcriber = transcriber
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

    var visibleSegments: [MeetingSegment] {
        MeetingTranscript.live(
            segments,
            callDecodedThrough: workingTracks.contains(.them) ? decodedThrough[.them] ?? 0 : nil,
            callPlayedOnSpeakers: record.callPlayedOnSpeakers
        )
    }

    fileprivate var workingTracks: [MeetingTrack] {
        recorder.tracks.filter { failedTracks[$0] == nil }
    }

    /// Transcribed audio after the last words, on every track that records.
    fileprivate var secondsWithoutSpeech: Double {
        let decoded = workingTracks.map { decodedThrough[$0] ?? 0 }.min() ?? 0
        let lastWords = segments.map(\.audioEnd).max() ?? 0
        return Double(max(0, decoded - lastWords)) / Double(MeetingAudioFormat.sampleRate)
    }

    /// Recorded time: the wall clock since the start, without the pauses.
    func elapsed(at date: Date) -> TimeInterval {
        MeetingTimeline(pauses: record.pauses).audioSeconds(forWallSeconds: date.timeIntervalSince(record.startedAt))
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
            }
        }
    }
    /// A meeting that a disk write error stopped, for its banner.
    private(set) var writeFailure: MeetingWriteFailure?
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
    @ObservationIgnored let templates: MeetingTemplateStore

    @ObservationIgnored private let settingsStore: MeetingSettingsStore
    @ObservationIgnored private let engine: TranscriptionServiceProtocol
    @ObservationIgnored private let environment: MeetingEnvironment
    @ObservationIgnored private let analytics: Analytics
    @ObservationIgnored private let detector: MeetingCallDetector
    @ObservationIgnored private var launched = false
    @ObservationIgnored private var isStarting = false
    @ObservationIgnored private var cardTimer: Task<Void, Never>?
    @ObservationIgnored private var transcribers: [UUID: MeetingTranscriber] = [:]
    @ObservationIgnored private var dictating = false
    /// The dictation's audio capture runs: the microphone track gets silence.
    @ObservationIgnored private var dictationCaptures = false {
        didSet { live?.recorder.setMicrophoneMuted(dictationCaptures) }
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
        environment: MeetingEnvironment,
        summaryAvailability: @escaping () -> MeetingSummaryAvailability,
        makeSummaryModel: @escaping (MeetingSummaryEngine) -> MeetingSummaryModel?,
        analytics: Analytics
    ) {
        self.store = store
        self.templates = templates
        self.settingsStore = settingsStore
        self.engine = engine
        self.environment = environment
        self.analytics = analytics
        settings = settingsStore.load()
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
        launched = true
        updateCallDetection()
    }

    /// The summary, notes and transcript of a meeting, read from disk once.
    func listText(for id: UUID) async -> MeetingListText {
        if let cached = listTexts[id] {
            return cached
        }
        let text = MeetingListText(
            summary: await store.summary(of: id),
            notes: await store.notes(of: id) ?? "",
            transcript: await transcript(of: id).map(\.text)
        )
        listTexts[id] = text
        return text
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

    // MARK: - Settings

    func updateSettings(_ change: (inout MeetingSettings) -> Void) {
        change(&settings)
        settingsStore.save(settings)
        updateCallDetection()
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

    func startMeeting(source: MeetingSource, callApp: MeetingCallApp? = nil) async throws {
        guard live == nil, !isStarting else { throw MeetingStartError.alreadyRecording }
        isStarting = true
        defer { isStarting = false }
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
        let transcriber = makeTranscriber(for: record.id, tracks: recorder.tracks)
        let session = MeetingSession(record: record, recorder: recorder, transcriber: transcriber)
        // The recorder's queue keeps its events in order, and so does the main queue.
        recorder.onOutput = { transcriber.enqueue($0) }
        recorder.onEvent = { [weak self, weak session] event in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let session else { return }
                    self?.handle(event, from: session)
                }
            }
        }
        await transcriber.start()
        recorder.setMicrophoneMuted(dictationCaptures)
        do {
            try recorder.start()
        } catch {
            transcribers[record.id] = nil
            await transcriber.cancel()
            try? await store.delete(record.id)
            throw MeetingStartError.couldNotStart(error.localizedDescription)
        }
        // No await between the start and `live`: `handle` drops the events of
        // a session that is not live, and the recorder sends some at once.
        live = session
        meetings.insert(record, at: 0)
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

    /// Stops the recording, then finishes the transcript and queues the summary.
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
        await finish(session.id, transcriber: session.transcriber) { try await $0.finish() }
    }

    /// A call track that cannot start again shows as a failed track.
    func restartCallAudio() {
        live?.recorder.restartCallAudio()
    }

    /// Before the app quits: stops the recording and saves it, and leaves the
    /// transcript to the next launch, which finishes it with no click.
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
        guard transcribers[id] == nil else { return }
        let transcriber = makeTranscriber(for: id, tracks: store.audioTracks(of: id))
        Task {
            await update(id) { $0.status = .finishing }
            await finish(id, transcriber: transcriber) { try await $0.recover() }
        }
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
        transcribers[session.id] = nil
        await session.transcriber.cancel()
        do {
            try await store.delete(session.id)
        } catch {
            AppLogger.shared.log(.error, "canceled meeting not deleted id=\(session.id.uuidString) error=\(error.localizedDescription)")
        }
        AppLogger.shared.log(.info, "meeting canceled id=\(session.id.uuidString)")
    }

    /// Stop Now on the call-ended card: the meeting ends when the call did.
    func stopEndedCall() async {
        guard case let .callEnded(_, _, endedAt, _) = callCard else { return }
        answerCallCard(.stopNow)
        await stop(.callEnded, endingAt: endedAt)
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
            guard live != nil else { return }
            let now = environment.now()
            let ended = now.addingTimeInterval(endedAt - environment.uptime())
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
    /// by itself, and the call-ended card stops the recording.
    private func showCard(_ card: MeetingCallCard, for seconds: TimeInterval) {
        cardTimer?.cancel()
        callCard = card
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

    func saveNotes(_ notes: String, for id: UUID) async {
        listTexts[id] = nil
        do {
            try await store.saveNotes(notes, for: id)
        } catch {
            AppLogger.shared.log(.error, "meeting notes not saved id=\(id.uuidString) error=\(error.localizedDescription)")
        }
    }

    func regenerate(_ id: UUID, templateID: String? = nil) async {
        guard record(id)?.status.canRegenerate == true else { return }
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
        guard live?.id != id, record(id)?.status != .finishing else { return }
        summaries.remove(id)
        try await store.delete(id)
        meetings.removeAll { $0.id == id }
    }

    func record(_ id: UUID) -> MeetingRecord? {
        meetings.first { $0.id == id }
    }

    // MARK: - Dictation and the speech model

    /// From the start of a dictation to its end, no meeting chunk starts
    /// decoding and the summary waits. The microphone track gets silence from
    /// the start until `dictationCaptureEnded()`: the dictated words are not
    /// meeting talk.
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

    private func wakeTranscribers() {
        guard speechEngineFree else { return }
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

    private func makeTranscriber(for id: UUID, tracks: [MeetingTrack]) -> MeetingTranscriber {
        let transcriber = MeetingTranscriber(
            meetingID: id,
            tracks: tracks,
            store: store,
            engine: engine,
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
        let started = ContinuousClock.now
        defer {
            transcribers[id] = nil
        }
        let outcome: MeetingOutcome
        var segments = 0
        do {
            let transcript = try await run(transcriber)
            segments = transcript.count
            outcome = segments == 0 ? .noSpeech : .done
            await store.deleteAudio(of: id)
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
            model: SafeLabel(loadedModel?.rawValue ?? ""),
            segments: segments,
            durationMs: Int((ContinuousClock.now - started) / .milliseconds(1))
        ))
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

    private func handle(_ event: MeetingTranscriber.Event, of id: UUID) {
        guard let session = live, session.id == id else { return }
        switch event {
        case let .segment(segment):
            session.segments.append(segment)
        case let .decodedThrough(track, position):
            session.decodedThrough[track] = position
            if session.secondsWithoutSpeech >= environment.speechlessLimit {
                Task { await stop(.noSpeech) }
            }
        }
    }

    /// Every few seconds while the meeting records: stops it at the time
    /// limit, and notes when the call plays on speakers, for the echo filter.
    private func checkLive(_ session: MeetingSession) {
        liveCheck?.cancel()
        liveCheck = Task { [weak self, weak session] in
            while !Task.isCancelled {
                guard let self, let session else { return }
                if session.elapsed(at: self.environment.now()) >= Self.recordingLimit {
                    Task { await self.stop(.timeLimit) }
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

    private func hasEnoughSpeech(_ id: UUID, segments: [MeetingSegment]) async -> Bool {
        MeetingSummaryWriter.hasEnoughSpeech(segments, notes: await store.notes(of: id) ?? "")
    }

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
