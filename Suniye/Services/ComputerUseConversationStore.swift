import Foundation

protocol ComputerUseConversationStoring {
    func load() -> [ComputerUseConversationMessage]
    func save(_ conversation: [ComputerUseConversationMessage])
}

struct NoopComputerUseConversationStore: ComputerUseConversationStoring {
    func load() -> [ComputerUseConversationMessage] { [] }
    func save(_ conversation: [ComputerUseConversationMessage]) {}
}

final class ComputerUseConversationStore: ComputerUseConversationStoring, @unchecked Sendable {
    private let fileURL: URL
    private let fileManager: FileManager
    private let queue = DispatchQueue(label: "dev.suniye.computer-use-conversation-store")

    init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default,
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "dev.suniye.app"
    ) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(
            fileManager: fileManager,
            bundleIdentifier: bundleIdentifier
        )
    }

    func load() -> [ComputerUseConversationMessage] {
        queue.sync { loadFromDisk() }
    }

    func save(_ conversation: [ComputerUseConversationMessage]) {
        queue.async { [self] in
            saveToDisk(conversation)
        }
    }

    private func loadFromDisk() -> [ComputerUseConversationMessage] {
        guard let data = try? Data(contentsOf: fileURL) else {
            return []
        }
        do {
            let decoder = JSONDecoder()
            return try decoder.decode([ComputerUseConversationMessage].self, from: data)
        } catch {
            AppLogger.shared.log(
                .warning,
                "computer use conversation load failed: \(error.localizedDescription)"
            )
            return []
        }
    }

    private func saveToDisk(_ conversation: [ComputerUseConversationMessage]) {
        guard !conversation.isEmpty else {
            do {
                if fileManager.fileExists(atPath: fileURL.path) {
                    try fileManager.removeItem(at: fileURL)
                }
            } catch {
                AppLogger.shared.log(
                    .warning,
                    "computer use conversation clear failed: \(error.localizedDescription)"
                )
            }
            return
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(conversation)
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            AppLogger.shared.log(
                .warning,
                "computer use conversation save failed: \(error.localizedDescription)"
            )
        }
    }

    private static func defaultFileURL(
        fileManager: FileManager,
        bundleIdentifier: String
    ) -> URL {
        let supportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return supportURL
            .appendingPathComponent("Suniye", isDirectory: true)
            .appendingPathComponent("computer-use", isDirectory: true)
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("current-session.json")
    }
}
