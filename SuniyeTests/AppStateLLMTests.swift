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

    func testAutomaticProviderUsesAppleWhenAvailable() async {
        let fakeLLM = FakeLLMPostProcessor(result: .success("api polished"))
        let fakeApple = CapturingAppleMagicFormatPostProcessor(
            availability: .available,
            result: .success("apple polished")
        )
        let keychain = TestKeychainService(value: nil)
        let store = TestLLMSettingsStore()

        let appState = makeTestAppState(
            llmPostProcessor: fakeLLM,
            appleMagicFormatPostProcessor: fakeApple,
            llmSettingsStore: store,
            keychainService: keychain
        )
        appState.llmEnabled = true
        appState.llmProvider = .automatic
        appState.refreshLLMKeyStatus()

        let output = await appState.postProcessTextIfEnabled("raw text")

        XCTAssertEqual(output, "apple polished")
        XCTAssertEqual(fakeApple.callCount, 1)
        XCTAssertEqual(fakeLLM.callCount, 0)
    }

    func testAutomaticProviderFallsBackToAPIWhenAppleUnavailable() async {
        let fakeLLM = FakeLLMPostProcessor(result: .success("api polished"))
        let fakeApple = CapturingAppleMagicFormatPostProcessor(
            availability: .modelNotReady,
            result: .success("apple polished")
        )
        let keychain = TestKeychainService(value: "api-key")
        let store = TestLLMSettingsStore()

        let appState = makeTestAppState(
            llmPostProcessor: fakeLLM,
            appleMagicFormatPostProcessor: fakeApple,
            llmSettingsStore: store,
            keychainService: keychain
        )
        appState.llmEnabled = true
        appState.llmProvider = .automatic
        appState.refreshLLMKeyStatus()

        let output = await appState.postProcessTextIfEnabled("raw text")

        XCTAssertEqual(output, "api polished")
        XCTAssertEqual(fakeApple.callCount, 0)
        XCTAssertEqual(fakeLLM.callCount, 1)
    }

    func testAutomaticProviderUsesLocalGemmaWhenAppleUnavailableAndGemmaAvailable() async {
        let fakeLLM = FakeLLMPostProcessor(result: .success("api polished"))
        let fakeApple = CapturingAppleMagicFormatPostProcessor(
            availability: .modelNotReady,
            result: .success("apple polished")
        )
        let fakeGemma = CapturingLocalGemmaMagicFormatPostProcessor(
            availability: .available,
            result: .success("gemma polished")
        )
        let keychain = TestKeychainService(value: nil)
        let store = TestLLMSettingsStore()

        let appState = makeTestAppState(
            llmPostProcessor: fakeLLM,
            appleMagicFormatPostProcessor: fakeApple,
            localGemmaMagicFormatPostProcessor: fakeGemma,
            llmSettingsStore: store,
            keychainService: keychain
        )
        appState.llmEnabled = true
        appState.llmProvider = .automatic
        appState.refreshLLMKeyStatus()

        let output = await appState.postProcessTextIfEnabled("raw text")

        XCTAssertEqual(output, "gemma polished")
        XCTAssertEqual(fakeGemma.callCount, 1)
        XCTAssertEqual(fakeApple.callCount, 0)
        XCTAssertEqual(fakeLLM.callCount, 0)
        XCTAssertFalse(appState.needsAPIConfigurationForMagicFormat)
    }

    func testExplicitAppleProviderDoesNotRequireAPIKey() async {
        let fakeLLM = FakeLLMPostProcessor(result: .success("api polished"))
        let fakeApple = CapturingAppleMagicFormatPostProcessor(
            availability: .available,
            result: .success("apple polished")
        )
        let keychain = TestKeychainService(value: nil)
        let store = TestLLMSettingsStore()

        let appState = makeTestAppState(
            llmPostProcessor: fakeLLM,
            appleMagicFormatPostProcessor: fakeApple,
            llmSettingsStore: store,
            keychainService: keychain
        )
        appState.llmEnabled = true
        appState.llmProvider = .appleFoundationModels
        appState.refreshLLMKeyStatus()

        let output = await appState.postProcessTextIfEnabled("raw text")

        XCTAssertEqual(output, "apple polished")
        XCTAssertEqual(fakeApple.callCount, 1)
        XCTAssertEqual(fakeLLM.callCount, 0)
    }

    func testExplicitLocalGemmaProviderDoesNotRequireAPIKey() async {
        let fakeLLM = FakeLLMPostProcessor(result: .success("api polished"))
        let fakeGemma = CapturingLocalGemmaMagicFormatPostProcessor(
            availability: .available,
            result: .success("gemma polished")
        )
        let keychain = TestKeychainService(value: nil)
        let store = TestLLMSettingsStore()

        let appState = makeTestAppState(
            llmPostProcessor: fakeLLM,
            localGemmaMagicFormatPostProcessor: fakeGemma,
            llmSettingsStore: store,
            keychainService: keychain
        )
        appState.llmEnabled = true
        appState.llmProvider = .localGemma
        appState.refreshLLMKeyStatus()

        let output = await appState.postProcessTextIfEnabled("raw text")

        XCTAssertEqual(output, "gemma polished")
        XCTAssertEqual(fakeGemma.callCount, 1)
        XCTAssertEqual(fakeLLM.callCount, 0)
        XCTAssertEqual(appState.magicFormatSetupState, .ready)
    }

    func testExplicitLocalGemmaProviderUnavailableFallsBackToRaw() async {
        let fakeGemma = CapturingLocalGemmaMagicFormatPostProcessor(
            availability: .modelNotInstalled,
            result: .success("gemma polished")
        )
        let store = TestLLMSettingsStore()

        let appState = makeTestAppState(
            localGemmaMagicFormatPostProcessor: fakeGemma,
            llmSettingsStore: store
        )
        appState.llmEnabled = true
        appState.llmProvider = .localGemma

        let output = await appState.postProcessTextIfEnabled("raw text")

        XCTAssertEqual(output, "raw text")
        XCTAssertEqual(fakeGemma.callCount, 0)
        XCTAssertEqual(appState.magicFormatSetupState, .needsServiceSetup)
    }

    func testExplicitAPIProviderStillRequiresAPIKey() async {
        let fakeLLM = FakeLLMPostProcessor(result: .success("api polished"))
        let fakeApple = CapturingAppleMagicFormatPostProcessor(
            availability: .available,
            result: .success("apple polished")
        )
        let keychain = TestKeychainService(value: nil)
        let store = TestLLMSettingsStore()

        let appState = makeTestAppState(
            llmPostProcessor: fakeLLM,
            appleMagicFormatPostProcessor: fakeApple,
            llmSettingsStore: store,
            keychainService: keychain
        )
        appState.llmEnabled = true
        appState.llmProvider = .openAICompatible
        appState.refreshLLMKeyStatus()

        let output = await appState.postProcessTextIfEnabled("raw text")

        XCTAssertEqual(output, "raw text")
        XCTAssertEqual(fakeApple.callCount, 0)
        XCTAssertEqual(fakeLLM.callCount, 0)
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

    func testAppleProviderFailureFallsBackToRaw() async {
        let fakeLLM = FakeLLMPostProcessor(result: .success("api polished"))
        let fakeApple = CapturingAppleMagicFormatPostProcessor(
            availability: .available,
            result: .failure(LLMPostProcessorError.malformedResponse)
        )
        let keychain = TestKeychainService(value: "api-key")
        let store = TestLLMSettingsStore()

        let appState = makeTestAppState(
            llmPostProcessor: fakeLLM,
            appleMagicFormatPostProcessor: fakeApple,
            llmSettingsStore: store,
            keychainService: keychain
        )
        appState.llmEnabled = true
        appState.llmProvider = .appleFoundationModels
        appState.refreshLLMKeyStatus()

        let output = await appState.postProcessTextIfEnabled("raw text")

        XCTAssertEqual(output, "raw text")
        XCTAssertEqual(fakeApple.callCount, 1)
        XCTAssertEqual(fakeLLM.callCount, 0)
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
        XCTAssertEqual(appState.llmEndpointValidationError, "Enter a valid service URL.")
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
        XCTAssertEqual(appState.llmModelValidationError, "Enter a valid custom model name.")
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

        XCTAssertEqual(appState.llmKeyStatusText, "Not connected")
        XCTAssertEqual(
            appState.magicFormatSetupTestResult,
            MagicFormatSetupTestResult(message: "Connection works.", severity: .success)
        )
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

    func testMagicFormatSlowWarningUpdatesProcessingPill() async {
        let fakeApple = BlockingAppleMagicFormatPostProcessor()
        let store = TestLLMSettingsStore()
        let appState = makeTestAppState(
            appleMagicFormatPostProcessor: fakeApple,
            llmSettingsStore: store,
            magicFormatSlowWarningDelaySeconds: 0.05
        )
        appState.llmEnabled = true
        appState.llmProvider = .appleFoundationModels
        appState.floatingIndicatorState = .processing()

        let task = Task {
            await appState.postProcessTextIfEnabled("raw text")
        }

        await fakeApple.waitUntilStarted()
        try? await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertEqual(
            appState.floatingIndicatorState,
            .processing(message: "Magic Format is taking longer than usual.")
        )

        fakeApple.resume(output: "polished")
        let output = await task.value
        XCTAssertEqual(output, "polished")
    }

    func testMagicFormatSlowWarningCancelsOnFastSuccess() async {
        let fakeApple = CapturingAppleMagicFormatPostProcessor(
            availability: .available,
            result: .success("polished")
        )
        let store = TestLLMSettingsStore()
        let appState = makeTestAppState(
            appleMagicFormatPostProcessor: fakeApple,
            llmSettingsStore: store,
            magicFormatSlowWarningDelaySeconds: 0.05
        )
        appState.llmEnabled = true
        appState.llmProvider = .appleFoundationModels
        appState.floatingIndicatorState = .processing()

        let output = await appState.postProcessTextIfEnabled("raw text")
        try? await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertEqual(output, "polished")
        XCTAssertEqual(appState.floatingIndicatorState, .processing())
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
        XCTAssertEqual(
            appState.magicFormatSetupTestResult,
            MagicFormatSetupTestResult(message: "Connection works.", severity: .success)
        )
        XCTAssertEqual(appState.llmKeyStatusText, "Connected")
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

    func testHiddenLLMAdvancedSettingsPersistAsDefaults() {
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
        appState.llmSystemPrompt = "old hidden prompt"

        XCTAssertEqual(appState.llmTimeoutSeconds, LLMDefaults.maxTimeoutSeconds)
        XCTAssertEqual(appState.llmMaxTokens, LLMDefaults.maxMaxTokens)
        XCTAssertEqual(store.latest.timeoutSeconds, LLMDefaults.defaultTimeoutSeconds)
        XCTAssertEqual(store.latest.maxTokens, LLMDefaults.defaultMaxTokens)
        XCTAssertEqual(store.latest.systemPrompt, "")
    }

    func testLoadMergesLegacyHiddenPromptAndClearsHiddenSettings() {
        let fakeLLM = FakeLLMPostProcessor(result: .success("polished"))
        let keychain = TestKeychainService(value: "api-key")
        let store = TestLLMSettingsStore()
        store.save(
            LLMSettings(
                isEnabled: true,
                selectedModelPreset: .gpt41Mini,
                customModelId: "",
                endpointURLString: LLMDefaults.defaultEndpointURLString,
                baseSystemPrompt: "BASE",
                systemPrompt: "USER",
                keywordsRaw: "",
                timeoutSeconds: 9,
                maxTokens: 256
            )
        )

        let appState = makeTestAppState(
            llmPostProcessor: fakeLLM,
            llmSettingsStore: store,
            keychainService: keychain
        )

        XCTAssertEqual(appState.llmBaseSystemPrompt, "BASE\n\nUSER")
        XCTAssertEqual(appState.llmSystemPrompt, "")
        XCTAssertEqual(store.latest.systemPrompt, "")
        XCTAssertEqual(store.latest.timeoutSeconds, LLMDefaults.defaultTimeoutSeconds)
        XCTAssertEqual(store.latest.maxTokens, LLMDefaults.defaultMaxTokens)
    }

    func testLoadPreservesLegacyHiddenPromptWhenItMatchesOnlySubstringOfBasePrompt() {
        let fakeLLM = FakeLLMPostProcessor(result: .success("polished"))
        let keychain = TestKeychainService(value: "api-key")
        let store = TestLLMSettingsStore()
        store.save(
            LLMSettings(
                isEnabled: true,
                selectedModelPreset: .gpt41Mini,
                customModelId: "",
                endpointURLString: LLMDefaults.defaultEndpointURLString,
                baseSystemPrompt: "Preserve meaning and intent.",
                systemPrompt: "Preserve meaning",
                keywordsRaw: "",
                timeoutSeconds: 9,
                maxTokens: 256
            )
        )

        let appState = makeTestAppState(
            llmPostProcessor: fakeLLM,
            llmSettingsStore: store,
            keychainService: keychain
        )

        XCTAssertEqual(
            appState.llmBaseSystemPrompt,
            "Preserve meaning and intent.\n\nPreserve meaning"
        )
        XCTAssertEqual(appState.llmSystemPrompt, "")
        XCTAssertEqual(store.latest.systemPrompt, "")
    }

    func testLoadDoesNotDuplicateLegacyHiddenPromptWhenAlreadyMergedIntoBasePrompt() {
        let fakeLLM = FakeLLMPostProcessor(result: .success("polished"))
        let keychain = TestKeychainService(value: "api-key")
        let store = TestLLMSettingsStore()
        store.save(
            LLMSettings(
                isEnabled: true,
                selectedModelPreset: .gpt41Mini,
                customModelId: "",
                endpointURLString: LLMDefaults.defaultEndpointURLString,
                baseSystemPrompt: "BASE\n\nUSER",
                systemPrompt: "USER",
                keywordsRaw: "",
                timeoutSeconds: 9,
                maxTokens: 256
            )
        )

        let appState = makeTestAppState(
            llmPostProcessor: fakeLLM,
            llmSettingsStore: store,
            keychainService: keychain
        )

        XCTAssertEqual(appState.llmBaseSystemPrompt, "BASE\n\nUSER")
        XCTAssertEqual(appState.llmSystemPrompt, "")
        XCTAssertEqual(store.latest.systemPrompt, "")
    }
}

private final class FakeLLMPostProcessor: LLMPostProcessor {
    private let result: Result<String, Error>
    private let testSetupResult: Result<Void, Error>
    private(set) var callCount = 0
    private(set) var setupTestCallCount = 0

    init(result: Result<String, Error>, testSetupResult: Result<Void, Error> = .success(())) {
        self.result = result
        self.testSetupResult = testSetupResult
    }

    func polish(text: String, config: LLMConfig) async throws -> String {
        callCount += 1
        return try result.get()
    }

    func testSetup(config: LLMConfig) async throws {
        setupTestCallCount += 1
        try testSetupResult.get()
    }
}

private final class CapturingLLMPostProcessor: LLMPostProcessor {
    private let result: Result<String, Error>
    private(set) var lastConfig: LLMConfig?
    private(set) var lastTestConfig: LLMConfig?

    init(result: Result<String, Error>) {
        self.result = result
    }

    func polish(text: String, config: LLMConfig) async throws -> String {
        lastConfig = config
        return try result.get()
    }

    func testSetup(config: LLMConfig) async throws {
        lastTestConfig = config
    }
}

private final class CapturingAppleMagicFormatPostProcessor: AppleMagicFormatPostProcessor {
    var availability: AppleFoundationModelsAvailability
    private let result: Result<String, Error>
    private(set) var callCount = 0
    private(set) var lastConfig: AppleMagicFormatConfig?

    init(availability: AppleFoundationModelsAvailability, result: Result<String, Error>) {
        self.availability = availability
        self.result = result
    }

    func polish(text: String, config: AppleMagicFormatConfig) async throws -> String {
        callCount += 1
        lastConfig = config
        return try result.get()
    }

    func testSetup(config: AppleMagicFormatConfig) async throws {
        lastConfig = config
    }
}

private final class CapturingLocalGemmaMagicFormatPostProcessor: LocalGemmaMagicFormatPostProcessor {
    var availability: LocalGemmaAvailability
    private let result: Result<String, Error>
    private(set) var callCount = 0
    private(set) var lastConfig: LocalGemmaMagicFormatConfig?

    init(availability: LocalGemmaAvailability, result: Result<String, Error>) {
        self.availability = availability
        self.result = result
    }

    func polish(text: String, config: LocalGemmaMagicFormatConfig) async throws -> String {
        callCount += 1
        lastConfig = config
        return try result.get()
    }

    func testSetup(config: LocalGemmaMagicFormatConfig) async throws {
        lastConfig = config
    }
}

private final class BlockingAppleMagicFormatPostProcessor: AppleMagicFormatPostProcessor {
    var availability: AppleFoundationModelsAvailability = .available
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var resumeContinuation: CheckedContinuation<String, Never>?
    private(set) var callCount = 0

    func polish(text: String, config: AppleMagicFormatConfig) async throws -> String {
        callCount += 1
        startedContinuation?.resume()
        startedContinuation = nil
        return await withCheckedContinuation { continuation in
            resumeContinuation = continuation
        }
    }

    func testSetup(config: AppleMagicFormatConfig) async throws {}

    func waitUntilStarted() async {
        if callCount > 0 {
            return
        }
        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func resume(output: String) {
        resumeContinuation?.resume(returning: output)
        resumeContinuation = nil
    }
}

private final class BlockingLLMPostProcessor: LLMPostProcessor {
    private var continuation: CheckedContinuation<Void, Never>?
    private var startContinuation: CheckedContinuation<Void, Never>?
    var testSetupResult: Result<Void, Error> = .success(())

    func polish(text: String, config: LLMConfig) async throws -> String {
        text
    }

    func testSetup(config: LLMConfig) async throws {
        startContinuation?.resume()
        startContinuation = nil
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        try testSetupResult.get()
    }

    func waitUntilStarted() async {
        if continuation != nil {
            return
        }
        await withCheckedContinuation { continuation in
            startContinuation = continuation
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
