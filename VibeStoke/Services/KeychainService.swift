import Foundation

protocol KeychainServiceProtocol {
    func setOpenRouterKey(_ key: String) throws
    func hasOpenRouterKey() -> Bool
    func getOpenRouterKey() throws -> String?
    func deleteOpenRouterKey() throws
}

enum KeychainServiceError: LocalizedError {
    case invalidData
    case writeFailed
    case readFailed
    case deleteFailed

    var errorDescription: String? {
        switch self {
        case .invalidData:
            return "Invalid API key data"
        case .writeFailed:
            return "Failed to save API key"
        case .readFailed:
            return "Failed to read API key"
        case .deleteFailed:
            return "Failed to clear API key"
        }
    }
}

final class KeychainService: KeychainServiceProtocol {
    private let fileManager: FileManager
    private let keyFileURL: URL

    init(baseDirectoryURL: URL? = nil, filename: String = "openrouter_api_key.txt", fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let baseDirectoryURL {
            self.keyFileURL = baseDirectoryURL.appendingPathComponent(filename, isDirectory: false)
            return
        }

        let defaultBaseDirectory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("VibeStoke", isDirectory: true)
            .appendingPathComponent("config", isDirectory: true)
        self.keyFileURL = defaultBaseDirectory.appendingPathComponent(filename, isDirectory: false)
    }

    func setOpenRouterKey(_ key: String) throws {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw KeychainServiceError.invalidData
        }

        do {
            try ensureDirectoryExists()
            try Data(normalized.utf8).write(to: keyFileURL, options: .atomic)
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyFileURL.path)
        } catch {
            throw KeychainServiceError.writeFailed
        }
    }

    func hasOpenRouterKey() -> Bool {
        do {
            guard let value = try getOpenRouterKey() else {
                return false
            }
            return !value.isEmpty
        } catch {
            return false
        }
    }

    func getOpenRouterKey() throws -> String? {
        guard fileManager.fileExists(atPath: keyFileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: keyFileURL)
            guard let key = String(data: data, encoding: .utf8) else {
                throw KeychainServiceError.invalidData
            }
            let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.isEmpty ? nil : normalized
        } catch let error as KeychainServiceError {
            throw error
        } catch {
            throw KeychainServiceError.readFailed
        }
    }

    func deleteOpenRouterKey() throws {
        guard fileManager.fileExists(atPath: keyFileURL.path) else {
            return
        }

        do {
            try fileManager.removeItem(at: keyFileURL)
        } catch {
            throw KeychainServiceError.deleteFailed
        }
    }

    private func ensureDirectoryExists() throws {
        let directoryURL = keyFileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }
}
