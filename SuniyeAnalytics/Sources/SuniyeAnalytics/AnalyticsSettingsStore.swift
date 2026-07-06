import Foundation

/// Locally persisted analytics identity + opt-out state. Mirrors the app's
/// `GeneralSettingsStore` shape (injectable `UserDefaults` + key, Codable,
/// silent-fail). The install id is generated once and then frozen — changing it
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
    private let settingsKey: String
    private let directiveKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "dev.suniye.analytics.settings"
    ) {
        self.userDefaults = userDefaults
        self.settingsKey = storageKey
        self.directiveKey = storageKey + ".killswitch"
    }

    /// Returns existing settings, or creates + persists fresh ones (generating
    /// the frozen install id) on first call.
    public func loadOrCreate(
        makeInstallID: () -> String = { UUID().uuidString },
        now: () -> Date = { Date() }
    ) -> AnalyticsSettings {
        if let existing = peek() { return existing }
        let fresh = AnalyticsSettings(installID: makeInstallID(), enabled: true, firstLaunchAt: now())
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

    public func setEnabled(_ enabled: Bool, makeInstallID: () -> String = { UUID().uuidString }) {
        var settings = loadOrCreate(makeInstallID: makeInstallID)
        settings.enabled = enabled
        save(settings)
    }

    /// Rotates the install id (clears + regenerates). Used by "reset analytics".
    @discardableResult
    public func resetIdentity(makeInstallID: () -> String = { UUID().uuidString }) -> AnalyticsSettings {
        var settings = loadOrCreate(makeInstallID: makeInstallID)
        settings.installID = makeInstallID()
        save(settings)
        return settings
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
