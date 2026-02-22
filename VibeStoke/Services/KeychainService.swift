import Foundation
import Security

protocol KeychainServiceProtocol {
    func setOpenRouterKey(_ key: String) throws
    func hasOpenRouterKey() -> Bool
    func getOpenRouterKey() throws -> String?
    func deleteOpenRouterKey() throws
}

enum KeychainServiceError: LocalizedError {
    case invalidData
    case osStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidData:
            return "Invalid keychain data"
        case let .osStatus(code):
            return "Keychain error: \(code)"
        }
    }
}

final class KeychainService: KeychainServiceProtocol {
    private let service: String
    private let account: String

    init(service: String = "dev.vibestroke.app.openrouter", account: String = "api-key") {
        self.service = service
        self.account = account
    }

    func setOpenRouterKey(_ key: String) throws {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw KeychainServiceError.invalidData
        }

        let data = Data(normalized.utf8)
        let query = baseQuery()

        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainServiceError.osStatus(addStatus)
            }
            return
        }

        throw KeychainServiceError.osStatus(updateStatus)
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
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainServiceError.osStatus(status)
        }

        guard let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw KeychainServiceError.invalidData
        }
        return key
    }

    func deleteOpenRouterKey() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            return
        }
        throw KeychainServiceError.osStatus(status)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
