import Foundation
import SuniyeAnalytics

/// A call app or browser that holds the microphone, as call detection
/// reports it.
struct MeetingCallApp: Equatable, Sendable {
    let name: String
    let bundleID: String
    let isBrowser: Bool

    /// "Zoom call", or "call in Chrome" for a browser.
    var callName: String {
        isBrowser ? "call in \(name)" : "\(name) call"
    }

    var title: String {
        callName.prefix(1).uppercased() + callName.dropFirst()
    }
}

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

/// Why a recording stopped.
enum MeetingStopCause: String, Sendable {
    case user
    case callEnded
    case sleep
    case timeLimit
    case noSpeech
    case diskFull
    case quit
}

/// Something the user should see while the meeting page is not on screen.
enum MeetingNotice: Equatable {
    case callAudioNeverHeard
    case callAudioStopped(since: TimeInterval)
    case microphoneChanged(String)
    case trackFailed(MeetingTrack)
    case stoppedAtTimeLimit(UUID)
    case stoppedWithoutSpeech(UUID)
    case stoppedByDiskFull(UUID)
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
    /// For each track: every chunk before this sample position is decoded.
    fileprivate(set) var decodedThrough: [MeetingTrack: Int] = [:]
    fileprivate(set) var callAudioProblem: CallAudioProblem?
    /// Recorded time when the call went silent, for "No sound since 16:30".
    fileprivate(set) var callSilentSince: TimeInterval?
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
            callDecodedThrough: hasCallTrack ? decodedThrough[.them] ?? 0 : nil,
            callPlayedOnSpeakers: record.callPlayedOnSpeakers
        )
    }

    /// The tracks that started and did not fail since.
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
            }
        }
    }
    /// Meetings whose transcript is being finished now.
    private(set) var finishing: Set<UUID> = []
    /// A meeting that a disk write error stopped, for its banner.
    private(set) var stoppedByWriteError: UUID?
    /// The meeting that the Meetings section shows; nil shows the list.
    var openMeetingID: UUID?
    /// The meeting whose page is on screen, so a notice does not repeat it.
    var pageOnScreen: UUID?
    private(set) var settings: MeetingSettings
    let canRecordCallAudio: Bool
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
        canRecordCallAudio: Bool,
        summaryAvailability: @escaping () -> MeetingSummaryAvailability,
        makeSummaryModel: @escaping (MeetingSummaryProvider) -> MeetingSummaryModel?,
        analytics: Analytics
    ) {
        self.store = store
        self.templates = templates
        self.settingsStore = settingsStore
        self.engine = engine
        self.environment = environment
        self.canRecordCallAudio = canRecordCallAudio
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

    func startMeeting(source: MeetingStartSource, callApp: MeetingCallApp? = nil) async throws {
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

        let record = MeetingRecord(
            title: callApp?.title ?? "Meeting",
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
        closeCallCard()
        detector.recordingStarted(call: callApp)
        checkLive(session)
        analytics.track(.meetingStarted(source: source.analyticsSource))
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
    func stop(_ cause: MeetingStopCause = .user) async {
        await stop(cause, endingAt: nil)
    }

    /// `cut` ends the meeting before now: the transcript keeps no line that
    /// starts after it.
    private func stop(_ cause: MeetingStopCause, endingAt cut: Date?) async {
        guard let session = beginStop() else { return }
        let now = wallSeconds(of: session)
        let end = cut.map { min(now, $0.timeIntervalSince(session.record.startedAt)) } ?? now
        await update(session.id) {
            $0.end(atWallSeconds: end)
            $0.status = .finishing
        }
        live = nil
        AppLogger.shared.log(.info, "meeting stopped id=\(session.id.uuidString) cause=\(cause.rawValue)")
        trackEnd(of: session, atWallSeconds: end, cause: cause)
        switch cause {
        case .timeLimit:
            onNotice?(.stoppedAtTimeLimit(session.id))
        case .noSpeech:
            onNotice?(.stoppedWithoutSpeech(session.id))
        case .diskFull:
            onNotice?(.stoppedByDiskFull(session.id))
        case .user, .callEnded, .sleep, .quit:
            break
        }
        let keptAudio = cut.map { _ in
            Int(MeetingTimeline(pauses: session.record.pauses).audioSeconds(forWallSeconds: end) * Double(MeetingAudioFormat.sampleRate))
        }
        await finish(session.id, transcriber: session.transcriber) { try await $0.finish(keepingAudioBefore: keptAudio) }
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

    /// Before the app quits: stops the recording and saves it, and leaves the
    /// transcript to the next launch, which finishes it with no click.
    func stopForQuit() async {
        guard let session = beginStop() else { return }
        let end = wallSeconds(of: session)
        await update(session.id) { $0.end(atWallSeconds: end) }
        live = nil
        AppLogger.shared.log(.info, "meeting stopped for quit id=\(session.id.uuidString)")
        trackEnd(of: session, atWallSeconds: end, cause: .quit)
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

    /// Call detection runs from launch, unless the user chose Do Nothing.
    private func updateCallDetection() {
        guard launched else { return }
        if settings.callStartAction == .doNothing {
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
        }
    }

    private func startAutomatically(_ app: MeetingCallApp) async {
        await startForCall(app, source: .automatic)
        guard live != nil else { return }
        let window = environment.callCardDurations.cancel
        showCard(.startedAutomatically(app, cancelEndsAt: environment.now().addingTimeInterval(window)), for: window)
    }

    private func startForCall(_ app: MeetingCallApp, source: MeetingStartSource) async {
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

    /// Closes the card that the user answered, or that closed by itself, and
    /// counts how it closed.
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
        detector.dictationChanged(active: active)
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

    private func trackEnd(of session: MeetingSession, atWallSeconds end: Double, cause: MeetingStopCause) {
        let recorded = MeetingTimeline(pauses: session.record.pauses).audioSeconds(forWallSeconds: end)
        analytics.track(.meetingEnded(
            durationMs: Int(recorded / 60) * 60_000,
            tracks: MeetingTracks(session.workingTracks),
            reason: cause.analyticsReason
        ))
    }

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
        let started = ContinuousClock.now
        defer {
            finishing.remove(id)
            transcribers[id] = nil
        }
        let outcome: MeetingTranscriptOutcome
        var segments = 0
        do {
            segments = try await run(transcriber).count
            outcome = segments == 0 ? .noSpeech : .done
            await store.deleteAudio(of: id)
            await update(id) { $0.status = .summarizing }
            summaries.enqueue(id)
        } catch {
            AppLogger.shared.log(.error, "meeting transcript not finished id=\(id.uuidString) error=\(error.localizedDescription)")
            outcome = .failed
            await update(id) { $0.status = .interrupted }
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
            Task { await stop(.diskFull) }
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
