import Foundation

protocol GeneralSettingsStoreProtocol {
    func load() -> GeneralSettings
    func save(_ settings: GeneralSettings)
}

final class GeneralSettingsStore: GeneralSettingsStoreProtocol {
    private let userDefaults: UserDefaults
    private let storageKey = "dev.suniye.general.settings"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> GeneralSettings {
        guard let data = userDefaults.data(forKey: storageKey) else {
            return GeneralSettings()
        }
        return (try? decoder.decode(GeneralSettings.self, from: data)) ?? GeneralSettings()
    }

    func save(_ settings: GeneralSettings) {
        guard let data = try? encoder.encode(settings) else {
            return
        }
        userDefaults.set(data, forKey: storageKey)
    }
}
