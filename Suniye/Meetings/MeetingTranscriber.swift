import Foundation

/// Turns the audio of one meeting into stored transcript segments: while the
/// meeting records, and later for a meeting that the app did not finish.
///
/// - The recorder's output arrives in order through `enqueue`.
/// - One chunk decodes at a time, the earliest first across both tracks,
///   through the speech engine that dictation uses.
/// - A chunk whose decode fails is tried again after `retryDelay`: a decode
///   that arrives while the router unloads the old engine of a model switch
///   fails once.
actor MeetingTranscriber {
    enum Event: Equatable, Sendable {
        case segment(MeetingSegment)
        /// Every chunk of the track before this sample position is decoded.
        case decodedThrough(MeetingTrack, Int)
    }

    static let maximumAttempts = 5
    /// Audio read per step when the app finishes a meeting from its files.
    static let replayStepSamples = 60 * MeetingAudioFormat.sampleRate

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
    private let engineName: @Sendable () async -> String
    private let mayDecode: @Sendable () async -> Bool
    private let retryDelay: Duration
    private let onEvent: @Sendable (Event) -> Void
    private let input: AsyncStream<MeetingRecorderOutput>
    private nonisolated let inputContinuation: AsyncStream<MeetingRecorderOutput>.Continuation

    private var segmenters: [MeetingTrack: MeetingSegmenter]
    private var pending: [MeetingAudioChunk] = []
    private var attempts: [ChunkID: Int] = [:]
    private var consumer: Task<Void, Never>?
    private var decoder: Task<Void, Never>?
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    private var stats = Stats()
    private var isCanceled = false

    init(
        meetingID: UUID,
        tracks: [MeetingTrack],
        store: MeetingStore,
        engine: TranscriptionServiceProtocol,
        engineName: @escaping @Sendable () async -> String,
        mayDecode: @escaping @Sendable () async -> Bool,
        retryDelay: Duration = .seconds(1),
        onEvent: @escaping @Sendable (Event) -> Void
    ) {
        self.meetingID = meetingID
        self.tracks = tracks
        self.store = store
        self.engine = engine
        self.engineName = engineName
        self.mayDecode = mayDecode
        self.retryDelay = retryDelay
        self.onEvent = onEvent
        (input, inputContinuation) = AsyncStream.makeStream(of: MeetingRecorderOutput.self)
        segmenters = Dictionary(uniqueKeysWithValues: tracks.map { ($0, MeetingSegmenter(track: $0)) })
    }

    /// Starts reading the audio of a meeting that records now.
    func start() {
        guard consumer == nil else { return }
        consumer = Task { [input] in
            for await output in input {
                process(output)
            }
        }
    }

    nonisolated func enqueue(_ output: MeetingRecorderOutput) {
        inputContinuation.yield(output)
    }

    /// For a recording that is thrown away: stops reading and decoding, and
    /// returns when nothing writes to the store any more.
    func cancel() async {
        isCanceled = true
        pending = []
        inputContinuation.finish()
        await consumer?.value
        await decoder?.value
    }

    /// Asks `mayDecode` again. Call it when its answer can have changed to
    /// yes. Audio that arrived while the answer was no waits until then.
    func wake() {
        decodeIfIdle()
    }

    /// Decodes the rest after the meeting stopped and returns the final
    /// transcript, which is also stored. With `end`, a line that starts at or
    /// after that sample position goes.
    func finish(keepingAudioBefore end: Int? = nil) async throws -> [MeetingSegment] {
        inputContinuation.finish()
        await consumer?.value
        flushSegmenters()
        await waitUntilDecoded()
        return try await finalize(keepingAudioBefore: end)
    }

    /// For a meeting that the app did not finish: decodes the audio after the
    /// last stored segment of each track, in steps so that memory stays small,
    /// and returns the final transcript.
    func recover() async throws -> [MeetingSegment] {
        let stored = await store.segments(of: meetingID)
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
        var position = resumeAt.values.min() ?? end
        while position < end {
            let stepEnd = position + Self.replayStepSamples
            for (track, from) in resumeAt {
                let lower = max(position, from)
                guard lower < stepEnd else { continue }
                let samples = try MeetingAudioFileReader.samples(at: store.audioURL(track, for: meetingID), range: lower ..< stepEnd)
                if !samples.isEmpty {
                    process(.samples(track, samples, position: lower))
                }
            }
            await waitUntilDecoded()
            position = stepEnd
        }
        flushSegmenters()
        await waitUntilDecoded()
        return try await finalize(keepingAudioBefore: nil)
    }

    // MARK: - Chunks

    private func process(_ output: MeetingRecorderOutput) {
        guard !isCanceled else { return }
        switch output {
        case let .samples(track, samples, position):
            if let chunks = segmenters[track]?.append(samples, at: position) {
                pending += chunks
            }
            decodeIfIdle()
        case .paused:
            flushSegmenters()
        }
    }

    private func flushSegmenters() {
        for track in tracks {
            if let chunk = segmenters[track]?.flush() {
                pending.append(chunk)
            }
        }
        decodeIfIdle()
    }

    private func decodeIfIdle() {
        guard decoder == nil else { return }
        guard !pending.isEmpty else {
            resumeIdleWaiters()
            return
        }
        decoder = Task { await decodePending() }
    }

    /// Stops when nothing is pending or `mayDecode` says no; `wake()` or the
    /// next chunk starts it again.
    private func decodePending() async {
        while !isCanceled, earliestPendingIndex() != nil, await mayDecode(), let index = earliestPendingIndex() {
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

    /// The call track first when two chunks start together: a "You" line
    /// waits for the call track anyway.
    private func earliestPendingIndex() -> Int? {
        pending.indices.min { (pending[$0].start, pending[$0].track.rawValue) < (pending[$1].start, pending[$1].track.rawValue) }
    }

    /// Returns false when the chunk should be tried again.
    private func decode(_ chunk: MeetingAudioChunk) async -> Bool {
        guard chunk.hasSound else {
            stats.silent += 1
            finished(chunk)
            return true
        }
        let id = ChunkID(track: chunk.track, start: chunk.start)
        let name = await engineName()
        let started = ContinuousClock.now
        do {
            let text = try await engine.transcribe(samples: chunk.samples, sampleRate: MeetingAudioFormat.sampleRate, purpose: .meeting)
            stats.decodeSeconds += (ContinuousClock.now - started) / .seconds(1)
            attempts[id] = nil
            await save(text, of: chunk, engine: name)
            finished(chunk)
            return true
        } catch {
            let attempt = (attempts[id] ?? 0) + 1
            guard attempt < Self.maximumAttempts else {
                attempts[id] = nil
                stats.failed += 1
                AppLogger.shared.log(.error, "meeting transcript gave up on a chunk id=\(meetingID.uuidString) track=\(chunk.track.rawValue) start=\(chunk.start) error=\(error.localizedDescription)")
                finished(chunk)
                return true
            }
            attempts[id] = attempt
            stats.retries += 1
            return false
        }
    }

    private func save(_ text: String, of chunk: MeetingAudioChunk, engine name: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let segment = MeetingSegment(
            id: UUID(),
            track: chunk.track,
            audioStart: chunk.start,
            audioEnd: chunk.end,
            text: trimmed,
            engine: name
        )
        do {
            try await store.appendSegment(segment, to: meetingID)
            stats.segments += 1
            onEvent(.segment(segment))
        } catch {
            AppLogger.shared.log(.error, "meeting transcript could not save a segment id=\(meetingID.uuidString) error=\(error.localizedDescription)")
        }
    }

    private func finished(_ chunk: MeetingAudioChunk) {
        stats.chunks += 1
        onEvent(.decodedThrough(chunk.track, chunk.end))
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

    private func finalize(keepingAudioBefore end: Int?) async throws -> [MeetingSegment] {
        let stored = await store.segments(of: meetingID)
        let kept = end.map { end in stored.filter { $0.audioStart < end } } ?? stored
        let callPlayedOnSpeakers = await store.record(meetingID)?.callPlayedOnSpeakers ?? false
        let transcript = MeetingTranscript.final(kept, callPlayedOnSpeakers: callPlayedOnSpeakers)
        if transcript.count != stored.count {
            try await store.replaceSegments(transcript, of: meetingID)
        }
        AppLogger.shared.log(
            .info,
            "meeting transcript finished id=\(meetingID.uuidString) chunks=\(stats.chunks) silent=\(stats.silent) segments=\(stats.segments) cut=\(stored.count - kept.count) echoes=\(kept.count - transcript.count) retries=\(stats.retries) failed=\(stats.failed) decodeSeconds=\(String(format: "%.1f", stats.decodeSeconds))"
        )
        return transcript
    }
}
