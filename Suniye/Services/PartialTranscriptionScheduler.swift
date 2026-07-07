import Foundation

/// Drives the live transcription preview while recording: ticks on a fixed interval,
/// snapshots the accumulated audio, and decodes it into a partial transcript.
/// A tick is skipped (never queued) while a decode for the same session is in flight.
/// `stop()` suppresses the *result* of any decode still running — the decode work
/// itself is not cancelled, so on the TranscriptionService actor a final decode
/// requested right after stop can queue behind at most one partial decode. AppState
/// bounds that cost by only enabling partials for model families whose decode time
/// scales with input length (see `ASRModelFamily.supportsLivePreview`).
@MainActor
final class PartialTranscriptionScheduler {
    /// Partial decodes only cover the most recent window of audio. This keeps the
    /// per-tick decode cost bounded for arbitrarily long dictations; the indicator
    /// shows the transcript tail, so older audio adds nothing visible.
    nonisolated static let maxWindowSeconds: Double = 30
    nonisolated static let defaultTickInterval: TimeInterval = 0.7

    private let tickInterval: TimeInterval
    private var snapshotProvider: (() async -> AudioSampleSnapshot?)?
    private var decode: (([Float], Int) async throws -> String)?
    private var onPartial: ((String) -> Void)?
    private var tickTask: Task<Void, Never>?
    private var generation = 0
    /// Generation of the decode currently in flight, if any. Scoped per generation
    /// so a decode left over from a stopped session never blocks the first ticks of
    /// a quickly restarted one.
    private var inFlightGeneration: Int?

    init(tickInterval: TimeInterval = PartialTranscriptionScheduler.defaultTickInterval) {
        // Floor prevents a zero/negative interval from busy-spinning the main actor.
        self.tickInterval = max(0.01, tickInterval)
    }

    var isActive: Bool {
        tickTask != nil
    }

    var isDecodeInFlight: Bool {
        inFlightGeneration != nil
    }

    func start(
        snapshotProvider: @escaping () async -> AudioSampleSnapshot?,
        decode: @escaping ([Float], Int) async throws -> String,
        onPartial: @escaping (String) -> Void
    ) {
        stop()
        self.snapshotProvider = snapshotProvider
        self.decode = decode
        self.onPartial = onPartial
        let startedGeneration = generation
        let interval = tickInterval
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await self?.performTick(generation: startedGeneration)
            }
        }
    }

    func stop() {
        generation += 1
        tickTask?.cancel()
        tickTask = nil
        snapshotProvider = nil
        decode = nil
        onPartial = nil
    }

    /// Runs a single tick immediately. Exposed for deterministic tests; the interval
    /// loop started by `start` goes through the same path.
    func tickNow() async {
        await performTick(generation: generation)
    }

    private func performTick(generation: Int) async {
        guard generation == self.generation, inFlightGeneration != generation else {
            return
        }
        guard let snapshotProvider, let decode else {
            return
        }
        inFlightGeneration = generation
        defer {
            if inFlightGeneration == generation {
                inFlightGeneration = nil
            }
        }

        guard let snapshot = await snapshotProvider(), !snapshot.samples.isEmpty else {
            return
        }
        guard generation == self.generation else {
            return
        }
        guard let text = try? await decode(snapshot.samples, snapshot.sampleRate) else {
            return
        }
        guard generation == self.generation else {
            return
        }
        onPartial?(text)
    }
}
