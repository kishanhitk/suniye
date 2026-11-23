import Foundation
import Security

/// One secret that the app saves.
protocol SecretItem: Sendable {
    func read() throws -> Data?
    func write(_ data: Data) throws
    func delete() throws
}

struct KeychainError: Error, Equatable {
    let status: OSStatus
}

/// A generic-password item in the login Keychain. Every secret that the app
/// saves goes through this type.
struct KeychainItem: SecretItem {
    /// The app is also the XCTest host, and a test run must not touch the
    /// login Keychain: there every item is empty and a write fails.
    private static let isTestRun = ProcessInfo.processInfo.isRunningUnderXCTest

    private let service: String
    private let account: String
    private let label: String

    /// The service is the bundle ID followed by `name`, so Suniye and Suniye
    /// Preview keep separate items.
    init(name: String, account: String, label: String) {
        service = "\(Bundle.main.bundleIdentifier ?? "dev.suniye.app").\(name)"
        self.account = account
        self.label = label
    }

    private var query: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
    }

    func read() throws -> Data? {
        guard !Self.isTestRun else { return nil }
        var read = query
        read[kSecReturnData] = true
        read[kSecMatchLimit] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(read as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            return item as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: status)
        }
    }

    func write(_ data: Data) throws {
        guard !Self.isTestRun else { throw KeychainError(status: errSecNotAvailable) }
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData] = data
            item[kSecAttrLabel] = label
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    func delete() throws {
        guard !Self.isTestRun else { return }
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}
