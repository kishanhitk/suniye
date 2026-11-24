import Foundation

/// Locally persisted analytics identity + opt-out state. The install id is
/// generated once and then frozen — changing it
/// would silently reset all retention history.
public struct AnalyticsSettings: Codable, Equatable, Sendable {
    public var installID: String
    public var enabled: Bool
    public var firstLaunchAt: Date

    public init(installID: String, enabled: Bool, firstLaunchAt: Date) {
        self.installID = installID
        self.enabled = enabled
        self.firstLaunchAt = firstLaunchAt
    }
}

/// Remote-controlled directive returned by the ingest endpoint (a kill switch /
/// sampling knob). Cached locally so old builds can be quieted without an app
/// update — you cannot add this channel retroactively, so it exists from v1.
public struct KillSwitchDirective: Codable, Equatable, Sendable {
    public var disabled: Bool
    public var sampleRate: Double?   // 0.0...1.0; nil = send everything

    public init(disabled: Bool = false, sampleRate: Double? = nil) {
        self.disabled = disabled
        self.sampleRate = sampleRate
    }

    enum CodingKeys: String, CodingKey {
        case disabled
        case sampleRate = "sample_rate"
    }

    // The server may send `{ "sample_rate": ... }` with no `disabled`; default it
    // to false rather than failing decode and dropping the whole directive.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        disabled = try container.decodeIfPresent(Bool.self, forKey: .disabled) ?? false
        sampleRate = try container.decodeIfPresent(Double.self, forKey: .sampleRate)
    }
}

public final class AnalyticsSettingsStore: @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let settingsKey = "dev.suniye.analytics.settings"
    private let directiveKey = "dev.suniye.analytics.settings.killswitch"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    /// Returns existing settings, or creates + persists fresh ones (generating
    /// the frozen install id) on first call.
    public func loadOrCreate() -> AnalyticsSettings {
        if let existing = peek() { return existing }
        let fresh = AnalyticsSettings(installID: UUID().uuidString, enabled: true, firstLaunchAt: Date())
        save(fresh)
        return fresh
    }

    /// Reads settings without creating them. `nil` if never initialized.
    public func peek() -> AnalyticsSettings? {
        guard let data = userDefaults.data(forKey: settingsKey) else { return nil }
        return try? decoder.decode(AnalyticsSettings.self, from: data)
    }

    public func save(_ settings: AnalyticsSettings) {
        guard let data = try? encoder.encode(settings) else { return }
        userDefaults.set(data, forKey: settingsKey)
    }

    public func setEnabled(_ enabled: Bool) {
        var settings = loadOrCreate()
        settings.enabled = enabled
        save(settings)
    }

    public func loadDirective() -> KillSwitchDirective? {
        guard let data = userDefaults.data(forKey: directiveKey) else { return nil }
        return try? decoder.decode(KillSwitchDirective.self, from: data)
    }

    public func saveDirective(_ directive: KillSwitchDirective?) {
        guard let directive, let data = try? encoder.encode(directive) else {
            userDefaults.removeObject(forKey: directiveKey)
            return
        }
        userDefaults.set(data, forKey: directiveKey)
    }
}
