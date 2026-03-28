import XCTest
@testable import Suniye

@MainActor
final class AppStateLLMTests: XCTestCase {
    func testToggleOffSkipsLLM() async {
        let fakeLLM = FakeLLMPostProcessor(result: .success("polished"))
        let keychain = TestKeychainService(value: "api-key")
        let store = TestLLMSettingsStore()

        let appState = makeTestAppState(
            llmPostProcessor: fakeLLM,
            llmSettingsStore: store,
            keychainService: keychain
        )
        appState.llmEnabled = false

        let output = await appState.postProcessTextIfEnabled("raw text")

        XCTAssertEqual(output, "raw text")
        XCTAssertEqual(fakeLLM.callCount, 0)
    }

    func testToggleOnWithMissingKeyFallsBackToRaw() async {
        let fakeLLM = FakeLLMPostProcessor(result: .success("polished"))
        let keychain = TestKeychainService(value: nil)
        let store = TestLLMSettingsStore()

        let appState = makeTestAppState(
            llmPostProcessor: fakeLLM,
            llmSettingsStore: store,
            keychainService: keychain
        )
        appState.llmEnabled = true
        appState.refreshLLMKeyStatus()

        let output = await appState.postProcessTextIfEnabled("raw text")

        XCTAssertEqual(output, "raw text")
        XCTAssertEqual(fakeLLM.callCount, 0)
    }

    func testToggleOnSuccessUsesPolishedText() async {
        let fakeLLM = FakeLLMPostProcessor(result: .success("polished text"))
        let keychain = TestKeychainService(value: "api-key")
        let store = TestLLMSettingsStore()

        let appState = makeTestAppState(
            llmPostProcessor: fakeLLM,
            llmSettingsStore: store,
            keychainService: keychain
        )
        appState.llmEnabled = true
        appState.refreshLLMKeyStatus()

        let output = await appState.postProcessTextIfEnabled("raw text")

        XCTAssertEqual(output, "polished text")
        XCTAssertEqual(fakeLLM.callCount, 1)
    }

    func testToggleOnFailureFallsBackToRaw() async {
        let fakeLLM = FakeLLMPostProcessor(result: .failure(LLMPostProcessorError.timeout))
        let keychain = TestKeychainService(value: "api-key")
        let store = TestLLMSettingsStore()

        let appState = makeTestAppState(
            llmPostProcessor: fakeLLM,
            llmSettingsStore: store,
            keychainService: keychain
        )
        appState.llmEnabled = true
        appState.refreshLLMKeyStatus()

        let output = await appState.postProcessTextIfEnabled("raw text")

        XCTAssertEqual(output, "raw text")
        XCTAssertEqual(fakeLLM.callCount, 1)
    }

    func testToggleOnWithInvalidEndpointFallsBackToRawWithoutCallingProvider() async {
        let fakeLLM = FakeLLMPostProcessor(result: .success("polished"))
        let keychain = TestKeychainService(value: "api-key")
        let store = TestLLMSettingsStore()

        let appState = makeTestAppState(
            llmPostProcessor: fakeLLM,
            llmSettingsStore: store,
            keychainService: keychain
        )
        appState.llmEnabled = true
        appState.llmEndpointURLString = "not a url"
        appState.refreshLLMKeyStatus()

        let output = await appState.postProcessTextIfEnabled("raw text")

        XCTAssertEqual(output, "raw text")
        XCTAssertEqual(fakeLLM.callCount, 0)
        XCTAssertEqual(appState.llmEndpointValidationError, "Enter a valid http(s) endpoint URL.")
    }

    func testToggleOnWithInvalidCustomModelFallsBackToRawWithoutCallingProvider() async {
        let fakeLLM = FakeLLMPostProcessor(result: .success("polished"))
        let keychain = TestKeychainService(value: "api-key")
        let store = TestLLMSettingsStore()

        let appState = makeTestAppState(
            llmPostProcessor: fakeLLM,
            llmSettingsStore: store,
            keychainService: keychain
        )
        appState.llmEnabled = true
        appState.llmSelectedModelPreset = .custom
        appState.llmCustomModelId = "   "
        appState.refreshLLMKeyStatus()

        let output = await appState.postProcessTextIfEnabled("raw text")

        XCTAssertEqual(output, "raw text")
        XCTAssertEqual(fakeLLM.callCount, 0)
        XCTAssertEqual(appState.llmModelValidationError, "Enter a valid model ID.")
    }

    func testAttentionItemsIncludeMissingLLMKeyWhenEnabled() {
        let fakeLLM = FakeLLMPostProcessor(result: .success("polished"))
        let keychain = TestKeychainService(value: nil)
        let store = TestLLMSettingsStore()

        let appState = makeTestAppState(
            llmPostProcessor: fakeLLM,
            llmSettingsStore: store,
            keychainService: keychain
        )
        appState.llmEnabled = true
        appState.refreshLLMKeyStatus()

        XCTAssertTrue(appState.attentionItems.contains(where: { $0.id == "llm-key-missing" }))
    }

    func testAttentionItemsIncludeInvalidEndpointWhenEnabled() {
        let fakeLLM = FakeLLMPostProcessor(result: .success("polished"))
        let keychain = TestKeychainService(value: "api-key")
        let store = TestLLMSettingsStore()

        let appState = makeTestAppState(
            llmPostProcessor: fakeLLM,
            llmSettingsStore: store,
            keychainService: keychain
        )
        appState.llmEnabled = true
        appState.llmEndpointURLString = "not a url"
        appState.refreshLLMKeyStatus()

        XCTAssertTrue(appState.attentionItems.contains(where: { $0.id == "llm-endpoint-invalid" }))
    }

    func testAttentionItemsIncludeInvalidModelWhenEnabled() {
        let fakeLLM = FakeLLMPostProcessor(result: .success("polished"))
        let keychain = TestKeychainService(value: "api-key")
        let store = TestLLMSettingsStore()

        let appState = makeTestAppState(
            llmPostProcessor: fakeLLM,
            llmSettingsStore: store,
            keychainService: keychain
        )
        appState.llmEnabled = true
        appState.llmSelectedModelPreset = .custom
        appState.llmCustomModelId = "   "
        appState.refreshLLMKeyStatus()

        XCTAssertTrue(appState.attentionItems.contains(where: { $0.id == "llm-model-invalid" }))
    }

    func testOpenAIEndpointUsesNativePresetModelID() async {
        let fakeLLM = CapturingLLMPostProcessor(result: .success("polished"))
        let keychain = TestKeychainService(value: "api-key")
        let store = TestLLMSettingsStore()

        let appState = makeTestAppState(
            llmPostProcessor: fakeLLM,
            llmSettingsStore: store,
            keychainService: keychain
        )
        appState.llmEnabled = true
        appState.llmSelectedModelPreset = .gpt41Mini
        appState.llmEndpointURLString = "https://api.openai.com/v1/chat/completions"
        appState.refreshLLMKeyStatus()

        let output = await appState.postProcessTextIfEnabled("raw text")

        XCTAssertEqual(output, "polished")
        XCTAssertEqual(fakeLLM.lastConfig?.modelId, "gpt-4.1-mini")
    }

    func testLLMRuntimeSettingsClampAndPersist() {
        let fakeLLM = FakeLLMPostProcessor(result: .success("polished"))
        let keychain = TestKeychainService(value: "api-key")
        let store = TestLLMSettingsStore()

        let appState = makeTestAppState(
            llmPostProcessor: fakeLLM,
            llmSettingsStore: store,
            keychainService: keychain
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

private final class CapturingLLMPostProcessor: LLMPostProcessor {
    private let result: Result<String, Error>
    private(set) var lastConfig: LLMConfig?

    init(result: Result<String, Error>) {
        self.result = result
    }

    func polish(text: String, config: LLMConfig) async throws -> String {
        lastConfig = config
        return try result.get()
    }
}
