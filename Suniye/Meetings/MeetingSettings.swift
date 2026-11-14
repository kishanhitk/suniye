import Foundation

/// What Suniye does when a call app starts a call.
enum MeetingCallStartAction: String, Codable, CaseIterable, Sendable {
    case ask
    case recordAutomatically
    case doNothing
}

/// How long a meeting's audio stays on the Mac after its transcript is
/// ready.
enum MeetingAudioRetention: String, Codable, CaseIterable, Sendable {
    case untilTranscript
    case sevenDays
    case thirtyDays

    /// Days after the end of the meeting; nil deletes the audio when the
    /// transcript is ready.
    var days: Int? {
        switch self {
        case .untilTranscript:
            return nil
        case .sevenDays:
            return 7
        case .thirtyDays:
            return 30
        }
    }
}

struct MeetingSettings: Codable, Equatable, Sendable {
    var callStartAction = MeetingCallStartAction.ask
    /// Bundle IDs of the call apps that get no offer card and no automatic
    /// recording.
    var neverAskBundleIDs: [String] = []
    /// The template that the user picked last.
    var templateID = MeetingTemplate.general.id
    /// The speech model that writes the transcripts; nil is the dictation
    /// model.
    var transcriptModel: ASRModelID?
    var audioRetention = MeetingAudioRetention.untilTranscript

    init() {}

    /// A missing key keeps its default, so settings that one build saved
    /// still load after a later build adds a key. A transcript model that
    /// this build does not know is the dictation model, and an unknown audio
    /// choice is the default.
    init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        callStartAction = try container.decodeIfPresent(MeetingCallStartAction.self, forKey: .callStartAction) ?? callStartAction
        neverAskBundleIDs = try container.decodeIfPresent([String].self, forKey: .neverAskBundleIDs) ?? neverAskBundleIDs
        templateID = try container.decodeIfPresent(String.self, forKey: .templateID) ?? templateID
        transcriptModel = try container.decodeIfPresent(String.self, forKey: .transcriptModel).flatMap(ASRModelID.init(rawValue:))
        audioRetention = try container.decodeIfPresent(String.self, forKey: .audioRetention)
            .flatMap(MeetingAudioRetention.init(rawValue:)) ?? audioRetention
    }
}

/// The transcript model cannot write a transcript now.
enum MeetingTranscriptModelError: LocalizedError, Equatable {
    case notDownloaded(String)

    var errorDescription: String? {
        switch self {
        case let .notDownloaded(name):
            return "\(name) is not downloaded. Download it in Settings, or choose another transcript model."
        }
    }
}

final class MeetingSettingsStore {
    private let userDefaults: UserDefaults
    private let key: String

    init(userDefaults: UserDefaults = .standard, key: String = "dev.suniye.meeting.settings") {
        self.userDefaults = userDefaults
        self.key = key
    }

    func load() -> MeetingSettings {
        guard let data = userDefaults.data(forKey: key) else { return MeetingSettings() }
        do {
            return try JSONDecoder().decode(MeetingSettings.self, from: data)
        } catch {
            AppLogger.shared.log(.error, "meeting settings unreadable error=\(error.localizedDescription)")
            return MeetingSettings()
        }
    }

    func save(_ settings: MeetingSettings) {
        do {
            userDefaults.set(try JSONEncoder().encode(settings), forKey: key)
        } catch {
            AppLogger.shared.log(.error, "meeting settings not saved error=\(error.localizedDescription)")
        }
    }
}
