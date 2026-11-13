import Foundation

/// `~/Library/Application Support/Suniye`. The folder name is a contract: the
/// models, prompts, logs, stats and the analytics queue of current users live there.
enum AppSupportDirectory {
    static let name = "Suniye"

    /// nil only when macOS reports no Application Support folder.
    static func url(fileManager: FileManager = .default) -> URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(name, isDirectory: true)
    }

    /// For data that may live in a temporary folder when Application Support is missing.
    static func urlOrTemporary(fileManager: FileManager = .default) -> URL {
        url(fileManager: fileManager)
            ?? fileManager.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
    }
}
