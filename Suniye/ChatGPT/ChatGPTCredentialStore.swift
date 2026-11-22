import Foundation
import Security

/// One ChatGPT account that signed in on this Mac.
struct ChatGPTCredentials: Codable, Equatable, Sendable {
    struct Tokens: Codable, Equatable, Sendable {
        var accessToken: String
        /// Changes at each refresh; the old one stops working.
        var refreshToken: String
        var scopes: [String]
        var expiresAt: Date
    }

    /// The client ID that OpenAI issued for this account on this Mac.
    let clientID: String
    /// The account, from the checked ID token.
    let subject: String
    let email: String?
    /// Kept for the next sign-in to the same account.
    let idToken: String
    /// Nil after the sign-in ended: the user must sign in again.
    var tokens: Tokens?

    var registration: ChatGPTOAuth.Registration {
        ChatGPTOAuth.Registration(clientID: clientID, idToken: idToken, email: email)
    }
}

protocol ChatGPTCredentialStore: Sendable {
    func load() -> ChatGPTCredentials?
    func save(_ credentials: ChatGPTCredentials) throws
    func delete()
}

/// One generic-password item in the login Keychain. The service has the
/// bundle ID, so Suniye and Suniye Preview keep separate sign-ins: a refresh
/// token works once, and two apps with one token would end each other's
/// sign-in.
struct KeychainChatGPTCredentialStore: ChatGPTCredentialStore {
    struct WriteError: Error {
        let status: OSStatus
    }

    private let service: String
    private let account = "connection"

    init(bundleID: String = Bundle.main.bundleIdentifier ?? "dev.suniye.app") {
        service = "\(bundleID).chatgpt"
    }

    private var query: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
    }

    func load() -> ChatGPTCredentials? {
        var read = query
        read[kSecReturnData] = true
        read[kSecMatchLimit] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(read as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(ChatGPTCredentials.self, from: data)
    }

    func save(_ credentials: ChatGPTCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData] = data
            item[kSecAttrLabel] = "\(ChatGPTOAuth.appName) ChatGPT sign-in"
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw WriteError(status: status) }
    }

    func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
