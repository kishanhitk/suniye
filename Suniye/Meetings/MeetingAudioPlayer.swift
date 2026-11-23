import AVFoundation

/// Plays the audio files of one meeting together, from one position. Output
/// only: it opens no input.
@MainActor
protocol MeetingAudioPlayer: AnyObject {
    /// Seconds of audio in the longest file.
    var duration: TimeInterval { get }
    /// Seconds from the start of the files.
    var currentTime: TimeInterval { get }
    var isPlaying: Bool { get }
    /// Called when the audio plays to its end.
    var onEnd: () -> Void { get set }
    /// Starts every file at `time`, all at one moment. False when they do
    /// not start.
    func play(from time: TimeInterval) -> Bool
    func pause()
}

/// One AVAudioPlayer for each track file. Both files hold the same moment at
/// the same position, and the players start at one time of the output
/// device's clock, so they play together.
@MainActor
final class MeetingTrackPlayers: NSObject, MeetingAudioPlayer, AVAudioPlayerDelegate {
    /// Time for each player to be ready for the common start.
    private static let startDelay: TimeInterval = 0.05

    var onEnd: () -> Void = {}
    /// The longest first: it plays to the end, so it gives the position.
    private let players: [AVAudioPlayer]

    init(urls: [URL]) throws {
        let players = try urls.map { try AVAudioPlayer(contentsOf: $0) }.sorted { $0.duration > $1.duration }
        guard let clock = players.first else {
            throw CocoaError(.fileNoSuchFile)
        }
        self.players = players
        super.init()
        clock.delegate = self
        for player in players {
            player.prepareToPlay()
        }
    }

    var duration: TimeInterval {
        players[0].duration
    }

    var currentTime: TimeInterval {
        players[0].currentTime
    }

    var isPlaying: Bool {
        players[0].isPlaying
    }

    func play(from time: TimeInterval) -> Bool {
        pause()
        let start = players[0].deviceCurrentTime + Self.startDelay
        for player in players where time < player.duration {
            player.currentTime = time
            guard player.play(atTime: start) else {
                pause()
                return false
            }
        }
        return true
    }

    func pause() {
        for player in players {
            player.pause()
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.onEnd()
        }
    }
}
