import Foundation

protocol LLMSettingsStoreProtocol {
    func load() -> LLMSettings
    func save(_ settings: LLMSettings)
}

final class LLMSettingsStore: LLMSettingsStoreProtocol {
    private let userDefaults: UserDefaults
    private let storageKey = "dev.suniye.llm.settings"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> LLMSettings {
        guard let data = userDefaults.data(forKey: storageKey) else {
            return LLMSettings()
        }
        return (try? decoder.decode(LLMSettings.self, from: data)) ?? LLMSettings()
    }

    func save(_ settings: LLMSettings) {
        guard let data = try? encoder.encode(settings) else {
            return
        }
        userDefaults.set(data, forKey: storageKey)
    }
}
