import Foundation

protocol HistoryStoreProtocol {
    func load() -> [HistoryEntry]
    func save(_ entries: [HistoryEntry])
}

final class HistoryStore: HistoryStoreProtocol {
    private let fileManager: FileManager
    private let historyFileURL: URL
    private let maxEntries: Int
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        fileManager: FileManager = .default,
        baseDirectoryURL: URL? = nil,
        filename: String = "history.json",
        maxEntries: Int = 500
    ) {
        self.fileManager = fileManager
        let baseURL = baseDirectoryURL ?? HistoryStore.defaultHistoryDirectoryURL(fileManager: fileManager)
        self.historyFileURL = baseURL.appendingPathComponent(filename, isDirectory: false)
        self.maxEntries = maxEntries
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() -> [HistoryEntry] {
        guard fileManager.fileExists(atPath: historyFileURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: historyFileURL)
            let decoded = try decoder.decode([HistoryEntry].self, from: data)
            return Array(decoded.prefix(maxEntries))
        } catch {
            AppLogger.shared.log(.warning, "history load failed: \(error.localizedDescription)")
            return []
        }
    }

    func save(_ entries: [HistoryEntry]) {
        let bounded = Array(entries.prefix(maxEntries))

        do {
            try ensureDirectoryExists()
            let data = try encoder.encode(bounded)
            try data.write(to: historyFileURL, options: .atomic)
        } catch {
            AppLogger.shared.log(.error, "history save failed: \(error.localizedDescription)")
        }
    }

    private func ensureDirectoryExists() throws {
        let directoryURL = historyFileURL.deletingLastPathComponent()
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
