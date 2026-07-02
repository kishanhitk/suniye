import Foundation

/// Drives the live transcription preview while recording: ticks on a fixed interval,
/// snapshots the accumulated audio, and decodes it into a partial transcript.
/// A tick is skipped (never queued) while a decode is in flight, and `stop()`
/// suppresses results from any decode still running so a stale partial can never
/// surface after recording ends.
@MainActor
final class PartialTranscriptionScheduler {
    /// Partial decodes only cover the most recent window of audio. This keeps the
    /// per-tick decode cost bounded for arbitrarily long dictations; the indicator
    /// shows the transcript tail, so older audio adds nothing visible.
    static let maxWindowSeconds: Double = 30
    static let defaultTickInterval: TimeInterval = 0.7
    static let previewTailMaxCharacters = 80

    private let tickInterval: TimeInterval
    private var snapshotProvider: (() async -> (samples: [Float], sampleRate: Int)?)?
    private var decode: (([Float], Int) async throws -> String)?
    private var onPartial: ((String) -> Void)?
    private var tickTask: Task<Void, Never>?
    private var generation = 0
    private(set) var isDecodeInFlight = false

    init(tickInterval: TimeInterval = PartialTranscriptionScheduler.defaultTickInterval) {
        self.tickInterval = tickInterval
    }

    var isActive: Bool {
        tickTask != nil
    }

    func start(
        snapshotProvider: @escaping () async -> (samples: [Float], sampleRate: Int)?,
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
                try? await Task.sleep(nanoseconds: UInt64(max(0, interval) * 1_000_000_000))
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

    static func previewTail(_ text: String, maxCharacters: Int = previewTailMaxCharacters) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxCharacters else {
            return trimmed
        }
        return "…" + String(trimmed.suffix(maxCharacters))
    }

    private func performTick(generation: Int) async {
        guard generation == self.generation, !isDecodeInFlight else {
            return
        }
        guard let snapshotProvider, let decode else {
            return
        }
        isDecodeInFlight = true
        defer { isDecodeInFlight = false }

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
