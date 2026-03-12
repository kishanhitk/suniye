import Foundation

protocol HistoryStoreProtocol {
    func load() -> [RecentResult]
    func save(_ results: [RecentResult])
}

final class HistoryStore: HistoryStoreProtocol {
    private let userDefaults: UserDefaults
    private let storageKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let legacyDecoder = JSONDecoder()

    init(userDefaults: UserDefaults = .standard, storageKey: String = "dev.suniye.history") {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        encoder.dateEncodingStrategy = .millisecondsSince1970
        decoder.dateDecodingStrategy = .millisecondsSince1970
        legacyDecoder.dateDecodingStrategy = .iso8601
    }

    func load() -> [RecentResult] {
        guard let data = userDefaults.data(forKey: storageKey) else {
            return []
        }
        if let results = try? decoder.decode([RecentResult].self, from: data) {
            return results
        }
        return (try? legacyDecoder.decode([RecentResult].self, from: data)) ?? []
    }

    func save(_ results: [RecentResult]) {
        guard let data = try? encoder.encode(results) else {
            return
        }
        userDefaults.set(data, forKey: storageKey)
    }
}
