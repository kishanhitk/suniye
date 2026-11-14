import Foundation

/// The microphone is "You"; the audio of every other app (the call) is "Them".
enum MeetingTrack: String, Codable, CaseIterable, Comparable, Sendable {
    case you
    case them

    /// The call track sorts first, so that lines and chunks with one start
    /// come in the same order everywhere.
    static func < (lhs: MeetingTrack, rhs: MeetingTrack) -> Bool {
        lhs == .them && rhs == .you
    }

    var speakerLabel: String {
        switch self {
        case .you:
            return "You"
        case .them:
            return "Them"
        }
    }
}

struct MeetingSegment: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let track: MeetingTrack
    /// Sample positions in the track's audio file. Both files hold the same
    /// moment at the same position; `MeetingTimeline` maps a position to the
    /// wall clock.
    let audioStart: Int
    let audioEnd: Int
    let text: String

    func withText(_ text: String) -> MeetingSegment {
        MeetingSegment(id: id, track: track, audioStart: audioStart, audioEnd: audioEnd, text: text)
    }
}

enum MeetingStatus: String, Codable, Sendable {
    case recording
    case paused
    case finishing
    case summarizing
    case done
    case summaryFailed
    case noSpeech
    /// The transcript did not finish: the app ended while it finished, or
    /// part of the audio got no text. The user starts the finish again,
    /// because the finish itself may have ended the app.
    case interrupted
    /// The app quit or crashed during the recording. The audio is saved, and
    /// the transcript waits for the user: a launch does not load a speech
    /// model and run for minutes with no click.
    case notTranscribed

    /// Titles of the states without a summary, for the meeting page and the
    /// meetings list.
    static let summaryFailedTitle = "Couldn’t write the summary"
    static let noSpeechTitle = "Too little speech to summarize"
    static let interruptedTitle = "A transcript did not finish"
    static let notTranscribedTitle = "A meeting stopped when Suniye quit"

    /// A summary can be written again: the transcript is final and no
    /// summary runs.
    var canRegenerate: Bool {
        switch self {
        case .done, .summaryFailed, .noSpeech:
            return true
        case .recording, .paused, .finishing, .summarizing, .interrupted, .notTranscribed:
            return false
        }
    }

    /// A transcript pass ran to its end.
    var hasFinalTranscript: Bool {
        switch self {
        case .summarizing, .done, .summaryFailed, .noSpeech:
            return true
        case .recording, .paused, .finishing, .interrupted, .notTranscribed:
            return false
        }
    }

    /// States that only a running session can be in. A record found in one of
    /// them at launch belongs to a session that ended without saving.
    var needsRecovery: Bool {
        switch self {
        case .recording, .paused, .finishing:
            return true
        case .summarizing, .done, .summaryFailed, .noSpeech, .interrupted, .notTranscribed:
            return false
        }
    }
}

enum MeetingTitleSource: String, Codable, Sendable {
    case placeholder
    case generated
    case user
}

/// A pause on the wall clock, in seconds from the meeting start. The audio
/// files hold no samples for it.
struct MeetingPause: Codable, Equatable, Sendable {
    let start: Double
    var end: Double?
}

struct MeetingRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var titleSource: MeetingTitleSource
    let startedAt: Date
    /// The tracks that recorded. A meeting with a call track shows who
    /// speaks: page, export and summary.
    let tracks: [MeetingTrack]
    var endedAt: Date?
    var callAppName: String?
    var callAppBundleID: String?
    var status: MeetingStatus
    var templateID: String
    var pauses: [MeetingPause]
    /// The call played on speakers at some point, so the microphone may have
    /// heard it and the transcript needs the echo filter.
    var callPlayedOnSpeakers: Bool
    /// The audio position where the call that the meeting followed ended: the
    /// transcript keeps no line that starts at or after it.
    var transcriptEnd: Int?
    /// Why the last finish of the transcript failed; nil when the app closed
    /// while it finished.
    var transcriptFailure: String?
    /// Why the last summary failed, for the meeting page.
    var summaryFailure: String?
    /// When the user first changed a transcript line; nil until then, and
    /// again after Transcribe Again.
    var transcriptEditedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        titleSource: MeetingTitleSource = .placeholder,
        startedAt: Date,
        tracks: [MeetingTrack],
        endedAt: Date? = nil,
        callAppName: String? = nil,
        callAppBundleID: String? = nil,
        status: MeetingStatus = .recording,
        templateID: String,
        pauses: [MeetingPause] = [],
        callPlayedOnSpeakers: Bool = false
    ) {
        self.id = id
        self.title = title
        self.titleSource = titleSource
        self.startedAt = startedAt
        self.tracks = tracks
        self.endedAt = endedAt
        self.callAppName = callAppName
        self.callAppBundleID = callAppBundleID
        self.status = status
        self.templateID = templateID
        self.pauses = pauses
        self.callPlayedOnSpeakers = callPlayedOnSpeakers
    }

    var duration: TimeInterval? {
        endedAt.map { $0.timeIntervalSince(startedAt) }
    }

    var hasCallTrack: Bool {
        tracks.contains(.them)
    }

    /// Ends the meeting `seconds` after its start on the wall clock. A pause
    /// that runs past that moment ends there, and a later pause goes.
    mutating func end(atWallSeconds seconds: Double) {
        pauses = pauses.compactMap { pause in
            guard pause.start < seconds else { return nil }
            return MeetingPause(start: pause.start, end: min(pause.end ?? seconds, seconds))
        }
        endedAt = startedAt.addingTimeInterval(seconds)
    }
}

/// Maps a position in a track's audio file to the meeting's wall clock. The
/// files skip paused time, so every closed pause that starts at or before
/// the moment shifts it later by the pause length.
struct MeetingTimeline: Equatable, Sendable {
    let pauses: [MeetingPause]

    func wallSeconds(forSample position: Int) -> Double {
        wallSeconds(forAudioSeconds: Double(position) / Double(MeetingAudioFormat.sampleRate))
    }

    func audioPosition(forWallSeconds wall: Double) -> Int {
        Int(audioSeconds(forWallSeconds: wall) * Double(MeetingAudioFormat.sampleRate))
    }

    /// The audio position, in seconds, of a moment on the wall clock: the
    /// paused time before that moment does not count.
    func audioSeconds(forWallSeconds wall: Double) -> Double {
        let paused = pauses.reduce(0) { total, pause in
            total + max(0, min(pause.end ?? wall, wall) - pause.start)
        }
        return max(0, wall - paused)
    }

    func wallSeconds(forAudioSeconds audio: Double) -> Double {
        var wall = audio
        for pause in pauses.sorted(by: { $0.start < $1.start }) {
            guard let end = pause.end, pause.start <= wall else { break }
            wall += end - pause.start
        }
        return wall
    }
}
