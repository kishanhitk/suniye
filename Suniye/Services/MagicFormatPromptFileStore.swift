import Foundation

protocol MagicFormatPromptFileStoreProtocol {
    func syncPrompts(settings: LLMSettings) -> LLMSettings
    func syncAppPrompt(bundleID: String, fallback: String) -> String
    func saveProviderPrompt(_ prompt: MagicFormatEngine, content: String)
    func saveAppPrompt(bundleID: String, content: String)
    func providerPromptURL(_ prompt: MagicFormatEngine) -> URL
    func appPromptURL(bundleID: String) -> URL?
}

final class MagicFormatPromptFileStore: MagicFormatPromptFileStoreProtocol {
    private let fileManager: FileManager
    private let promptsDirectoryURL: URL

    init(fileManager: FileManager = .default, promptsDirectoryURL: URL? = nil) {
        self.fileManager = fileManager
        self.promptsDirectoryURL = promptsDirectoryURL ?? Self.defaultPromptsDirectoryURL(fileManager: fileManager)
    }

    func syncPrompts(settings: LLMSettings) -> LLMSettings {
        createPromptDirectoriesIfNeeded()

        var synced = settings
        for engine in MagicFormatEngine.allCases {
            synced[keyPath: engine.promptKeyPath] = readOrCreateProviderPrompt(engine, fallback: settings[keyPath: engine.promptKeyPath])
        }
        synced.appPromptBindings = settings.appPromptBindings.map { binding in
            var copy = binding
            copy.prompt = readOrCreateAppPrompt(bundleID: binding.bundleID, fallback: binding.prompt)
            return copy
        }
        return synced
    }

    func syncAppPrompt(bundleID: String, fallback: String) -> String {
        createPromptDirectoriesIfNeeded()
        return readOrCreateAppPrompt(bundleID: bundleID, fallback: fallback)
    }

    func saveProviderPrompt(_ prompt: MagicFormatEngine, content: String) {
        write(content, to: providerPromptURL(prompt))
    }

    func saveAppPrompt(bundleID: String, content: String) {
        guard let url = appPromptURL(bundleID: bundleID) else {
            return
        }
        write(content, to: url)
    }

    func providerPromptURL(_ prompt: MagicFormatEngine) -> URL {
        promptsDirectoryURL.appendingPathComponent(prompt.promptFilename, isDirectory: false)
    }

    func appPromptURL(bundleID: String) -> URL? {
        guard let normalized = AppPromptResolver.normalizedBundleID(bundleID) else {
            return nil
        }
        return appsDirectoryURL.appendingPathComponent("\(normalized).md", isDirectory: false)
    }

    private var appsDirectoryURL: URL {
        promptsDirectoryURL.appendingPathComponent("apps", isDirectory: true)
    }

    private func readOrCreateProviderPrompt(_ prompt: MagicFormatEngine, fallback: String) -> String {
        readOrCreate(url: providerPromptURL(prompt), fallback: fallback)
    }

    private func readOrCreateAppPrompt(bundleID: String, fallback: String) -> String {
        guard let url = appPromptURL(bundleID: bundleID) else {
            return fallback
        }
        return readOrCreate(url: url, fallback: fallback)
    }

    private func readOrCreate(url: URL, fallback: String) -> String {
        if let content = try? String(contentsOf: url, encoding: .utf8) {
            return content
        }
        write(fallback, to: url)
        return fallback
    }

    private func write(_ content: String, to url: URL) {
        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            AppLogger.shared.log(.warning, "magic format prompt file write failed: \(error.localizedDescription)")
        }
    }

    private func createPromptDirectoriesIfNeeded() {
        do {
            try fileManager.createDirectory(at: appsDirectoryURL, withIntermediateDirectories: true)
        } catch {
            AppLogger.shared.log(.warning, "magic format prompt directory creation failed: \(error.localizedDescription)")
        }
    }

    private static func defaultPromptsDirectoryURL(fileManager: FileManager) -> URL {
        let supportURL = AppSupportDirectory.url(fileManager: fileManager)
            ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(AppSupportDirectory.name, isDirectory: true)
        return supportURL.appendingPathComponent("prompts", isDirectory: true)
    }
}
