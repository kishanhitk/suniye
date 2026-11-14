import Foundation

/// What Suniye does when a call app starts a call.
enum MeetingCallStartAction: String, Codable, CaseIterable, Sendable {
    case ask
    case recordAutomatically
    case doNothing
}

struct MeetingSettings: Codable, Equatable, Sendable {
    var callStartAction = MeetingCallStartAction.ask
    /// Bundle IDs of the call apps that get no offer card and no automatic
    /// recording.
    var neverAskBundleIDs: [String] = []
    /// The template that the user picked last.
    var templateID = MeetingTemplate.general.id

    init() {}

    /// A missing key keeps its default, so settings that one build saved
    /// still load after a later build adds a key.
    init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        callStartAction = try container.decodeIfPresent(MeetingCallStartAction.self, forKey: .callStartAction) ?? callStartAction
        neverAskBundleIDs = try container.decodeIfPresent([String].self, forKey: .neverAskBundleIDs) ?? neverAskBundleIDs
        templateID = try container.decodeIfPresent(String.self, forKey: .templateID) ?? templateID
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
