import Foundation

/// How much of a meeting's audio the transcript has, in samples.
struct MeetingTranscriptProgress: Equatable, Sendable {
    let done: Int
    let total: Int

    var fraction: Double {
        total > 0 ? min(1, Double(done) / Double(total)) : 0
    }

    /// "12 of 60 min": the whole minutes done, and the total rounded like the
    /// meeting length.
    var minutesText: String {
        let samplesPerMinute = 60 * MeetingAudioFormat.sampleRate
        let totalMinutes = max(1, Int((Double(total) / Double(samplesPerMinute)).rounded()))
        let doneMinutes = done >= total ? totalMinutes : min(totalMinutes, done / samplesPerMinute)
        return "\(doneMinutes) of \(totalMinutes) min"
    }
}

/// What a recording hands its live transcript, in the recorder's order.
enum MeetingLiveInput: Sendable {
    case audio(MeetingRecorderOutput)
    /// The recording paused after the audio before it.
    case paused
    /// The track's source failed, so its audio can stop.
    case trackFailed(MeetingTrack)
    /// The track's source started again after a failure.
    case trackStarted(MeetingTrack)
}

/// The lines that a recording shows. They only grow at the end: a line never
/// changes, moves or goes during the call.
struct MeetingLiveTranscript: Equatable, Sendable {
    var lines: [MeetingSegment] = []
    /// No track adds a line that starts before this sample position.
    var completeThrough = 0
}

/// Writes the transcript of one meeting from its audio.
///
/// - While the meeting records (`startLive`), the recorder's audio arrives
///   through `enqueue` and is cut into chunks as it arrives. Lines show by
///   `MeetingLiveTranscript`'s rule, see `releaseLines()`.
/// - `transcribe()` decodes the audio after the last stored line of each
///   track from the files: after the recording stops (`endLive` first), or
///   after a quit or a crash. It reads in steps of `stepSamples`, so memory
///   stays small, and reports each step's end as progress.
/// - One chunk decodes at a time, the earliest first across both tracks,
///   through the speech engine, and only while `mayDecode` says yes.
/// - `interruptDecode()` stops the chunk in flight, when its engine can stop
///   it; the chunk decodes again, with all its attempts left.
/// - A chunk whose decode fails is tried again after `retryDelay`: a decode
///   that arrives while the router unloads the old engine of a model switch
///   fails once.
/// - A chunk whose text is not stored (its decode kept failing, or the store
///   could not save its line) makes the transcript fail.
actor MeetingTranscriber {
    enum TranscriptError: LocalizedError, Equatable {
        case incomplete

        var errorDescription: String? {
            "Part of the audio has no transcript yet."
        }
    }

    static let maximumAttempts = 5
    static let stepSamples = 60 * MeetingAudioFormat.sampleRate

    private struct ChunkID: Hashable {
        let track: MeetingTrack
        let start: Int
    }

    private struct Stats {
        var chunks = 0
        var silent = 0
        var segments = 0
        var retries = 0
        var interrupted = 0
        var failed = 0
        var decodeSeconds: Double = 0
    }

    private enum ChunkResult {
        /// The chunk has its line, or none, or a hole.
        case done
        case failed
        case interrupted
    }

    /// The state that only the live phase uses.
    private struct Live {
        var onChange: @Sendable (MeetingLiveTranscript) -> Void
        var shown = MeetingLiveTranscript()
        /// Stored lines that are not shown yet and not dropped as echo.
        var unreleased: [MeetingSegment] = []
        /// Every stored line of the call track, for the echo rule.
        var callLines: [MeetingSegment] = []
        /// For each track, the end of the audio that arrived.
        var received: [MeetingTrack: Int] = [:]
        /// For each track, the end of the audio before its first chunk with
        /// no result; it stops at a hole.
        var heard: [MeetingTrack: Int] = [:]
        /// Tracks whose source failed; one opens again when its source
        /// starts or its audio comes, whichever is first.
        var closed: Set<MeetingTrack> = []
        /// Opened tracks whose first audio gets a cut of its own.
        var cutsFirstBlock: Set<MeetingTrack> = []
        var callPlaysOnSpeakers: Bool
    }

    nonisolated let meetingID: UUID
    nonisolated let tracks: [MeetingTrack]
    private let store: MeetingStore
    private let file: MeetingStore.SegmentFile
    private var engine: TranscriptionServiceProtocol?
    private var mayDecode: @Sendable () async -> Bool = { false }
    private let retryDelay = Duration.seconds(1)
    private let onProgress: @Sendable (MeetingTranscriptProgress) -> Void

    private var segmenters: [MeetingTrack: MeetingSegmenter] = [:]
    private var pending: [MeetingAudioChunk] = []
    private var inFlight: MeetingAudioChunk?
    private var attempts: [ChunkID: Int] = [:]
    /// For each track, the start of the earliest chunk whose text is not
    /// stored.
    private var holes: [MeetingTrack: Int] = [:]
    private var decoder: Task<Void, Never>?
    /// The engine call of the chunk in flight.
    private var engineCall: Task<String, Error>?
    /// Set by `wake()`, so that a wake during an `await mayDecode()` is not lost.
    private var woken = false
    /// Counts `interruptDecode()` calls, so that one during an
    /// `await mayDecode()` is not lost.
    private var interrupts = 0
    /// Set by `endLive()` while the chunk in flight finishes.
    private var holdsChunks = false
    private var cancelled = false
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    private var stats = Stats()

    private var live: Live?
    private let liveInput: AsyncStream<MeetingLiveInput>
    private nonisolated let liveInputContinuation: AsyncStream<MeetingLiveInput>.Continuation
    private var liveConsumer: Task<Void, Never>?

    init(
        meetingID: UUID,
        tracks: [MeetingTrack],
        store: MeetingStore,
        file: MeetingStore.SegmentFile = .transcript,
        onProgress: @escaping @Sendable (MeetingTranscriptProgress) -> Void
    ) {
        self.meetingID = meetingID
        self.tracks = tracks
        self.store = store
        self.file = file
        self.onProgress = onProgress
        (liveInput, liveInputContinuation) = AsyncStream.makeStream(of: MeetingLiveInput.self)
    }

    /// Chunks decode on `engine` while `mayDecode` says yes. Until this is
    /// called, chunks wait.
    func use(_ engine: TranscriptionServiceProtocol, mayDecode: @escaping @Sendable () async -> Bool) {
        self.engine = engine
        self.mayDecode = mayDecode
        wake()
    }

    /// Asks `mayDecode` again. Call it when its answer can have changed to
    /// yes. Audio waits while the answer is no.
    func wake() {
        woken = true
        decodeIfIdle()
    }

    /// Stops the chunk in flight, when its engine can stop it. Call it when
    /// `mayDecode` says no from now on: the chunk decodes again when it says
    /// yes, and the interrupt does not count as one of its attempts.
    func interruptDecode() {
        interrupts += 1
        engineCall?.cancel()
    }

    // MARK: - Live phase

    /// Starts cutting the audio that `enqueue` hands over. `onChange` gets
    /// each new state of the shown lines.
    func startLive(callPlaysOnSpeakers: Bool, onChange: @escaping @Sendable (MeetingLiveTranscript) -> Void) {
        guard live == nil, liveConsumer == nil else { return }
        live = Live(onChange: onChange, callPlaysOnSpeakers: callPlaysOnSpeakers)
        for track in tracks {
            segmenters[track] = MeetingSegmenter(track: track)
        }
        liveConsumer = Task { [liveInput] in
            for await input in liveInput {
                process(input)
            }
        }
    }

    /// Called on the recorder's queue, so the inputs keep its order.
    nonisolated func enqueue(_ input: MeetingLiveInput) {
        liveInputContinuation.yield(input)
    }

    /// The call plays on speakers from now on: a "You" line shows only after
    /// the echo rule had all the call lines near it.
    func callPlaysOnSpeakers() {
        guard live?.callPlaysOnSpeakers == false else { return }
        live?.callPlaysOnSpeakers = true
        releaseLines()
    }

    /// Ends the live phase at Stop: no chunk starts after it, the chunk in
    /// flight finishes and keeps its line, and the chunks that wait are
    /// dropped, so `transcribe()` decodes them from the files.
    func endLive() async {
        guard live != nil else { return }
        holdsChunks = true
        live = nil
        liveInputContinuation.finish()
        await liveConsumer?.value
        liveConsumer = nil
        await decoder?.value
        holdsChunks = false
        pending = []
        segmenters = [:]
        holes = [:]
        attempts = [:]
    }

    /// Ends the transcriber for a quit or a deleted meeting: no chunk starts
    /// and no line is stored after it. `idle()` waits for a chunk in flight.
    func cancel() {
        cancelled = true
        live = nil
        liveInputContinuation.finish()
        pending = []
        segmenters = [:]
        decoder?.cancel()
        resumeIdleWaiters()
    }

    /// Returns when no chunk decodes, so its engine can unload.
    func idle() async {
        await decoder?.value
    }

    private func process(_ input: MeetingLiveInput) {
        guard live != nil else { return }
        switch input {
        case let .audio(output):
            let track = output.track
            guard segmenters[track] != nil else { return }
            if live?.closed.remove(track) != nil {
                live?.cutsFirstBlock.insert(track)
            }
            let cutsBlock = live?.cutsFirstBlock.remove(track) != nil
            if let chunks = segmenters[track]?.append(MeetingAudioFormat.stored(output.samples), at: output.position) {
                pending += chunks
            }
            // The recorder pads a gap with silence in a block of its own;
            // a cut after it keeps the silence out of the next line.
            if cutsBlock, let chunk = segmenters[track]?.flush() {
                pending.append(chunk)
            }
            live?.received[track] = output.position + output.samples.count
        case .paused:
            flushSegmenters()
        case let .trackFailed(track):
            live?.closed.insert(track)
            live?.cutsFirstBlock.remove(track)
            if let chunk = segmenters[track]?.flush() {
                pending.append(chunk)
            }
        case let .trackStarted(track):
            if live?.closed.remove(track) != nil {
                live?.cutsFirstBlock.insert(track)
            }
        }
        decodeIfIdle()
        releaseLines()
    }

    /// No line of `track` can start before the returned position: the
    /// earliest audio with no result, or the end of the audio received. Nil
    /// for a failed track whose audio all has a result.
    private func bound(of track: MeetingTrack, in live: Live) -> Int? {
        var starts = pending.filter { $0.track == track }.map(\.start)
        if let start = segmenters[track]?.unresolvedStart {
            starts.append(start)
        }
        if let chunk = inFlight, chunk.track == track {
            starts.append(chunk.start)
        }
        if let earliest = starts.min() {
            return earliest
        }
        return live.closed.contains(track) ? nil : live.received[track] ?? 0
    }

    /// Shows the stored lines that start before every track's bound, in time
    /// order. With the call on speakers, a "You" line also waits until the
    /// call track has a result past its end and the echo window; the echo
    /// rule then drops it or shows it. A line that starts before the lines
    /// already shown waits for the final transcript.
    private func releaseLines() {
        guard var live else { return }
        let bounds = tracks.compactMap { bound(of: $0, in: live) }
        var release = bounds.min() ?? live.received.values.max() ?? 0
        let checksEcho = live.callPlaysOnSpeakers && tracks.contains(.them)
        // A failed call track adds no line before it returns, so its lines
        // are all there.
        let callLinesComplete = live.closed.contains(.them) && bound(of: .them, in: live) == nil && holes[.them] == nil
        let from = live.shown.completeThrough
        var added: [MeetingSegment] = []
        var dropped: Set<UUID> = []
        for line in MeetingTranscript.ordered(live.unreleased) where line.audioStart < release {
            if checksEcho, line.track == .you {
                guard callLinesComplete || (live.heard[.them] ?? 0) > line.audioEnd + MeetingTranscript.echoWindowSamples else {
                    release = line.audioStart
                    added.removeAll { $0.audioStart >= release }
                    break
                }
                if MeetingTranscript.isEcho(line, call: live.callLines) {
                    dropped.insert(line.id)
                    continue
                }
            }
            added.append(line)
        }
        guard release > from else { return }
        let gone = dropped.union(added.map(\.id))
        live.unreleased.removeAll { gone.contains($0.id) }
        live.shown.lines += added
        live.shown.completeThrough = release
        self.live = live
        live.onChange(live.shown)
    }

    // MARK: - Final phase

    /// Decodes the audio after the last stored segment of each track and
    /// returns the final transcript, which is also stored.
    func transcribe() async throws -> [MeetingSegment] {
        let stored = await store.segments(of: meetingID, in: file)
        // The files hold no pause; a pause ends the chunk in progress there.
        let pauses = await store.record(meetingID)?.pauses ?? []
        let timeline = MeetingTimeline(pauses: pauses)
        let pauseCuts = pauses.map { timeline.audioPosition(forWallSeconds: $0.start) }
        var resumeAt: [MeetingTrack: Int] = [:]
        var end = 0
        for track in tracks {
            let url = store.audioURL(track, for: meetingID)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let from = stored.filter { $0.track == track }.map(\.audioEnd).max() ?? 0
            resumeAt[track] = from
            segmenters[track] = MeetingSegmenter(track: track, startPosition: from)
            end = max(end, try MeetingAudioFileReader.sampleCount(at: url))
        }
        var position = min(resumeAt.values.min() ?? end, end)
        onProgress(MeetingTranscriptProgress(done: position, total: end))
        while position < end {
            let nextCut = pauseCuts.filter { $0 > position }.min()
            let stepEnd = min(position + Self.stepSamples, nextCut ?? .max, end)
            for (track, from) in resumeAt {
                let lower = max(position, from)
                guard lower < stepEnd else { continue }
                let samples = try MeetingAudioFileReader.samples(at: store.audioURL(track, for: meetingID), range: lower ..< stepEnd)
                if !samples.isEmpty, let chunks = segmenters[track]?.append(samples, at: lower) {
                    pending += chunks
                }
            }
            if stepEnd == nextCut {
                flushSegmenters()
            }
            decodeIfIdle()
            await waitUntilDecoded()
            position = stepEnd
            onProgress(MeetingTranscriptProgress(done: position, total: end))
        }
        flushSegmenters()
        decodeIfIdle()
        await waitUntilDecoded()
        try requireComplete()
        return try await finalize()
    }

    // MARK: - Chunks

    private func flushSegmenters() {
        for track in tracks {
            if let chunk = segmenters[track]?.flush() {
                pending.append(chunk)
            }
        }
    }

    private func decodeIfIdle() {
        guard decoder == nil else { return }
        guard !pending.isEmpty else {
            resumeIdleWaiters()
            return
        }
        decoder = Task { await decodePending() }
    }

    /// Stops when nothing is pending or `mayDecode` says no; `wake()` starts
    /// it again.
    private func decodePending() async {
        while !holdsChunks, !cancelled, earliestPendingIndex() != nil {
            woken = false
            let interruptsBefore = interrupts
            guard engine != nil, await mayDecode() else {
                if woken { continue }
                break
            }
            // An interrupt during `mayDecode()` makes its yes old.
            guard interrupts == interruptsBefore else { continue }
            guard !holdsChunks, !cancelled, let index = earliestPendingIndex(), let engine else { break }
            let chunk = pending.remove(at: index)
            inFlight = chunk
            let result = await decode(chunk, on: engine)
            if result != .done {
                pending.append(chunk)
            }
            inFlight = nil
            releaseLines()
            if result == .failed {
                try? await Task.sleep(for: retryDelay)
            }
        }
        decoder = nil
        if pending.isEmpty || cancelled {
            resumeIdleWaiters()
        }
    }

    private func earliestPendingIndex() -> Int? {
        pending.indices.min { (pending[$0].start, pending[$0].track) < (pending[$1].start, pending[$1].track) }
    }

    private func decode(_ chunk: MeetingAudioChunk, on engine: TranscriptionServiceProtocol) async -> ChunkResult {
        // A line stored past a failed chunk would make the next finish start
        // after it, so the rest of the track waits for that finish.
        if let hole = holes[chunk.track], chunk.start > hole {
            return .done
        }
        guard chunk.hasSound else {
            stats.silent += 1
            stats.chunks += 1
            live?.heard[chunk.track] = chunk.end
            return .done
        }
        let id = ChunkID(track: chunk.track, start: chunk.start)
        let interruptsBefore = interrupts
        let started = ContinuousClock.now
        do {
            let samples = try MeetingAudioFileReader.samples(at: store.audioURL(chunk.track, for: meetingID), range: chunk.start ..< chunk.end)
            let text = try await decodeText(samples, on: engine)
            guard !cancelled else { return .done }
            stats.decodeSeconds += (ContinuousClock.now - started) / .seconds(1)
            attempts[id] = nil
            await save(text, of: chunk)
            stats.chunks += 1
            if holes[chunk.track] == nil {
                live?.heard[chunk.track] = chunk.end
            }
            return .done
        } catch {
            guard !cancelled else { return .done }
            guard interrupts == interruptsBefore else {
                stats.interrupted += 1
                return .interrupted
            }
            let attempt = (attempts[id] ?? 0) + 1
            guard attempt < Self.maximumAttempts else {
                attempts[id] = nil
                stats.failed += 1
                stats.chunks += 1
                AppLogger.shared.log(.error, "meeting transcript gave up on a chunk id=\(meetingID.uuidString) track=\(chunk.track.rawValue) start=\(chunk.start) error=\(error.localizedDescription)")
                markHole(at: chunk)
                return .done
            }
            attempts[id] = attempt
            stats.retries += 1
            return .failed
        }
    }

    /// The engine runs in a task of its own, which `interruptDecode()` and a
    /// cancel of the decoder both cancel.
    private func decodeText(_ samples: [Float], on engine: TranscriptionServiceProtocol) async throws -> String {
        let call = Task { try await engine.transcribe(samples: samples, sampleRate: MeetingAudioFormat.sampleRate, purpose: .meeting) }
        engineCall = call
        defer { engineCall = nil }
        return try await withTaskCancellationHandler {
            try await call.value
        } onCancel: {
            call.cancel()
        }
    }

    private func save(_ text: String, of chunk: MeetingAudioChunk) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let segment = MeetingSegment(
            id: UUID(),
            track: chunk.track,
            audioStart: chunk.start,
            audioEnd: chunk.end,
            text: trimmed
        )
        do {
            try await store.appendSegment(segment, to: meetingID, in: file)
            stats.segments += 1
            if live != nil {
                if segment.audioStart >= live?.shown.completeThrough ?? 0 {
                    live?.unreleased.append(segment)
                }
                if segment.track == .them {
                    live?.callLines.append(segment)
                }
            }
        } catch {
            AppLogger.shared.log(.error, "meeting transcript could not save a segment id=\(meetingID.uuidString) error=\(error.localizedDescription)")
            markHole(at: chunk)
        }
    }

    private func markHole(at chunk: MeetingAudioChunk) {
        holes[chunk.track] = min(holes[chunk.track] ?? chunk.start, chunk.start)
    }

    /// A track with a hole has no line from the hole on, so the next
    /// `transcribe()` decodes it again from there.
    private func requireComplete() throws {
        guard holes.isEmpty else { throw TranscriptError.incomplete }
    }

    private func waitUntilDecoded() async {
        guard !cancelled, decoder != nil || !pending.isEmpty else { return }
        await withCheckedContinuation { idleWaiters.append($0) }
    }

    private func resumeIdleWaiters() {
        let waiters = idleWaiters
        idleWaiters = []
        waiters.forEach { $0.resume() }
    }

    private func finalize() async throws -> [MeetingSegment] {
        guard let record = await store.record(meetingID) else {
            throw MeetingStore.StoreError.unknownMeeting(meetingID)
        }
        let stored = await store.segments(of: meetingID, in: file)
        let transcript = MeetingTranscript.filtered(stored, of: record)
        if transcript.count != stored.count {
            try await store.replaceSegments(transcript, of: meetingID, in: file)
        }
        AppLogger.shared.log(
            .info,
            "meeting transcript finished id=\(meetingID.uuidString) chunks=\(stats.chunks) silent=\(stats.silent) segments=\(stats.segments) dropped=\(stored.count - transcript.count) retries=\(stats.retries) interrupted=\(stats.interrupted) failed=\(stats.failed) decodeSeconds=\(String(format: "%.1f", stats.decodeSeconds))"
        )
        return transcript
    }
}
