import Foundation
import Observation

/// The playback of one meeting's kept audio, from its page; one meeting at a
/// time. The coordinator closes it when a recording starts or the meeting
/// goes, and pauses it when a dictation starts. The page pauses it when
/// another tab opens and closes it when the page goes.
@MainActor
@Observable
final class MeetingPlayback {
    /// The meeting whose audio is open.
    private(set) var meetingID: UUID?
    private(set) var isPlaying = false
    /// Seconds from the start of the audio files, which hold no paused time.
    private(set) var position: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    /// The audio of the open meeting could not be read or played.
    private(set) var failed = false
    /// Goes up at each start and each move of the position, so the
    /// transcript follows the line that plays again after the user scrolled.
    private(set) var moves = 0

    @ObservationIgnored private let store: MeetingStore
    @ObservationIgnored private let makePlayer: @MainActor ([URL]) throws -> MeetingAudioPlayer
    @ObservationIgnored private let tickInterval: Duration
    @ObservationIgnored private var player: MeetingAudioPlayer?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    init(
        store: MeetingStore,
        makePlayer: @escaping @MainActor ([URL]) throws -> MeetingAudioPlayer,
        tickInterval: Duration = .milliseconds(100)
    ) {
        self.store = store
        self.makePlayer = makePlayer
        self.tickInterval = tickInterval
    }

    /// Opens the audio of `id`, and closes the audio of another meeting.
    func open(_ id: UUID) {
        guard meetingID != id else { return }
        close()
        meetingID = id
        let urls = store.audioTracks(of: id).map { store.audioURL($0, for: id) }
        do {
            let player = try makePlayer(urls)
            player.onEnd = { [weak self] in self?.ended() }
            self.player = player
            duration = player.duration
        } catch {
            AppLogger.shared.log(.error, "meeting audio not opened id=\(id.uuidString) error=\(error.localizedDescription)")
            failed = true
        }
    }

    /// Plays from `time`, or from where it stopped; after the end, from the
    /// start.
    func play(from time: TimeInterval? = nil) {
        guard let player else { return }
        let start = time.map { min(max(0, $0), duration) } ?? (position < duration ? position : 0)
        guard start < duration else {
            // A move to the end stops the audio there.
            player.pause()
            position = duration
            stopped()
            return
        }
        guard player.play(from: start) else {
            AppLogger.shared.log(.error, "meeting audio did not play id=\(meetingID?.uuidString ?? "-")")
            failed = true
            return
        }
        position = start
        isPlaying = true
        moves += 1
        ticker?.cancel()
        ticker = Task { [weak self, tickInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: tickInterval)
                guard let self, !Task.isCancelled else { return }
                self.tick()
            }
        }
    }

    func pause() {
        guard isPlaying, let player else { return }
        player.pause()
        position = player.currentTime
        stopped()
    }

    /// Moves the position; the audio plays on if it played.
    func seek(to time: TimeInterval) {
        guard player != nil else { return }
        if isPlaying {
            play(from: time)
        } else {
            position = min(max(0, time), duration)
            moves += 1
        }
    }

    /// Closes the audio of `id`; with no id, the audio of any meeting.
    func close(_ id: UUID? = nil) {
        guard meetingID != nil, id == nil || id == meetingID else { return }
        player?.pause()
        // An end that the player reported just before is for this audio, not
        // for the next meeting.
        player?.onEnd = {}
        player = nil
        stopped()
        meetingID = nil
        position = 0
        duration = 0
        failed = false
        moves = 0
    }

    /// The lines that play at `sample`: each line whose audio holds it, so
    /// two when two people talk at once. Between lines, the line that
    /// started last.
    static func playingLines(at sample: Int, in segments: [MeetingSegment]) -> Set<UUID> {
        let holding = segments.filter { $0.audioStart <= sample && sample < $0.audioEnd }
        if !holding.isEmpty {
            return Set(holding.map(\.id))
        }
        let last = segments.filter { $0.audioStart <= sample }.max { $0.audioStart < $1.audioStart }
        return last.map { [$0.id] } ?? []
    }

    private func tick() {
        guard isPlaying, let player else { return }
        if player.isPlaying {
            position = player.currentTime
        } else {
            // The output stopped before the end, for example when its device
            // went away.
            stopped()
        }
    }

    /// The player resets its position at the end, so the end is kept here.
    /// An end that comes after a new start is old: the player plays.
    private func ended() {
        guard let player, !player.isPlaying else { return }
        position = duration
        stopped()
    }

    private func stopped() {
        isPlaying = false
        ticker?.cancel()
        ticker = nil
    }
}
