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

/// Writes the transcript of one meeting from its audio files, after the
/// recording stops or after a quit or a crash.
///
/// - The audio after the last stored segment of each track is read in steps
///   of `stepSamples`, so memory stays small. A step reports its end as
///   progress.
/// - One chunk decodes at a time, the earliest first across both tracks,
///   through the speech engine, and only while `mayDecode` says yes.
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
        var failed = 0
        var decodeSeconds: Double = 0
    }

    nonisolated let meetingID: UUID
    nonisolated let tracks: [MeetingTrack]
    private let store: MeetingStore
    private let engine: TranscriptionServiceProtocol
    private let mayDecode: @Sendable () async -> Bool
    private let retryDelay: Duration
    private let onProgress: @Sendable (MeetingTranscriptProgress) -> Void

    private var segmenters: [MeetingTrack: MeetingSegmenter] = [:]
    private var pending: [MeetingAudioChunk] = []
    private var attempts: [ChunkID: Int] = [:]
    /// For each track, the start of the earliest chunk whose text is not
    /// stored.
    private var holes: [MeetingTrack: Int] = [:]
    private var decoder: Task<Void, Never>?
    /// Set by `wake()`, so that a wake during an `await mayDecode()` is not lost.
    private var woken = false
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    private var stats = Stats()

    init(
        meetingID: UUID,
        tracks: [MeetingTrack],
        store: MeetingStore,
        engine: TranscriptionServiceProtocol,
        mayDecode: @escaping @Sendable () async -> Bool,
        retryDelay: Duration = .seconds(1),
        onProgress: @escaping @Sendable (MeetingTranscriptProgress) -> Void
    ) {
        self.meetingID = meetingID
        self.tracks = tracks
        self.store = store
        self.engine = engine
        self.mayDecode = mayDecode
        self.retryDelay = retryDelay
        self.onProgress = onProgress
    }

    /// Asks `mayDecode` again. Call it when its answer can have changed to
    /// yes. Audio waits while the answer is no.
    func wake() {
        woken = true
        decodeIfIdle()
    }

    /// Decodes the audio after the last stored segment of each track and
    /// returns the final transcript, which is also stored.
    func transcribe() async throws -> [MeetingSegment] {
        let stored = await store.segments(of: meetingID)
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
        while earliestPendingIndex() != nil {
            woken = false
            guard await mayDecode() else {
                if woken { continue }
                break
            }
            guard let index = earliestPendingIndex() else { break }
            let chunk = pending.remove(at: index)
            if await !decode(chunk) {
                pending.append(chunk)
                try? await Task.sleep(for: retryDelay)
            }
        }
        decoder = nil
        if pending.isEmpty {
            resumeIdleWaiters()
        }
    }

    private func earliestPendingIndex() -> Int? {
        pending.indices.min { (pending[$0].start, pending[$0].track) < (pending[$1].start, pending[$1].track) }
    }

    /// Returns false when the chunk should be tried again.
    private func decode(_ chunk: MeetingAudioChunk) async -> Bool {
        // A line stored past a failed chunk would make the next finish start
        // after it, so the rest of the track waits for that finish.
        if let hole = holes[chunk.track], chunk.start > hole {
            return true
        }
        guard chunk.hasSound else {
            stats.silent += 1
            stats.chunks += 1
            return true
        }
        let id = ChunkID(track: chunk.track, start: chunk.start)
        let started = ContinuousClock.now
        do {
            let samples = try MeetingAudioFileReader.samples(at: store.audioURL(chunk.track, for: meetingID), range: chunk.start ..< chunk.end)
            let text = try await engine.transcribe(samples: samples, sampleRate: MeetingAudioFormat.sampleRate, purpose: .meeting)
            stats.decodeSeconds += (ContinuousClock.now - started) / .seconds(1)
            attempts[id] = nil
            await save(text, of: chunk)
            stats.chunks += 1
            return true
        } catch {
            let attempt = (attempts[id] ?? 0) + 1
            guard attempt < Self.maximumAttempts else {
                attempts[id] = nil
                stats.failed += 1
                stats.chunks += 1
                AppLogger.shared.log(.error, "meeting transcript gave up on a chunk id=\(meetingID.uuidString) track=\(chunk.track.rawValue) start=\(chunk.start) error=\(error.localizedDescription)")
                markHole(at: chunk)
                return true
            }
            attempts[id] = attempt
            stats.retries += 1
            return false
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
            try await store.appendSegment(segment, to: meetingID)
            stats.segments += 1
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
        guard decoder != nil || !pending.isEmpty else { return }
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
        let stored = await store.segments(of: meetingID)
        let transcript = MeetingTranscript.final(stored, of: record)
        if transcript.count != stored.count {
            try await store.replaceSegments(transcript, of: meetingID)
        }
        AppLogger.shared.log(
            .info,
            "meeting transcript finished id=\(meetingID.uuidString) chunks=\(stats.chunks) silent=\(stats.silent) segments=\(stats.segments) dropped=\(stored.count - transcript.count) retries=\(stats.retries) failed=\(stats.failed) decodeSeconds=\(String(format: "%.1f", stats.decodeSeconds))"
        )
        return transcript
    }
}
