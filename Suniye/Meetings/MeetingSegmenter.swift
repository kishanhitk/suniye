import Foundation

/// A piece of one track for the speech model.
struct MeetingAudioChunk: Equatable, Sendable {
    let track: MeetingTrack
    /// Sample position of the first sample in the track's audio file.
    let start: Int
    let samples: [Float]
    /// False when no 100 ms window rose above `MeetingSegmenter.quietFloor`:
    /// the chunk is silence and is not decoded.
    let hasSound: Bool

    var end: Int {
        start + samples.count
    }
}

/// Cuts one track into chunks while the meeting records. A chunk ends at the
/// first pause after `minimumSamples`, or, at `maximumSamples`, at the
/// quietest 100 ms of its last 5 s (`AudioChunker`), so a cut rarely splits a
/// word. Chunks follow each other with no gap and no overlap.
struct MeetingSegmenter {
    static let minimumSamples = 2 * MeetingAudioFormat.sampleRate
    static let maximumSamples = 12 * MeetingAudioFormat.sampleRate
    static let windowSamples = AudioChunker.energyWindowSamples
    /// Three quiet windows in a row (300 ms) make a pause.
    static let pauseWindows = 3
    /// A window is quiet below a tenth (-20 dB) of the chunk's loudest window,
    /// and always below `quietFloor` (about -60 dBFS).
    static let quietRatio: Float = 0.1
    static let quietFloor: Float = 0.001

    let track: MeetingTrack
    private var pending: [Float] = []
    private var pendingStart: Int
    private var analyzedWindows = 0
    private var loudest: Float = 0
    private var quietRun = 0

    init(track: MeetingTrack, startPosition: Int = 0) {
        self.track = track
        pendingStart = startPosition
    }

    /// `position` is where `samples` start in the track's file. Audio that does
    /// not continue the chunk in progress ends that chunk first.
    mutating func append(_ samples: [Float], at position: Int) -> [MeetingAudioChunk] {
        var chunks: [MeetingAudioChunk] = []
        if position != pendingStart + pending.count {
            if let chunk = flush() {
                chunks.append(chunk)
            }
            pendingStart = position
        }
        pending += samples
        while let chunk = nextChunk() {
            chunks.append(chunk)
        }
        return chunks
    }

    /// Ends the chunk in progress, for a pause or the end of the meeting.
    mutating func flush() -> MeetingAudioChunk? {
        guard !pending.isEmpty else { return nil }
        return cut(at: pending.count)
    }

    private mutating func nextChunk() -> MeetingAudioChunk? {
        while (analyzedWindows + 1) * Self.windowSamples <= pending.count {
            let window = analyzedWindows * Self.windowSamples ..< (analyzedWindows + 1) * Self.windowSamples
            analyzedWindows += 1
            let level = Self.rms(pending[window])
            loudest = max(loudest, level)
            let quiet = level < max(Self.quietFloor, loudest * Self.quietRatio)
            quietRun = quiet ? quietRun + 1 : 0
            // Silence counts as one long pause, so a silent track still moves
            // forward in 2 s steps.
            if quietRun >= Self.pauseWindows, window.upperBound >= Self.minimumSamples {
                return cut(at: window.upperBound)
            }
            if window.upperBound >= Self.maximumSamples {
                let searched = (Self.maximumSamples - AudioChunker.boundarySearchSamples) ..< Self.maximumSamples
                let quietest = AudioChunker.quietestPoint(in: searched) { Self.rms(pending[$0]) }
                return cut(at: quietest)
            }
        }
        return nil
    }

    /// Returns `pending[..<position]` as a chunk and analyzes the rest again
    /// as the start of the next chunk.
    private mutating func cut(at position: Int) -> MeetingAudioChunk {
        let samples = Array(pending[..<position])
        var hasSound = false
        for start in stride(from: 0, to: samples.count, by: Self.windowSamples) {
            let end = min(start + Self.windowSamples, samples.count)
            if Self.rms(samples[start ..< end]) >= Self.quietFloor {
                hasSound = true
                break
            }
        }
        let chunk = MeetingAudioChunk(track: track, start: pendingStart, samples: samples, hasSound: hasSound)
        pending.removeFirst(position)
        pendingStart += position
        analyzedWindows = 0
        loudest = 0
        quietRun = 0
        return chunk
    }

    static func rms(_ samples: ArraySlice<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for sample in samples {
            sum += sample * sample
        }
        return (sum / Float(samples.count)).squareRoot()
    }
}
