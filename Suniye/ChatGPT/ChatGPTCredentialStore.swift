import Foundation

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

/// Suniye and Suniye Preview must not share this item: a refresh token works
/// once, and two apps with one token would end each other's sign-in.
struct KeychainChatGPTCredentialStore: ChatGPTCredentialStore {
    private let item: SecretItem

    init(item: SecretItem = KeychainItem(name: "chatgpt", account: "connection", label: "\(ChatGPTOAuth.appName) ChatGPT sign-in")) {
        self.item = item
    }

    func load() -> ChatGPTCredentials? {
        guard let data = try? item.read() else { return nil }
        return try? JSONDecoder().decode(ChatGPTCredentials.self, from: data)
    }

    func save(_ credentials: ChatGPTCredentials) throws {
        try item.write(JSONEncoder().encode(credentials))
    }

    func delete() {
        try? item.delete()
    }
}
