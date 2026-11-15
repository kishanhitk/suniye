import Foundation

/// Samples `start ..< end` of one track's audio file.
struct MeetingAudioChunk: Equatable, Sendable {
    let track: MeetingTrack
    let start: Int
    let end: Int
    /// False when no 100 ms window rose above `MeetingAudioFormat.silenceLevel`.
    let hasSound: Bool
}

/// Cuts one track into chunks while the meeting records. A chunk ends at the
/// first pause after `minimumSamples`, or, at `maximumSamples`, at the
/// quietest window of its last `cutSearchSamples`, so a cut rarely splits a
/// word. Chunks follow each other with no gap and no overlap.
struct MeetingSegmenter {
    static let minimumSamples = 2 * MeetingAudioFormat.sampleRate
    static let maximumSamples = 12 * MeetingAudioFormat.sampleRate
    /// 100 ms.
    static let windowSamples = MeetingAudioFormat.sampleRate / 10
    static let cutSearchSamples = 5 * MeetingAudioFormat.sampleRate
    /// Three quiet windows in a row (300 ms) make a pause.
    static let pauseWindows = 3
    /// A window is quiet below a tenth (-20 dB) of the chunk's loudest window,
    /// and always below `MeetingAudioFormat.silenceLevel`.
    static let quietRatio: Float = 0.1

    let track: MeetingTrack
    private var pending: [Float] = []
    private var pendingStart: Int
    private var analyzedWindows = 0
    /// The level of each analyzed window of the chunk in progress.
    private var levels: [Float] = []
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
        // In steps, so a long block of silence does not make `pending` long.
        for start in stride(from: 0, to: samples.count, by: Self.maximumSamples) {
            pending += samples[start ..< min(start + Self.maximumSamples, samples.count)]
            while let chunk = nextChunk() {
                chunks.append(chunk)
            }
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
            let level = MeetingAudioFormat.rms(pending[window])
            levels.append(level)
            loudest = max(loudest, level)
            let quiet = level < max(MeetingAudioFormat.silenceLevel, loudest * Self.quietRatio)
            quietRun = quiet ? quietRun + 1 : 0
            // Silence counts as one long pause, so a silent track still moves
            // forward in 2 s steps.
            if quietRun >= Self.pauseWindows, window.upperBound >= Self.minimumSamples {
                return cut(at: window.upperBound)
            }
            if window.upperBound >= Self.maximumSamples {
                return cut(at: quietestCut())
            }
        }
        return nil
    }

    /// The start of the quietest window in the last `cutSearchSamples` of a
    /// full chunk, the final window left out.
    private func quietestCut() -> Int {
        let first = (Self.maximumSamples - Self.cutSearchSamples) / Self.windowSamples
        let quietest = (first ..< levels.count - 1).min { levels[$0] < levels[$1] } ?? first
        return quietest * Self.windowSamples
    }

    /// Returns `pending[..<position]` as a chunk and analyzes the rest again
    /// as the start of the next chunk.
    private mutating func cut(at position: Int) -> MeetingAudioChunk {
        let hasSound = MeetingAudioFormat.hasSound(pending[..<position])
        let chunk = MeetingAudioChunk(track: track, start: pendingStart, end: pendingStart + position, hasSound: hasSound)
        pending.removeFirst(position)
        pendingStart += position
        analyzedWindows = 0
        levels = []
        loudest = 0
        quietRun = 0
        return chunk
    }
}
