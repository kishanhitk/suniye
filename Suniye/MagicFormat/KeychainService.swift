import Foundation

/// The API endpoint key. Magic Format and meeting summaries share it.
protocol KeychainServiceProtocol {
    func setLLMKey(_ key: String) async throws
    func getLLMKey() async throws -> String?
    func deleteLLMKey() async throws
}

enum KeychainServiceError: Error {
    case invalidData
}

/// Each call runs off the main actor: a SecItem call blocks its thread, also
/// while the user answers a Keychain prompt.
struct KeychainService: KeychainServiceProtocol {
    private let item: SecretItem

    init(item: SecretItem = KeychainItem(name: "api-endpoint", account: "api-key", label: "Suniye API key")) {
        self.item = item
    }

    @concurrent
    func setLLMKey(_ key: String) async throws {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw KeychainServiceError.invalidData
        }
        try item.write(Data(normalized.utf8))
    }

    @concurrent
    func getLLMKey() async throws -> String? {
        guard let data = try item.read() else {
            return nil
        }
        guard let key = String(data: data, encoding: .utf8) else {
            throw KeychainServiceError.invalidData
        }
        return key
    }

    @concurrent
    func deleteLLMKey() async throws {
        try item.delete()
    }

    /// Suniye kept the key in these files before it used the Keychain.
    static let plainTextKeyFilenames = ["llm_api_key.txt", "openrouter_api_key.txt"]

    static func removePlainTextKeyFiles(
        from directory: URL = AppSupportDirectory.urlOrHomeLibrary().appendingPathComponent("config", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        for filename in plainTextKeyFilenames {
            let url = directory.appendingPathComponent(filename, isDirectory: false)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            do {
                try fileManager.removeItem(at: url)
                AppLogger.shared.log(.info, "removed plain-text api key file \(filename)")
            } catch {
                AppLogger.shared.log(.error, "plain-text api key file \(filename) removal failed: \(error.localizedDescription)")
            }
        }
    }
}
