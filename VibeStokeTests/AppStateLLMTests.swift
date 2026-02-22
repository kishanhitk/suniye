import XCTest
@testable import VibeStoke

@MainActor
final class AppStateLLMTests: XCTestCase {
    func testToggleOffSkipsLLM() async {
        let fakeLLM = FakeLLMPostProcessor(result: .success("polished"))
        let keychain = InMemoryKeychainService(value: "api-key")
        let store = InMemorySettingsStore()

        let appState = AppState(
            llmPostProcessor: fakeLLM,
            llmSettingsStore: store,
            keychainService: keychain,
            startServices: false,
            llmE2EMode: .none
        )
        appState.llmEnabled = false

        let output = await appState.postProcessTextIfEnabled("raw text")

        XCTAssertEqual(output, "raw text")
        XCTAssertEqual(fakeLLM.callCount, 0)
    }

    func testToggleOnWithMissingKeyFallsBackToRaw() async {
        let fakeLLM = FakeLLMPostProcessor(result: .success("polished"))
        let keychain = InMemoryKeychainService(value: nil)
        let store = InMemorySettingsStore()

        let appState = AppState(
            llmPostProcessor: fakeLLM,
            llmSettingsStore: store,
            keychainService: keychain,
            startServices: false,
            llmE2EMode: .none
        )
        appState.llmEnabled = true
        appState.refreshLLMKeyStatus()

        let output = await appState.postProcessTextIfEnabled("raw text")

        XCTAssertEqual(output, "raw text")
        XCTAssertEqual(fakeLLM.callCount, 0)
    }

    func testToggleOnSuccessUsesPolishedText() async {
        let fakeLLM = FakeLLMPostProcessor(result: .success("polished text"))
        let keychain = InMemoryKeychainService(value: "api-key")
        let store = InMemorySettingsStore()

        let appState = AppState(
            llmPostProcessor: fakeLLM,
            llmSettingsStore: store,
            keychainService: keychain,
            startServices: false,
            llmE2EMode: .none
        )
        appState.llmEnabled = true
        appState.refreshLLMKeyStatus()

        let output = await appState.postProcessTextIfEnabled("raw text")

        XCTAssertEqual(output, "polished text")
        XCTAssertEqual(fakeLLM.callCount, 1)
    }

    func testToggleOnFailureFallsBackToRaw() async {
        let fakeLLM = FakeLLMPostProcessor(result: .failure(LLMPostProcessorError.timeout))
        let keychain = InMemoryKeychainService(value: "api-key")
        let store = InMemorySettingsStore()

        let appState = AppState(
            llmPostProcessor: fakeLLM,
            llmSettingsStore: store,
            keychainService: keychain,
            startServices: false,
            llmE2EMode: .none
        )
        appState.llmEnabled = true
        appState.refreshLLMKeyStatus()

        let output = await appState.postProcessTextIfEnabled("raw text")

        XCTAssertEqual(output, "raw text")
        XCTAssertEqual(fakeLLM.callCount, 1)
    }

    func testAttentionItemsIncludeMissingLLMKeyWhenEnabled() {
        let fakeLLM = FakeLLMPostProcessor(result: .success("polished"))
        let keychain = InMemoryKeychainService(value: nil)
        let store = InMemorySettingsStore()

        let appState = AppState(
            llmPostProcessor: fakeLLM,
            llmSettingsStore: store,
            keychainService: keychain,
            startServices: false,
            llmE2EMode: .none
        )
        appState.llmEnabled = true
        appState.refreshLLMKeyStatus()

        XCTAssertTrue(appState.attentionItems.contains(where: { $0.id == "llm-key-missing" }))
    }

    func testLLMRuntimeSettingsClampAndPersist() {
        let fakeLLM = FakeLLMPostProcessor(result: .success("polished"))
        let keychain = InMemoryKeychainService(value: "api-key")
        let store = InMemorySettingsStore()

        let appState = AppState(
            llmPostProcessor: fakeLLM,
            llmSettingsStore: store,
            keychainService: keychain,
            startServices: false,
            llmE2EMode: .none
        )

        appState.llmTimeoutSeconds = 99
        appState.llmMaxTokens = 900

        XCTAssertEqual(appState.llmTimeoutSeconds, LLMDefaults.maxTimeoutSeconds)
        XCTAssertEqual(appState.llmMaxTokens, LLMDefaults.maxMaxTokens)
        XCTAssertEqual(store.latest.timeoutSeconds, LLMDefaults.maxTimeoutSeconds)
        XCTAssertEqual(store.latest.maxTokens, LLMDefaults.maxMaxTokens)

        appState.llmTimeoutSeconds = 0
        appState.llmMaxTokens = 1

        XCTAssertEqual(appState.llmTimeoutSeconds, LLMDefaults.minTimeoutSeconds)
        XCTAssertEqual(appState.llmMaxTokens, LLMDefaults.minMaxTokens)
        XCTAssertEqual(store.latest.timeoutSeconds, LLMDefaults.minTimeoutSeconds)
        XCTAssertEqual(store.latest.maxTokens, LLMDefaults.minMaxTokens)
    }
}

private final class FakeLLMPostProcessor: LLMPostProcessor {
    private let result: Result<String, Error>
    private(set) var callCount = 0

    init(result: Result<String, Error>) {
        self.result = result
    }

    func polish(text: String, config: LLMConfig) async throws -> String {
        callCount += 1
        return try result.get()
    }
}

private final class InMemorySettingsStore: LLMSettingsStoreProtocol {
    private var value = LLMSettings()

    var latest: LLMSettings {
        value
    }

    func load() -> LLMSettings {
        value
    }

    func save(_ settings: LLMSettings) {
        value = settings
    }
}

private final class InMemoryKeychainService: KeychainServiceProtocol {
    private var stored: String?

    init(value: String?) {
        stored = value
    }

    func setOpenRouterKey(_ key: String) throws {
        stored = key
    }

    func hasOpenRouterKey() -> Bool {
        stored?.isEmpty == false
    }

    func getOpenRouterKey() throws -> String? {
        stored
    }

    func deleteOpenRouterKey() throws {
        stored = nil
    }
}
