import Foundation

protocol StatsStoreProtocol {
    func load() -> StatsSnapshot
    func save(_ snapshot: StatsSnapshot)
}

final class StatsStore: StatsStoreProtocol {
    private let fileManager: FileManager
    private let statsFileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        fileManager: FileManager = .default,
        baseDirectoryURL: URL? = nil,
        filename: String = "stats.json"
    ) {
        self.fileManager = fileManager
        let baseURL = baseDirectoryURL ?? StatsStore.defaultHistoryDirectoryURL(fileManager: fileManager)
        self.statsFileURL = baseURL.appendingPathComponent(filename, isDirectory: false)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() -> StatsSnapshot {
        guard fileManager.fileExists(atPath: statsFileURL.path) else {
            return .zero
        }

        do {
            let data = try Data(contentsOf: statsFileURL)
            return try decoder.decode(StatsSnapshot.self, from: data)
        } catch {
            AppLogger.shared.log(.warning, "stats load failed: \(error.localizedDescription)")
            return .zero
        }
    }

    func save(_ snapshot: StatsSnapshot) {
        do {
            try ensureDirectoryExists()
            let data = try encoder.encode(snapshot)
            try data.write(to: statsFileURL, options: .atomic)
        } catch {
            AppLogger.shared.log(.error, "stats save failed: \(error.localizedDescription)")
        }
    }

    private func ensureDirectoryExists() throws {
        let directoryURL = statsFileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private static func defaultHistoryDirectoryURL(fileManager: FileManager) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("VibeStoke", isDirectory: true)
            .appendingPathComponent("history", isDirectory: true)
    }
}
