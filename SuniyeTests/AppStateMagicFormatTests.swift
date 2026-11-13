import XCTest
@testable import Suniye

@MainActor
final class AppStateMagicFormatTests: XCTestCase {
    func testSetupTestReturnsEarlyWhenDisabled() async {
        let appState = makeTestAppState(keychainService: TestKeychainService(value: "key"))
        appState.refreshLLMKeyStatus()
        appState.llmEnabled = false

        await appState.testMagicFormatSetup(apiKeyDraft: "draft")

        XCTAssertNil(appState.magicFormatSetupTestResult)
        XCTAssertFalse(appState.isMagicFormatSetupTestInProgress)
    }

    /// The endpoint set-up sheet exists so an endpoint can be configured and
    /// tested *before* switching to it, so the API test no longer requires the
    /// API engine to be the selected one. It used to return early here.
    func testSetupTestRunsEvenWhenAnotherProviderIsSelected() async {
        let appState = makeTestAppState(
            appleMagicFormatPostProcessor: NoopAppleMagicFormatPostProcessor(availability: .available),
            keychainService: TestKeychainService(value: "key")
        )
        appState.refreshLLMKeyStatus()
        appState.llmEnabled = true
        appState.llmProvider = .appleFoundationModels

        await appState.testMagicFormatSetup(apiKeyDraft: "draft")

        XCTAssertEqual(appState.magicFormatSetupTestResult?.severity, .success)
        XCTAssertFalse(appState.isMagicFormatSetupTestInProgress)
        XCTAssertNil(appState.magicFormatTestingProvider)
    }

    func testSetupTestReturnsEarlyForInvalidEndpoint() async {
        let appState = makeTestAppState(keychainService: TestKeychainService(value: "key"))
        appState.refreshLLMKeyStatus()
        appState.llmEnabled = true
        appState.llmEndpointURLString = "not a url"

        await appState.testMagicFormatSetup(apiKeyDraft: "draft")

        XCTAssertNil(appState.magicFormatSetupTestResult)
    }

    func testSetupTestReturnsEarlyForInvalidModel() async {
        let appState = makeTestAppState(keychainService: TestKeychainService(value: "key"))
        appState.refreshLLMKeyStatus()
        appState.llmEnabled = true
        appState.llmSelectedModelPreset = .custom
        appState.llmCustomModelId = "   "

        await appState.testMagicFormatSetup(apiKeyDraft: "draft")

        XCTAssertNil(appState.magicFormatSetupTestResult)
    }

    func testSetupTestReturnsEarlyWithoutAnyAPIKey() async {
        let appState = makeTestAppState(keychainService: TestKeychainService(value: nil))
        appState.llmEnabled = true

        await appState.testMagicFormatSetup(apiKeyDraft: "   ")

        XCTAssertNil(appState.magicFormatSetupTestResult)
        XCTAssertFalse(appState.isMagicFormatSetupTestInProgress)
    }

    private func runSetupTest(error: Error) async -> AppState {
        let fakeLLM = FakeLLMPostProcessor(
            result: .success("polished"),
            testSetupResult: .failure(error)
        )
        let appState = makeTestAppState(
            llmPostProcessor: fakeLLM,
            keychainService: TestKeychainService(value: "api-key")
        )
        appState.llmEnabled = true
        appState.refreshLLMKeyStatus()
        await appState.testMagicFormatSetup(apiKeyDraft: "")
        return appState
    }

    func testSetupTestMapsRateLimitAndServerErrors() async {
        var appState = await runSetupTest(error: LLMPostProcessorError.provider("http_429"))
        XCTAssertEqual(
            appState.magicFormatSetupTestResult?.message,
            "HTTP 429: rate limited. Try again in a moment."
        )

        appState = await runSetupTest(error: LLMPostProcessorError.provider("http_503"))
        XCTAssertEqual(
            appState.magicFormatSetupTestResult?.message,
            "HTTP 503: server error. Try again."
        )

        appState = await runSetupTest(error: LLMPostProcessorError.provider("model_not_found"))
        XCTAssertEqual(
            appState.magicFormatSetupTestResult?.message,
            "The service rejected this setup. Check the URL and model, then try again."
        )
    }

    func testSetupTestMapsUnknownErrorToUnreachableService() async {
        let appState = await runSetupTest(error: FakeError(message: "socket melted"))
        XCTAssertEqual(
            appState.magicFormatSetupTestResult,
            MagicFormatSetupTestResult(message: "Couldn't reach that service URL.", severity: .error)
        )
    }

    func testSetupTestFailureAfterClearIsIgnoredAsStale() async {
        let blockingLLM = BlockingLLMPostProcessor()
        blockingLLM.testSetupResult = .failure(LLMPostProcessorError.timeout)
        let appState = makeTestAppState(
            llmPostProcessor: blockingLLM,
            keychainService: TestKeychainService(value: "api-key")
        )
        appState.llmEnabled = true
        appState.refreshLLMKeyStatus()

        let task = Task {
            await appState.testMagicFormatSetup(apiKeyDraft: "")
        }
        await blockingLLM.waitUntilStarted()
        appState.clearMagicFormatSetupTestResult()
        blockingLLM.resume()
        await task.value

        XCTAssertNil(appState.magicFormatSetupTestResult)
        XCTAssertFalse(appState.isMagicFormatSetupTestInProgress)
    }

    func testSaveLLMAPIKeySuccessAndEmptyInput() {
        let keychain = FailingKeychainService()
        let appState = makeTestAppState(keychainService: keychain)

        appState.saveLLMAPIKey("   ")
        XCTAssertEqual(appState.llmKeyOperationError, "API key can't be empty.")
        XCTAssertFalse(appState.hasLLMAPIKey)

        appState.saveLLMAPIKey("  secret-key  ")
        XCTAssertNil(appState.llmKeyOperationError)
        XCTAssertTrue(appState.hasLLMAPIKey)
        XCTAssertEqual(keychain.storedKey, "secret-key")
    }

    func testSaveLLMAPIKeyFailureSetsOperationError() {
        let keychain = FailingKeychainService()
        keychain.setError = FakeError(message: "keychain locked")
        let appState = makeTestAppState(keychainService: keychain)

        appState.saveLLMAPIKey("secret")

        XCTAssertEqual(appState.llmKeyOperationError, "Couldn't save the API key.")
        XCTAssertFalse(appState.hasLLMAPIKey)
    }

    func testClearLLMAPIKeySuccessAndFailure() {
        let keychain = FailingKeychainService()
        keychain.storedKey = "secret"
        let appState = makeTestAppState(keychainService: keychain)
        appState.refreshLLMKeyStatus()
        XCTAssertTrue(appState.hasLLMAPIKey)

        appState.clearLLMAPIKey()
        XCTAssertNil(appState.llmKeyOperationError)
        XCTAssertFalse(appState.hasLLMAPIKey)
        XCTAssertNil(keychain.storedKey)

        keychain.deleteError = FakeError(message: "keychain locked")
        appState.clearLLMAPIKey()
        XCTAssertEqual(appState.llmKeyOperationError, "Couldn't clear the API key.")
    }

    func testAPIKeyReadFailureDuringPolishFallsBackAndRefreshesKeyStatus() async {
        let keychain = FailingKeychainService()
        keychain.storedKey = "secret"
        let appState = makeTestAppState(
            llmPostProcessor: FakeLLMPostProcessor(result: .success("polished!")),
            keychainService: keychain
        )
        appState.llmEnabled = true
        appState.llmProvider = .openAICompatible
        appState.refreshLLMKeyStatus()
        XCTAssertTrue(appState.hasLLMAPIKey)

        keychain.getError = FakeError(message: "read denied")
        keychain.storedKey = nil

        let output = await appState.postProcessTextIfEnabled("hello world")

        XCTAssertEqual(output, "hello world")
        XCTAssertFalse(appState.hasLLMAPIKey)
    }

    func testPostProcessReturnsRawTextForWhitespaceInput() async {
        let appState = makeTestAppState()
        appState.llmEnabled = true

        let output = await appState.postProcessTextIfEnabled("   \n  ")

        XCTAssertEqual(output, "   \n  ")
    }

    func testPostProcessHonorsForcedE2EModes() async {
        let success = makeTestAppState(llmE2EMode: .forceSuccess)
        success.llmEnabled = true
        let successOutput = await success.postProcessTextIfEnabled("hello world")
        XCTAssertEqual(successOutput, "hello world.")

        let fallback = makeTestAppState(llmE2EMode: .forceFailure)
        fallback.llmEnabled = true
        let fallbackOutput = await fallback.postProcessTextIfEnabled("hello world")
        XCTAssertEqual(fallbackOutput, "hello world")
    }

    func testEditingBasePromptWritesProviderPromptFile() throws {
        let promptStore = MagicFormatPromptFileStore(
            promptsDirectoryURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("suniye-prompt-write-\(UUID().uuidString)", isDirectory: true)
        )
        let appState = makeTestAppState(magicFormatPromptFileStore: promptStore)

        appState.llmBaseSystemPrompt = "rewritten base prompt"

        let content = try String(contentsOf: promptStore.providerPromptURL(.openAICompatible), encoding: .utf8)
        XCTAssertEqual(content, "rewritten base prompt")
    }

    func testUpdateAppPromptBindingIgnoresUnknownID() {
        let appState = makeTestAppState()
        let binding = appState.addAppPromptBinding(bundleID: "com.example.app", appDisplayName: "Example")

        appState.updateAppPromptBinding(id: UUID(), prompt: "should not land")

        XCTAssertEqual(
            appState.llmAppPromptBindings.first(where: { $0.id == binding!.id })?.prompt,
            binding!.prompt
        )
    }

    func testAddVocabularyTermIgnoresWhitespaceOnlyInput() {
        let appState = makeTestAppState()
        appState.llmKeywordsRaw = "existing"

        appState.addVocabularyTerm("   ")

        XCTAssertEqual(appState.llmKeywordsRaw, "existing")
    }

    func testEndpointAndModelValidationSkippedForLocalProviders() {
        let appState = makeTestAppState(
            appleMagicFormatPostProcessor: NoopAppleMagicFormatPostProcessor(availability: .available)
        )
        appState.llmProvider = .appleFoundationModels
        appState.llmEndpointURLString = "not a url"
        appState.llmSelectedModelPreset = .custom
        appState.llmCustomModelId = ""

        XCTAssertNil(appState.llmEndpointValidationError)
        XCTAssertNil(appState.llmModelValidationError)
    }

    func testMagicFormatStatusIsOffWhenDisabled() {
        let appState = makeTestAppState()

        XCTAssertEqual(appState.magicFormatSetupState, .off)
    }

    func testMagicFormatStatusNeedsAPIKeyWhenEnabledWithoutKey() {
        let appState = makeTestAppState()
        appState.llmEnabled = true

        XCTAssertEqual(appState.magicFormatSetupState, .needsAPIKey)
        XCTAssertTrue(appState.attentionItems.contains {
            $0.id == "llm-key-missing"
                && $0.title == "Magic Format needs an API key"
                && $0.detail == "Magic Format is on, but your API key is missing."
        })
    }

    func testMagicFormatStatusNeedsServiceSetupWhenEndpointInvalid() {
        let appState = makeTestAppState()
        appState.llmEnabled = true
        appState.llmEndpointURLString = "not a url"

        XCTAssertEqual(appState.magicFormatSetupState, .needsServiceSetup)
        XCTAssertEqual(appState.llmEndpointValidationError, "Enter a valid service URL.")
        XCTAssertTrue(appState.attentionItems.contains {
            $0.id == "llm-endpoint-invalid"
                && $0.title == "Magic Format needs service setup"
                && $0.detail == "Enter a valid service URL."
        })
    }

    func testMagicFormatStatusIsReadyWhenEnabledAndConfigured() {
        let appState = makeTestAppState(keychainService: TestKeychainService(value: "test-key"))
        appState.llmEnabled = true
        appState.refreshLLMKeyStatus()

        XCTAssertEqual(appState.magicFormatSetupState, .ready)
    }

    func testCanTestMagicFormatSetupRequiresEnabledValidConfigAndKey() {
        let fakeLLM = FakeLLMPostProcessor(result: .success("polished"))
        let keychain = TestKeychainService(value: nil)
        let store = TestLLMSettingsStore()

        let appState = makeTestAppState(
            llmPostProcessor: fakeLLM,
            llmSettingsStore: store,
            keychainService: keychain
        )

        XCTAssertFalse(appState.canTestMagicFormatSetup(apiKeyDraft: "draft-key"))

        appState.llmEnabled = true
        XCTAssertTrue(appState.canTestMagicFormatSetup(apiKeyDraft: "draft-key"))

        appState.llmEndpointURLString = "not a url"
        XCTAssertFalse(appState.canTestMagicFormatSetup(apiKeyDraft: "draft-key"))

        appState.llmEndpointURLString = LLMDefaults.defaultEndpointURLString
        appState.llmSelectedModelPreset = .custom
        appState.llmCustomModelId = "   "
        XCTAssertFalse(appState.canTestMagicFormatSetup(apiKeyDraft: "draft-key"))

        appState.llmSelectedModelPreset = .gpt41Mini
        appState.llmCustomModelId = ""
        XCTAssertFalse(appState.canTestMagicFormatSetup(apiKeyDraft: ""))
    }

    func testTestMagicFormatSetupUsesDraftKeyWithoutSavingIt() async throws {
        let fakeLLM = CapturingLLMPostProcessor(result: .success("polished"))
        let keychain = TestKeychainService(value: "saved-key")
        let store = TestLLMSettingsStore()

        let appState = makeTestAppState(
            llmPostProcessor: fakeLLM,
            llmSettingsStore: store,
            keychainService: keychain
        )
        appState.llmEnabled = true
        appState.refreshLLMKeyStatus()

        await appState.testMagicFormatSetup(apiKeyDraft: "draft-key")

        XCTAssertEqual(fakeLLM.lastTestConfig?.apiKey, "draft-key")
        XCTAssertEqual(try keychain.getLLMKey(), "saved-key")
    }

    func testTestMagicFormatSetupWithDraftKeyDoesNotMarkUnsavedKeyAsConnected() async {
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

        await appState.testMagicFormatSetup(apiKeyDraft: "draft-key")

        // Assert the meaningful fields, not the whole struct: the result also
        // carries a measured latency, which is not deterministic in a test.
        XCTAssertEqual(appState.magicFormatSetupTestResult?.message, "Connection works.")
        XCTAssertEqual(appState.magicFormatSetupTestResult?.severity, .success)
    }

    func testTestMagicFormatSetupUsesSavedKeyWhenDraftIsEmpty() async {
        let fakeLLM = CapturingLLMPostProcessor(result: .success("polished"))
        let keychain = TestKeychainService(value: "saved-key")
        let store = TestLLMSettingsStore()

        let appState = makeTestAppState(
            llmPostProcessor: fakeLLM,
            llmSettingsStore: store,
            keychainService: keychain
        )
        appState.llmEnabled = true
        appState.refreshLLMKeyStatus()

        await appState.testMagicFormatSetup(apiKeyDraft: "   ")

        XCTAssertEqual(fakeLLM.lastTestConfig?.apiKey, "saved-key")
    }

    func testTestMagicFormatSetupTracksProgressAndSuccessResult() async {
        let fakeLLM = BlockingLLMPostProcessor()
        let keychain = TestKeychainService(value: "api-key")
        let store = TestLLMSettingsStore()

        let appState = makeTestAppState(
            llmPostProcessor: fakeLLM,
            llmSettingsStore: store,
            keychainService: keychain
        )
        appState.llmEnabled = true
        appState.refreshLLMKeyStatus()

        let task = Task {
            await appState.testMagicFormatSetup(apiKeyDraft: "")
        }

        await fakeLLM.waitUntilStarted()
        XCTAssertTrue(appState.isMagicFormatSetupTestInProgress)
        XCTAssertNil(appState.magicFormatSetupTestResult)

        fakeLLM.resume()
        await task.value

        XCTAssertFalse(appState.isMagicFormatSetupTestInProgress)
        // Assert the meaningful fields, not the whole struct: the result also
        // carries a measured latency, which is not deterministic in a test.
        XCTAssertEqual(appState.magicFormatSetupTestResult?.message, "Connection works.")
        XCTAssertEqual(appState.magicFormatSetupTestResult?.severity, .success)
    }

    func testTestMagicFormatSetupIgnoresStaleResultAfterSettingsChange() async {
        let fakeLLM = BlockingLLMPostProcessor()
        let keychain = TestKeychainService(value: "api-key")
        let store = TestLLMSettingsStore()

        let appState = makeTestAppState(
            llmPostProcessor: fakeLLM,
            llmSettingsStore: store,
            keychainService: keychain
        )
        appState.llmEnabled = true
        appState.refreshLLMKeyStatus()

        let task = Task {
            await appState.testMagicFormatSetup(apiKeyDraft: "")
        }

        await fakeLLM.waitUntilStarted()
        XCTAssertTrue(appState.isMagicFormatSetupTestInProgress)

        appState.llmEndpointURLString = "not a url"

        XCTAssertFalse(appState.isMagicFormatSetupTestInProgress)
        XCTAssertNil(appState.magicFormatSetupTestResult)

        fakeLLM.resume()
        await task.value

        XCTAssertNil(appState.magicFormatSetupTestResult)
        XCTAssertFalse(appState.isMagicFormatSetupTestInProgress)
    }

    func testTestMagicFormatSetupMapsUnauthorizedError() async {
        let fakeLLM = FakeLLMPostProcessor(
            result: .success("polished"),
            testSetupResult: .failure(LLMPostProcessorError.unauthorized)
        )
        let keychain = TestKeychainService(value: "api-key")
        let store = TestLLMSettingsStore()

        let appState = makeTestAppState(
            llmPostProcessor: fakeLLM,
            llmSettingsStore: store,
            keychainService: keychain
        )
        appState.llmEnabled = true
        appState.refreshLLMKeyStatus()

        await appState.testMagicFormatSetup(apiKeyDraft: "")

        XCTAssertEqual(
            appState.magicFormatSetupTestResult,
            MagicFormatSetupTestResult(message: "The API key was rejected.", severity: .error)
        )
    }

    func testTestMagicFormatSetupMapsNetworkError() async {
        let fakeLLM = FakeLLMPostProcessor(
            result: .success("polished"),
            testSetupResult: .failure(LLMPostProcessorError.timeout)
        )
        let keychain = TestKeychainService(value: "api-key")
        let store = TestLLMSettingsStore()

        let appState = makeTestAppState(
            llmPostProcessor: fakeLLM,
            llmSettingsStore: store,
            keychainService: keychain
        )
        appState.llmEnabled = true
        appState.refreshLLMKeyStatus()

        await appState.testMagicFormatSetup(apiKeyDraft: "")

        XCTAssertEqual(
            appState.magicFormatSetupTestResult,
            MagicFormatSetupTestResult(message: "Couldn't reach that service URL.", severity: .error)
        )
    }

    func testTestMagicFormatSetupMapsProviderError() async {
        let fakeLLM = FakeLLMPostProcessor(
            result: .success("polished"),
            testSetupResult: .failure(LLMPostProcessorError.provider("http_400"))
        )
        let keychain = TestKeychainService(value: "api-key")
        let store = TestLLMSettingsStore()

        let appState = makeTestAppState(
            llmPostProcessor: fakeLLM,
            llmSettingsStore: store,
            keychainService: keychain
        )
        appState.llmEnabled = true
        appState.refreshLLMKeyStatus()

        await appState.testMagicFormatSetup(apiKeyDraft: "")

        XCTAssertEqual(
            appState.magicFormatSetupTestResult,
            MagicFormatSetupTestResult(
                message: "HTTP 400: the service rejected this setup. Check the URL and model.",
                severity: .error
            )
        )
    }

    func testTestMagicFormatSetupMapsProvider404ErrorToEndpointMessage() async {
        let fakeLLM = FakeLLMPostProcessor(
            result: .success("polished"),
            testSetupResult: .failure(LLMPostProcessorError.provider("http_404"))
        )
        let keychain = TestKeychainService(value: "api-key")
        let store = TestLLMSettingsStore()

        let appState = makeTestAppState(
            llmPostProcessor: fakeLLM,
            llmSettingsStore: store,
            keychainService: keychain
        )
        appState.llmEnabled = true
        appState.refreshLLMKeyStatus()

        await appState.testMagicFormatSetup(apiKeyDraft: "")

        XCTAssertEqual(
            appState.magicFormatSetupTestResult,
            MagicFormatSetupTestResult(message: "HTTP 404: service URL not found.", severity: .error)
        )
    }

    func testTestMagicFormatSetupMapsMalformedResponseError() async {
        let fakeLLM = FakeLLMPostProcessor(
            result: .success("polished"),
            testSetupResult: .failure(LLMPostProcessorError.malformedResponse)
        )
        let keychain = TestKeychainService(value: "api-key")
        let store = TestLLMSettingsStore()

        let appState = makeTestAppState(
            llmPostProcessor: fakeLLM,
            llmSettingsStore: store,
            keychainService: keychain
        )
        appState.llmEnabled = true
        appState.refreshLLMKeyStatus()

        await appState.testMagicFormatSetup(apiKeyDraft: "")

        XCTAssertEqual(
            appState.magicFormatSetupTestResult,
            MagicFormatSetupTestResult(message: "The service responded, but not in a compatible format.", severity: .error)
        )
    }
}

/// Keychain double with independently controllable failures for set, get, and delete.
private final class FailingKeychainService: KeychainServiceProtocol {
    var storedKey: String?
    var setError: Error?
    var getError: Error?
    var deleteError: Error?

    func setLLMKey(_ key: String) throws {
        if let setError {
            throw setError
        }
        storedKey = key
    }

    func hasLLMKey() -> Bool {
        storedKey?.isEmpty == false
    }

    func getLLMKey() throws -> String? {
        if let getError {
            throw getError
        }
        return storedKey
    }

    func deleteLLMKey() throws {
        if let deleteError {
            throw deleteError
        }
        storedKey = nil
    }
}
