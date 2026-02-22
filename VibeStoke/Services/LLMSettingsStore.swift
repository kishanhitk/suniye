import Foundation

protocol LLMSettingsStoreProtocol {
    func load() -> LLMSettings
    func save(_ settings: LLMSettings)
}

final class LLMSettingsStore: LLMSettingsStoreProtocol {
    private let userDefaults: UserDefaults
    private let storageKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(userDefaults: UserDefaults = .standard, storageKey: String = "dev.vibestroke.llm.settings") {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
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
