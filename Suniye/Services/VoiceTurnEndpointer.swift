import Foundation

/// Decides when a spoken turn has ended, from a stream of per-frame speech
/// judgments. Pure logic: the caller supplies "is this frame speech" (from VAD
/// or the level meter) and a timestamp; this type owns the timing rules from
/// the UX plan (no button, no fixed pause ritual).
struct VoiceTurnEndpointer: Equatable, Sendable {
    struct Configuration: Equatable, Sendable {
        /// Speech shorter than this is treated as noise, not a turn.
        var minimumSpeechSeconds: TimeInterval = 0.3
        /// Silence this long after speech ends the turn.
        var trailingSilenceSeconds: TimeInterval = 0.9
        /// A turn cannot exceed this length; it ends here regardless.
        var maximumTurnSeconds: TimeInterval = 30
        /// With no meaningful speech after wake-up, return to Ready.
        var noSpeechTimeoutSeconds: TimeInterval = 5
    }

    enum Verdict: Equatable, Sendable {
        /// No meaningful speech yet.
        case waiting
        /// Speech is in progress.
        case speaking
        /// The turn ended after trailing silence.
        case turnEnded(speechDuration: TimeInterval)
        /// Nothing meaningful was said in time (UX plan: false wake-up).
        case noSpeechTimeout
        /// The maximum turn length was hit while still speaking.
        case maxTurnReached(speechDuration: TimeInterval)
    }

    let configuration: Configuration
    private var windowStart: TimeInterval?
    private var firstSpeech: TimeInterval?
    private var lastSpeech: TimeInterval?

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Starts a capture window (call on wake hit or follow-up window entry).
    mutating func begin(at time: TimeInterval) {
        windowStart = time
        firstSpeech = nil
        lastSpeech = nil
    }

    mutating func process(isSpeech: Bool, at time: TimeInterval) -> Verdict {
        guard let windowStart else {
            return .waiting
        }

        if isSpeech {
            if firstSpeech == nil {
                firstSpeech = time
            }
            lastSpeech = time
            if let firstSpeech, time - firstSpeech >= configuration.maximumTurnSeconds {
                return .maxTurnReached(speechDuration: time - firstSpeech)
            }
            return .speaking
        }

        guard let firstSpeech, let lastSpeech else {
            return time - windowStart >= configuration.noSpeechTimeoutSeconds
                ? .noSpeechTimeout
                : .waiting
        }

        guard time - lastSpeech >= configuration.trailingSilenceSeconds else {
            return .speaking
        }

        let speechDuration = lastSpeech - firstSpeech
        if speechDuration < configuration.minimumSpeechSeconds {
            // Noise, not a turn: forget it and keep waiting for real speech.
            self.firstSpeech = nil
            self.lastSpeech = nil
            return time - windowStart >= configuration.noSpeechTimeoutSeconds
                ? .noSpeechTimeout
                : .waiting
        }
        return .turnEnded(speechDuration: speechDuration)
    }
}
