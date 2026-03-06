import Foundation

protocol AppPreferencesStoreProtocol {
    func load() -> AppPreferences
    func save(_ preferences: AppPreferences)
}

final class AppPreferencesStore: AppPreferencesStoreProtocol {
    private let fileManager: FileManager
    private let preferencesFileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        fileManager: FileManager = .default,
        baseDirectoryURL: URL? = nil,
        filename: String = "preferences.json"
    ) {
        self.fileManager = fileManager
        let baseURL = baseDirectoryURL ?? AppPreferencesStore.defaultConfigDirectoryURL(fileManager: fileManager)
        self.preferencesFileURL = baseURL.appendingPathComponent(filename, isDirectory: false)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() -> AppPreferences {
        guard fileManager.fileExists(atPath: preferencesFileURL.path) else {
            return AppPreferences()
        }

        do {
            let data = try Data(contentsOf: preferencesFileURL)
            return try decoder.decode(AppPreferences.self, from: data)
        } catch {
            AppLogger.shared.log(.warning, "preferences load failed: \(error.localizedDescription)")
            return AppPreferences()
        }
    }

    func save(_ preferences: AppPreferences) {
        do {
            try ensureDirectoryExists()
            let data = try encoder.encode(preferences)
            try data.write(to: preferencesFileURL, options: .atomic)
        } catch {
            AppLogger.shared.log(.error, "preferences save failed: \(error.localizedDescription)")
        }
    }

    private func ensureDirectoryExists() throws {
        let directoryURL = preferencesFileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private static func defaultConfigDirectoryURL(fileManager: FileManager) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Suniye", isDirectory: true)
            .appendingPathComponent("config", isDirectory: true)
    }
}
