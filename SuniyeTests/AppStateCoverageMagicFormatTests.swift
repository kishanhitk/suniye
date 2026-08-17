import XCTest
@testable import Suniye

/// Coverage tests for Magic Format API setup testing, API key persistence
/// error paths, prompt file plumbing, and post-processing entry points.
@MainActor
final class AppStateCoverageMagicFormatTests: XCTestCase {
    // MARK: - testMagicFormatSetup guards

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

    // MARK: - testMagicFormatSetup error mapping

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

    // MARK: - API key persistence

    func testSaveLLMAPIKeySuccessAndEmptyInput() {
        let keychain = CovKeychainService()
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
        let keychain = CovKeychainService()
        keychain.setError = FakeError(message: "keychain locked")
        let appState = makeTestAppState(keychainService: keychain)

        appState.saveLLMAPIKey("secret")

        XCTAssertEqual(appState.llmKeyOperationError, "Couldn't save the API key.")
        XCTAssertFalse(appState.hasLLMAPIKey)
    }

    func testClearLLMAPIKeySuccessAndFailure() {
        let keychain = CovKeychainService()
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
        let keychain = CovKeychainService()
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

    // MARK: - postProcessTextIfEnabled entry points

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

    // MARK: - Prompt management

    func testResetPromptFunctionsRestoreDefaults() {
        let appState = makeTestAppState()

        appState.llmAppleSystemPrompt = "custom apple"
        appState.llmGemmaSystemPrompt = "custom gemma"
        appState.llmBaseSystemPrompt = "custom base"

        appState.resetAppleMagicFormatPrompt()
        appState.resetGemmaMagicFormatPrompt()
        appState.resetBaseMagicFormatPrompt()

        XCTAssertEqual(appState.llmAppleSystemPrompt, LLMDefaults.defaultAppleMagicFormatPrompt)
        XCTAssertEqual(appState.llmGemmaSystemPrompt, LLMDefaults.defaultGemmaMagicFormatPrompt)
        XCTAssertEqual(appState.llmBaseSystemPrompt, LLMDefaults.defaultBaseSystemPrompt)
    }

    func testEditingBasePromptWritesProviderPromptFile() throws {
        let promptStore = MagicFormatPromptFileStore(
            promptsDirectoryURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("cov-prompt-write-\(UUID().uuidString)", isDirectory: true)
        )
        let appState = makeTestAppState(magicFormatPromptFileStore: promptStore)

        appState.llmBaseSystemPrompt = "rewritten base prompt"

        let content = try String(contentsOf: promptStore.providerPromptURL(.api), encoding: .utf8)
        XCTAssertEqual(content, "rewritten base prompt")
    }

    func testOpenCurrentMagicFormatPromptInEditorUsesFileOpener() {
        var openedURLs: [URL] = []
        let appState = makeTestAppState(fileOpener: { url in
            openedURLs.append(url)
            return true
        })

        appState.openCurrentMagicFormatPromptInEditor()

        XCTAssertEqual(openedURLs, [appState.currentMagicFormatPromptURL])
    }

    func testReloadMagicFormatPromptsFromFilesKeepsSettingsConsistent() {
        let settingsStore = TestLLMSettingsStore()
        let appState = makeTestAppState(llmSettingsStore: settingsStore)
        appState.llmBaseSystemPrompt = "persisted base"

        appState.reloadMagicFormatPromptsFromFiles()

        XCTAssertEqual(appState.llmBaseSystemPrompt, "persisted base")
        XCTAssertEqual(settingsStore.latest.baseSystemPrompt, "persisted base")
    }

    func testOpenAppPromptInEditorBranches() {
        var openedURLs: [URL] = []
        let appState = makeTestAppState(fileOpener: { url in
            openedURLs.append(url)
            return true
        })

        // Unknown binding id: nothing opens.
        appState.openAppPromptInEditor(id: UUID())
        XCTAssertTrue(openedURLs.isEmpty)

        let binding = appState.addAppPromptBinding(bundleID: "com.example.app", appDisplayName: "Example")
        appState.openAppPromptInEditor(id: binding!.id)
        XCTAssertEqual(openedURLs.count, 1)
        XCTAssertTrue(openedURLs[0].path.contains("com.example.app"))
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

    // MARK: - Vocabulary

    func testAddVocabularyTermIgnoresWhitespaceOnlyInput() {
        let appState = makeTestAppState()
        appState.llmKeywordsRaw = "existing"

        appState.addVocabularyTerm("   ")

        XCTAssertEqual(appState.llmKeywordsRaw, "existing")
    }

    // MARK: - Validation shortcuts for local providers

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

    func testModelIdPreviewAndDisplayModelId() {
        let appState = makeTestAppState()
        XCTAssertFalse(appState.llmSelectedModelIdPreview.isEmpty)
        XCTAssertFalse(appState.llmDisplayModelId(for: .gemini25Flash).isEmpty)
        XCTAssertEqual(appState.llmStatusHint, appState.magicFormatSetupState.detail)
    }
}

/// Keychain double with independently controllable failures for set, get, and delete.
final class CovKeychainService: KeychainServiceProtocol {
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
