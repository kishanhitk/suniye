import Foundation
import Observation
import Security

enum ComputerUseModelProvider: String, CaseIterable, Codable, Sendable {
    case openAI
    case openRouter
    case custom

    var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .openRouter: "OpenRouter"
        case .custom: "Custom"
        }
    }

    var endpointURLString: String? {
        switch self {
        case .openAI: "https://api.openai.com/v1/chat/completions"
        case .openRouter: "https://openrouter.ai/api/v1/chat/completions"
        case .custom: nil
        }
    }
}

struct ComputerUseModelSettings: Codable, Equatable, Sendable {
    var provider: ComputerUseModelProvider = .openAI
    var modelID = "gpt-5.6-luna"
    var customEndpointURLString = ""
    var timeoutSeconds: Double = 120
    var maxTokens = 2_048

    var endpointURLString: String {
        provider.endpointURLString ?? customEndpointURLString
    }

    var endpointValidationError: String? {
        let value = endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return "Enter a valid HTTP or HTTPS endpoint."
        }
        return nil
    }

    var modelValidationError: String? {
        modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Enter a model ID."
            : nil
    }

    func configuration(apiKey: String?) -> ComputerUseRemoteModelConfiguration? {
        guard endpointValidationError == nil,
              modelValidationError == nil,
              let endpointURL = URL(
                string: endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines)
              ),
              let apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            return nil
        }
        return ComputerUseRemoteModelConfiguration(
            endpointURL: endpointURL,
            modelID: modelID.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: apiKey,
            timeoutSeconds: timeoutSeconds,
            maxTokens: maxTokens
        )
    }
}

protocol ComputerUseModelSettingsStoreProtocol {
    func load() -> ComputerUseModelSettings
    func save(_ settings: ComputerUseModelSettings)
}

final class ComputerUseModelSettingsStore: ComputerUseModelSettingsStoreProtocol {
    private let userDefaults: UserDefaults
    private let storageKey: String

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "dev.suniye.computer-use.model-settings"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
    }

    func load() -> ComputerUseModelSettings {
        guard let data = userDefaults.data(forKey: storageKey) else {
            return ComputerUseModelSettings()
        }
        return (try? JSONDecoder().decode(ComputerUseModelSettings.self, from: data))
            ?? ComputerUseModelSettings()
    }

    func save(_ settings: ComputerUseModelSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        userDefaults.set(data, forKey: storageKey)
    }
}

protocol ComputerUseCredentialStoring {
    func setAPIKey(_ key: String) throws
    func hasAPIKey() -> Bool
    func getAPIKey() throws -> String?
    func deleteAPIKey() throws
}

final class ComputerUseCredentialStore: ComputerUseCredentialStoring {
    private let service: String
    private let account: String

    init(
        service: String = Bundle.main.bundleIdentifier ?? "dev.suniye.app",
        account: String = "computer-use-api-key"
    ) {
        self.service = service
        self.account = account
    }

    func setAPIKey(_ key: String) throws {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw KeychainServiceError.invalidData }
        let data = Data(normalized.utf8)
        let query = baseQuery
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw KeychainServiceError.writeFailed }
        var addQuery = query
        addQuery[kSecValueData as String] = data
        guard SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess else {
            throw KeychainServiceError.writeFailed
        }
    }

    func hasAPIKey() -> Bool {
        do {
            return try getAPIKey()?.isEmpty == false
        } catch {
            return false
        }
    }

    func getAPIKey() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainServiceError.readFailed
        }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    func deleteAPIKey() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainServiceError.deleteFailed
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

protocol ComputerUseModelConnectionTesting: Sendable {
    func test(configuration: ComputerUseRemoteModelConfiguration) async throws
}

struct ComputerUseModelConnectionTester: ComputerUseModelConnectionTesting {
    func test(configuration: ComputerUseRemoteModelConfiguration) async throws {
        let client = ComputerUseRemoteModelClient(configuration: configuration)
        _ = try await client.respond(to: [
            .text(role: .user, text: "Reply with OK. Do not call a tool."),
        ])
    }
}

enum ComputerUseModelConnectionState: Equatable {
    case idle
    case testing
    case connected
    case failed(String)
}

@MainActor
@Observable
final class ComputerUseModelSettingsController {
    var settings: ComputerUseModelSettings {
        didSet {
            guard settings != oldValue else { return }
            settingsStore.save(settings)
            connectionState = .idle
            publishConfiguration()
        }
    }
    var apiKeyDraft = ""
    private(set) var hasAPIKey: Bool
    private(set) var credentialError: String?
    private(set) var connectionState: ComputerUseModelConnectionState = .idle

    private let settingsStore: ComputerUseModelSettingsStoreProtocol
    private let credentialStore: ComputerUseCredentialStoring
    private let connectionTester: ComputerUseModelConnectionTesting
    private let onConfigurationChange: (ComputerUseRemoteModelConfiguration?) -> Void

    init(
        settingsStore: ComputerUseModelSettingsStoreProtocol = ComputerUseModelSettingsStore(),
        credentialStore: ComputerUseCredentialStoring = ComputerUseCredentialStore(),
        connectionTester: ComputerUseModelConnectionTesting = ComputerUseModelConnectionTester(),
        onConfigurationChange: @escaping (ComputerUseRemoteModelConfiguration?) -> Void = { _ in }
    ) {
        self.settingsStore = settingsStore
        self.credentialStore = credentialStore
        self.connectionTester = connectionTester
        self.onConfigurationChange = onConfigurationChange
        settings = settingsStore.load()
        hasAPIKey = credentialStore.hasAPIKey()
    }

    var modelConfiguration: ComputerUseRemoteModelConfiguration? {
        settings.configuration(apiKey: try? credentialStore.getAPIKey())
    }

    var isReady: Bool { modelConfiguration != nil }

    func publishConfiguration() {
        onConfigurationChange(modelConfiguration)
    }

    func saveAPIKey(_ key: String? = nil) {
        let value = (key ?? apiKeyDraft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            credentialError = "API key can't be empty."
            return
        }
        do {
            try credentialStore.setAPIKey(value)
            apiKeyDraft = ""
            hasAPIKey = true
            credentialError = nil
            connectionState = .idle
            publishConfiguration()
        } catch {
            credentialError = "Couldn't save the API key."
        }
    }

    func clearAPIKey() {
        do {
            try credentialStore.deleteAPIKey()
            apiKeyDraft = ""
            hasAPIKey = false
            credentialError = nil
            connectionState = .idle
            publishConfiguration()
        } catch {
            credentialError = "Couldn't clear the API key."
        }
    }

    func testConnection() async {
        guard let configuration = modelConfiguration else {
            connectionState = .failed("Complete the model settings first.")
            return
        }
        connectionState = .testing
        do {
            try await connectionTester.test(configuration: configuration)
            connectionState = .connected
        } catch is CancellationError {
            connectionState = .idle
        } catch {
            connectionState = .failed(error.localizedDescription)
        }
    }
}
