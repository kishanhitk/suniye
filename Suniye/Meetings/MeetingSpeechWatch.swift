import Foundation

/// Finds the speech in a meeting's audio while it records, with the speech
/// detector and no speech recognition, so that a recording with no speech for
/// a long time stops.
///
/// - The recorder's output arrives in order through `enqueue`.
/// - Each track is checked in windows of `windowSamples`. The detector does
///   not run on a window with no sound.
/// - When the detector cannot start, every window with sound counts as
///   speech: then only silence stops the recording.
actor MeetingSpeechWatch {
    static let windowSamples = 10 * MeetingAudioFormat.sampleRate

    private struct Window {
        let start: Int
        var samples: [Float] = []

        var end: Int {
            start + samples.count
        }
    }

    private let makeDetector: @Sendable () throws -> SpeechDetecting
    private let input: AsyncStream<MeetingRecorderOutput>
    private nonisolated let inputContinuation: AsyncStream<MeetingRecorderOutput>.Continuation
    private var consumer: Task<Void, Never>?
    private lazy var detector: SpeechDetecting? = {
        do {
            return try self.makeDetector()
        } catch {
            AppLogger.shared.log(.error, "meeting speech detector did not start error=\(error.localizedDescription)")
            return nil
        }
    }()

    private var windows: [MeetingTrack: Window] = [:]
    /// For each track, the end of its last checked window.
    private var checkedThrough: [MeetingTrack: Int] = [:]
    /// The end of the last window with speech, on any track.
    private var lastSpeech = 0

    init(makeDetector: @escaping @Sendable () throws -> SpeechDetecting) {
        self.makeDetector = makeDetector
        (input, inputContinuation) = AsyncStream.makeStream(of: MeetingRecorderOutput.self)
    }

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

    /// Checks the audio that already arrived, and then nothing more.
    nonisolated func stop() {
        inputContinuation.finish()
    }

    /// Recorded time after the last speech on any track, counted to where
    /// every one of `tracks` is checked.
    func secondsWithoutSpeech(on tracks: [MeetingTrack]) -> Double {
        let checked = tracks.map { checkedThrough[$0] ?? 0 }.min() ?? 0
        return Double(max(0, checked - lastSpeech)) / Double(MeetingAudioFormat.sampleRate)
    }

    private func process(_ output: MeetingRecorderOutput) {
        let track = output.track
        var window = windows[track] ?? Window(start: output.position)
        var rest = output.samples[...]
        while !rest.isEmpty {
            let taken = rest.prefix(Self.windowSamples - window.samples.count)
            window.samples += taken
            rest = rest.dropFirst(taken.count)
            if window.samples.count == Self.windowSamples {
                check(window, of: track)
                window = Window(start: window.end)
            }
        }
        windows[track] = window
    }

    private func check(_ window: Window, of track: MeetingTrack) {
        if MeetingAudioFormat.hasSound(window.samples[...]), detector?.containsSpeech(window.samples) ?? true {
            lastSpeech = max(lastSpeech, window.end)
        }
        checkedThrough[track] = window.end
    }
}
