import Foundation

protocol GeneralSettingsStoreProtocol {
    func load() -> GeneralSettings
    func save(_ settings: GeneralSettings)
}

final class GeneralSettingsStore: GeneralSettingsStoreProtocol {
    private let userDefaults: UserDefaults
    private let storageKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(userDefaults: UserDefaults = .standard, storageKey: String = "dev.suniye.general.settings") {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
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
