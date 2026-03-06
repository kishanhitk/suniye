import Foundation

final class AppLogger {
    static let shared = AppLogger()

    enum Level: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }

    private let queue = DispatchQueue(label: "dev.suniye.logger")
    private let formatter = ISO8601DateFormatter()
    private let maxFileSizeBytes: UInt64 = 2_000_000

    private(set) var logFileURL: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Suniye", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        logFileURL = base.appendingPathComponent("app.log")
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }
    }

    func log(_ level: Level, _ message: String) {
        queue.async { [self] in
            rotateIfNeeded()
            let timestamp = formatter.string(from: Date())
            let line = "\(timestamp) [\(level.rawValue)] [pid:\(ProcessInfo.processInfo.processIdentifier)] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: logFileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            }
        }
    }

    private func rotateIfNeeded() {
        guard
            let attrs = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
            let size = attrs[.size] as? UInt64,
            size >= maxFileSizeBytes
        else {
            return
        }

        let rotated = logFileURL.deletingLastPathComponent().appendingPathComponent("app.log.1")
        try? FileManager.default.removeItem(at: rotated)
        try? FileManager.default.moveItem(at: logFileURL, to: rotated)
        FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
    }
}
