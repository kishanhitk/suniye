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
        let localManager = StubLocalLLMModelManager()
        localManager.installedModelIDs.insert(.gemma4E2BQ4KM)
        let keychain = TestKeychainService(value: nil)
        let store = TestLLMSettingsStore()

        let appState = makeTestAppState(
            llmPostProcessor: fakeLLM,
            appleMagicFormatPostProcessor: fakeApple,
            localGemmaMagicFormatPostProcessor: fakeGemma,
            localLLMModelManager: localManager,
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
        let localManager = StubLocalLLMModelManager()
        localManager.installedModelIDs.insert(.gemma4E2BQ4KM)
        let keychain = TestKeychainService(value: nil)
        let store = TestLLMSettingsStore()

        let appState = makeTestAppState(
            llmPostProcessor: fakeLLM,
            localGemmaMagicFormatPostProcessor: fakeGemma,
            localLLMModelManager: localManager,
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

    func testLocalGemmaNotInstalledShowsDownloadState() {
        let localManager = StubLocalLLMModelManager()
        let appState = makeTestAppState(localLLMModelManager: localManager)

        appState.llmEnabled = true
        appState.llmProvider = .localGemma

        XCTAssertEqual(appState.localGemmaInstallState, .notInstalled)
        XCTAssertTrue(appState.canStartLocalGemmaDownload)
        XCTAssertEqual(appState.localGemmaMagicFormatAvailability, .modelNotInstalled)
        XCTAssertEqual(appState.magicFormatSetupState, .needsServiceSetup)
    }

    func testLocalGemmaDownloadUpdatesInstallState() async {
        let localManager = StubLocalLLMModelManager()
        let appState = makeTestAppState(localLLMModelManager: localManager)
        let downloadFinished = expectation(description: "local Gemma download finished")
        localManager.onDownloadFinished = {
            downloadFinished.fulfill()
        }

        appState.llmEnabled = true
        appState.llmProvider = .localGemma
        appState.startLocalGemmaDownload()
        await fulfillment(of: [downloadFinished], timeout: 1)
        await waitUntil(timeoutSeconds: 1) {
            appState.localGemmaInstallState.isInstalled
        }

        XCTAssertEqual(localManager.downloadCallCount, 1)
        XCTAssertTrue(appState.localGemmaInstallState.isInstalled)
        XCTAssertFalse(appState.canStartLocalGemmaDownload)
    }

    func testLocalGemmaCancelForwardsToManager() {
        let localManager = StubLocalLLMModelManager()
        let appState = makeTestAppState(localLLMModelManager: localManager)
        appState.localGemmaInstallState = .downloading(LocalLLMDownloadProgress(
            fractionCompleted: 0.25,
            downloadedBytes: 25,
            expectedBytes: 100
        ))

        appState.cancelLocalGemmaDownload()

        XCTAssertEqual(localManager.cancelCallCount, 1)
    }

    func testLocalGemmaDeleteModelUpdatesInstallState() async {
        let localManager = StubLocalLLMModelManager()
        localManager.installedModelIDs.insert(.gemma4E2BQ4KM)
        let fakeGemma = CapturingLocalGemmaMagicFormatPostProcessor(
            availability: .available,
            result: .success("gemma polished")
        )
        let appState = makeTestAppState(
            localGemmaMagicFormatPostProcessor: fakeGemma,
            localLLMModelManager: localManager
        )

        XCTAssertTrue(appState.localGemmaInstallState.isInstalled)

        await appState.deleteLocalGemmaModel()

        XCTAssertEqual(fakeGemma.stopRuntimeCallCount, 1)
        XCTAssertEqual(localManager.deleteCallCount, 1)
        XCTAssertEqual(appState.localGemmaInstallState, .notInstalled)
    }

    func testLocalGemmaUnsupportedHardwareIsDisabled() {
        let localManager = StubLocalLLMModelManager()
        localManager.isHardwareSupported = false
        let appState = makeTestAppState(localLLMModelManager: localManager)

        XCTAssertFalse(appState.isLocalGemmaProviderSelectable)
        XCTAssertEqual(appState.localGemmaInstallState, .unavailable("Requires Apple Silicon."))
        XCTAssertEqual(appState.localGemmaMagicFormatAvailability, .unsupportedHardware)
    }

    func testMagicFormatProviderPresenterKeepsAutomaticSelectable() {
        let appState = makeTestAppState()
        appState.llmProvider = .automatic

        let presenter = MagicFormatProviderPresenter(appState: appState)

        XCTAssertEqual(presenter.providerOptions, [
            .localGemma,
            .appleFoundationModels,
            .automatic,
            .openAICompatible
        ])
        XCTAssertEqual(presenter.displayedProviderSelection, .automatic)
        XCTAssertTrue(presenter.isSelectable(.automatic))
    }

    func testLocalGemmaSetupTestDoesNotRequireAPIKey() async {
        let fakeGemma = CapturingLocalGemmaMagicFormatPostProcessor(
            availability: .available,
            result: .success("gemma polished")
        )
        let localManager = StubLocalLLMModelManager()
        localManager.installedModelIDs.insert(.gemma4E2BQ4KM)
        let appState = makeTestAppState(
            localGemmaMagicFormatPostProcessor: fakeGemma,
            localLLMModelManager: localManager,
            keychainService: TestKeychainService(value: nil)
        )

        appState.llmEnabled = true
        appState.llmProvider = .localGemma
        await appState.testLocalGemmaSetup()

        XCTAssertNotNil(fakeGemma.lastConfig)
        XCTAssertEqual(appState.magicFormatSetupTestResult, MagicFormatSetupTestResult(message: "Local model works.", severity: .success))
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

    func testLoadMigratesLegacyCustomPromptIntoMissingProviderPrompts() throws {
        let data = """
        {
          "isEnabled": true,
          "provider": "automatic",
          "selectedModelPreset": "gpt41Mini",
          "customModelId": "",
          "endpointURLString": "\(LLMDefaults.defaultEndpointURLString)",
          "baseSystemPrompt": "BASE",
          "systemPrompt": "USER",
          "keywordsRaw": "",
          "timeoutSeconds": 9,
          "maxTokens": 256
        }
        """.data(using: .utf8)!
        let settings = try JSONDecoder().decode(LLMSettings.self, from: data)
        let fakeLLM = FakeLLMPostProcessor(result: .success("polished"))
        let keychain = TestKeychainService(value: "api-key")
        let store = TestLLMSettingsStore()
        store.save(settings)

        let appState = makeTestAppState(
            llmPostProcessor: fakeLLM,
            llmSettingsStore: store,
            keychainService: keychain
        )

        XCTAssertEqual(appState.llmBaseSystemPrompt, "BASE\n\nUSER")
        XCTAssertEqual(appState.llmAppleSystemPrompt, "BASE\n\nUSER")
        XCTAssertEqual(appState.llmGemmaSystemPrompt, "BASE\n\nUSER")
        XCTAssertEqual(store.latest.appleSystemPrompt, "BASE\n\nUSER")
        XCTAssertEqual(store.latest.gemmaSystemPrompt, "BASE\n\nUSER")
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

    private func waitUntil(
        timeoutSeconds: TimeInterval,
        condition: @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(condition(), file: file, line: line)
    }
}
