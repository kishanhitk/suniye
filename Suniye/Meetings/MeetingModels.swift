import Foundation

/// The microphone is "You"; the audio of every other app (the call) is "Them".
enum MeetingTrack: String, Codable, CaseIterable, Sendable {
    case you
    case them
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
    /// The speech model that wrote the text, for example "parakeetV3".
    let engine: String
}

enum MeetingStatus: String, Codable, Sendable {
    case recording
    case paused
    case finishing
    case summarizing
    case done
    case summaryFailed
    case noSpeech
    /// The app ended while it finished the transcript. The user starts the
    /// finish again, because the finish itself may have ended the app.
    case interrupted

    /// States that only a running session can be in. A record found in one of
    /// them at launch belongs to a session that ended without saving.
    var needsRecovery: Bool {
        switch self {
        case .recording, .paused, .finishing:
            return true
        case .summarizing, .done, .summaryFailed, .noSpeech, .interrupted:
            return false
        }
    }
}

enum MeetingStartSource: String, Codable, Sendable {
    case manual
    case offer
    case automatic
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
    var endedAt: Date?
    var callAppName: String?
    var callAppBundleID: String?
    let startSource: MeetingStartSource
    var status: MeetingStatus
    var templateID: String
    var pauses: [MeetingPause]
    /// The call played on speakers at some point, so the microphone may have
    /// heard it and the transcript needs the echo filter.
    var callPlayedOnSpeakers: Bool
    /// The model that wrote the summary on disk.
    var summaryProvider: MeetingSummaryProvider?

    init(
        id: UUID = UUID(),
        title: String,
        titleSource: MeetingTitleSource = .placeholder,
        startedAt: Date,
        endedAt: Date? = nil,
        callAppName: String? = nil,
        callAppBundleID: String? = nil,
        startSource: MeetingStartSource,
        status: MeetingStatus = .recording,
        templateID: String,
        pauses: [MeetingPause] = [],
        callPlayedOnSpeakers: Bool = false,
        summaryProvider: MeetingSummaryProvider? = nil
    ) {
        self.id = id
        self.title = title
        self.titleSource = titleSource
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.callAppName = callAppName
        self.callAppBundleID = callAppBundleID
        self.startSource = startSource
        self.status = status
        self.templateID = templateID
        self.pauses = pauses
        self.callPlayedOnSpeakers = callPlayedOnSpeakers
        self.summaryProvider = summaryProvider
    }

    var duration: TimeInterval? {
        endedAt.map { $0.timeIntervalSince(startedAt) }
    }
}

/// Maps a position in a track's audio file to the meeting's wall clock. The
/// files skip paused time, so every pause that ends at or before an audio
/// position shifts it later by the pause length.
struct MeetingTimeline: Equatable, Sendable {
    let pauses: [MeetingPause]

    func wallSeconds(forSample position: Int) -> Double {
        wallSeconds(forAudioSeconds: Double(position) / Double(MeetingAudioFormat.sampleRate))
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
