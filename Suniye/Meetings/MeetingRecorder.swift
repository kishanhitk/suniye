import Foundation

/// What the recorder hands on, in order, on its queue: 16 kHz samples of a
/// track that are in its file, and the position of the first one there.
struct MeetingRecorderOutput: Equatable, Sendable {
    let track: MeetingTrack
    let samples: [Float]
    let position: Int
}

enum MeetingRecorderEvent: Equatable, Sendable {
    case levels(you: Float, them: Float)
    /// The call track had no sound for `MeetingRecorder.callSilenceLimit`.
    /// `heardBefore` tells a call track that stopped from one that never
    /// delivered sound, which points at the permission. `since` is the
    /// recorded time of the last sound, or of the call track's start.
    case callAudioSilent(heardBefore: Bool, since: TimeInterval)
    case callAudioReturned
    case inputChanged(deviceName: String)
    /// A track's source started: at the start, at a resume, or after
    /// Restart Call Audio.
    case trackStarted(MeetingTrack)
    case trackFailed(MeetingTrack, String)
    /// `outOfSpace` tells a full disk from any other write error.
    case storageFailed(String, outOfSpace: Bool)
}

/// Writes the two tracks of one meeting to disk, in step with the system
/// uptime clock.
///
/// - Paused time is not written; the meeting record keeps the pauses, and
///   `MeetingTimeline` maps audio positions back to the wall clock.
/// - A track that falls behind the clock by more than `gapThreshold` (a
///   device change, a slow start) gets silence, so a position in either file
///   means about the same moment. A track that runs ahead is not cut.
/// - While a dictation captures audio, the microphone track gets silence:
///   the dictated words are not meeting talk.
final class MeetingRecorder: @unchecked Sendable {
    static let callSilenceLimit: TimeInterval = 120
    /// Smaller gaps are timing jitter between blocks, not lost audio.
    static let gapThreshold: TimeInterval = 0.25
    static let levelInterval: TimeInterval = 1.0 / 15

    var onOutput: ((MeetingRecorderOutput) -> Void)?
    var onEvent: ((MeetingRecorderEvent) -> Void)?

    private let queue = DispatchQueue(label: "dev.suniye.meeting.recorder", qos: .userInitiated)
    private let sources: [MeetingTrack: MeetingAudioSource]
    private let audioURL: (MeetingTrack) -> URL
    private let uptime: () -> TimeInterval
    private let silenceCheckInterval: DispatchTimeInterval
    private var writers: [MeetingTrack: MeetingAudioFileWriter] = [:]
    private var samplesWritten: [MeetingTrack: Int] = [:]
    private var lastLevel: [MeetingTrack: Float] = [:]
    private var lastLevelEmission: TimeInterval = 0
    private var startedAt: TimeInterval = 0
    private var pausedTotal: TimeInterval = 0
    private var pausedSince: TimeInterval?
    private var running = false
    private var microphoneMuted = false
    private var lastCallSound: TimeInterval = 0
    private var callTrackHeardSound = false
    private var reportedCallSilence = false
    /// The call source started and did not fail since: only then can its
    /// silence mean that the call has no sound.
    private var callSourceRunning = false
    private var silenceTimer: DispatchSourceTimer?

    /// `sources` without `.them` records the microphone only.
    init(
        sources: [MeetingTrack: MeetingAudioSource],
        audioURL: @escaping (MeetingTrack) -> URL,
        uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        silenceCheckInterval: DispatchTimeInterval = .seconds(1)
    ) {
        self.sources = sources
        self.audioURL = audioURL
        self.uptime = uptime
        self.silenceCheckInterval = silenceCheckInterval
    }

    var tracks: [MeetingTrack] {
        MeetingTrack.allCases.filter { sources[$0] != nil }
    }

    /// A track that cannot start is reported as `trackFailed` and the other
    /// track records. Throws when no track starts.
    func start() throws {
        try queue.sync {
            do {
                for track in tracks {
                    writers[track] = try MeetingAudioFileWriter(url: audioURL(track))
                    samplesWritten[track] = 0
                }
            } catch {
                closeWriters()
                throw error
            }
            startedAt = uptime()
            running = true
        }
        do {
            try startSources()
        } catch {
            queue.sync {
                running = false
                closeWriters()
            }
            throw error
        }
        queue.sync { startSilenceTimer() }
    }

    func stop() {
        stopSources()
        queue.sync {
            silenceTimer?.cancel()
            silenceTimer = nil
            running = false
            closeWriters()
        }
    }

    /// Stops both sources so the microphone indicator goes off while paused.
    /// The audio that a source hands over while it stops is still written.
    func pause() {
        let isRecording: Bool = queue.sync { running && pausedSince == nil }
        guard isRecording else { return }
        stopSources()
        queue.sync { pausedSince = uptime() }
    }

    /// Stays paused and throws when no track starts again.
    func resume() throws {
        let shouldStart: Bool = queue.sync {
            guard running, let since = pausedSince else { return false }
            pausedTotal += uptime() - since
            pausedSince = nil
            return true
        }
        guard shouldStart else { return }
        do {
            try startSources()
        } catch {
            queue.sync { pausedSince = uptime() }
            throw error
        }
    }

    /// Builds the call track again from nothing: a broken tap can keep
    /// delivering silence until it is destroyed and created again. Reports
    /// `trackStarted` or `trackFailed`.
    func restartCallAudio() {
        guard let source = sources[.them] else { return }
        let isRecording: Bool = queue.sync { running && pausedSince == nil }
        guard isRecording else { return }
        source.stop()
        do {
            try source.start()
        } catch {
            AppLogger.shared.log(.error, "meeting recorder could not restart the call track error=\(error.localizedDescription)")
            queue.async { self.sourceFailed(.them, error.localizedDescription) }
            return
        }
        queue.sync { sourceStarted(.them) }
        AppLogger.shared.log(.info, "meeting recorder restarted the call track")
    }

    func setMicrophoneMuted(_ muted: Bool) {
        queue.async { self.microphoneMuted = muted }
    }

    /// Reports the call track's silence again, for a recording that starts
    /// to follow a call after it reported the silence once.
    func rearmCallSilence() {
        queue.async { self.reportedCallSilence = false }
    }

    // MARK: - Sources

    private func startSources() throws {
        var failures: [(track: MeetingTrack, error: Error)] = []
        var startedAny = false
        for track in tracks {
            guard let source = sources[track] else { continue }
            source.onSamples = { [weak self] samples in
                guard let self else { return }
                let arrival = self.uptime()
                self.queue.async { self.receive(samples, track: track, arrival: arrival) }
            }
            source.onEvent = { [weak self] event in
                self?.queue.async { self?.handle(event, track: track) }
            }
            do {
                try source.start()
                startedAny = true
                queue.async { self.sourceStarted(track) }
            } catch {
                AppLogger.shared.log(.error, "meeting recorder could not start track=\(track.rawValue) error=\(error.localizedDescription)")
                failures.append((track, error))
            }
        }
        if !startedAny, let first = failures.first {
            throw first.error
        }
        for failure in failures {
            queue.async { self.sourceFailed(failure.track, failure.error.localizedDescription) }
        }
    }

    private func stopSources() {
        for track in tracks {
            sources[track]?.stop()
        }
    }

    // MARK: - On `queue`

    /// `arrival` is when the source handed the block over, so time spent
    /// waiting on this queue does not count as a gap.
    private func receive(_ block: [Float], track: MeetingTrack, arrival: TimeInterval) {
        guard running, pausedSince == nil, let writer = writers[track] else { return }
        let samples = track == .you && microphoneMuted ? [Float](repeating: 0, count: block.count) : block
        let written = samplesWritten[track] ?? 0
        let expected = Int((arrival - startedAt - pausedTotal) * Double(MeetingAudioFormat.sampleRate))
        let missing = expected - written - samples.count
        var position = written
        do {
            if Double(missing) > Self.gapThreshold * Double(MeetingAudioFormat.sampleRate) {
                let silence = [Float](repeating: 0, count: missing)
                try writer.append(silence)
                onOutput?(MeetingRecorderOutput(track: track, samples: silence, position: position))
                position += missing
            }
            try writer.append(samples)
        } catch {
            AppLogger.shared.log(.error, "meeting recorder could not write track=\(track.rawValue) error=\(error.localizedDescription)")
            onEvent?(.storageFailed(error.localizedDescription, outOfSpace: MeetingAudioFileWriter.isOutOfSpace(error)))
            running = false
            return
        }
        onOutput?(MeetingRecorderOutput(track: track, samples: samples, position: position))
        samplesWritten[track] = position + samples.count

        let level = MeetingAudioFormat.rms(samples)
        if track == .them, level >= MeetingAudioFormat.silenceLevel {
            lastCallSound = arrival
            callTrackHeardSound = true
            if reportedCallSilence {
                reportedCallSilence = false
                onEvent?(.callAudioReturned)
            }
        }
        lastLevel[track] = min(max(level * AudioCaptureService.levelMeterGain, 0), 1)
        if arrival - lastLevelEmission >= Self.levelInterval {
            lastLevelEmission = arrival
            onEvent?(.levels(you: lastLevel[.you] ?? 0, them: lastLevel[.them] ?? 0))
        }
    }

    private func handle(_ event: MeetingAudioSourceEvent, track: MeetingTrack) {
        switch event {
        case let .inputChanged(name):
            onEvent?(.inputChanged(deviceName: name))
        case let .failed(message):
            sourceFailed(track, message)
        }
    }

    private func sourceStarted(_ track: MeetingTrack) {
        if track == .them {
            callSourceRunning = true
            lastCallSound = uptime()
            reportedCallSilence = false
        }
        onEvent?(.trackStarted(track))
    }

    private func sourceFailed(_ track: MeetingTrack, _ message: String) {
        if track == .them {
            callSourceRunning = false
        }
        onEvent?(.trackFailed(track, message))
    }

    private func startSilenceTimer() {
        guard sources[.them] != nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + silenceCheckInterval, repeating: silenceCheckInterval)
        timer.setEventHandler { [weak self] in self?.checkCallSilence() }
        silenceTimer = timer
        timer.resume()
    }

    private func checkCallSilence() {
        guard running, pausedSince == nil, callSourceRunning, !reportedCallSilence else { return }
        if uptime() - lastCallSound >= Self.callSilenceLimit {
            reportedCallSilence = true
            onEvent?(.callAudioSilent(heardBefore: callTrackHeardSound, since: max(0, lastCallSound - startedAt - pausedTotal)))
        }
    }

    private func closeWriters() {
        for (track, writer) in writers {
            do {
                try writer.close()
            } catch {
                AppLogger.shared.log(.error, "meeting recorder could not close track=\(track.rawValue) error=\(error.localizedDescription)")
            }
        }
        writers = [:]
    }
}
