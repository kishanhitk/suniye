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

    func testMagicFormatProviderPresenterHidesAutomaticAndDisplaysEffectiveProvider() {
        let appleAppState = makeTestAppState(
            appleMagicFormatPostProcessor: NoopAppleMagicFormatPostProcessor(availability: .available)
        )
        appleAppState.llmProvider = .automatic

        let localManager = StubLocalLLMModelManager()
        localManager.installedModelIDs.insert(.gemma4E2BQ4KM)
        let localAppState = makeTestAppState(
            localGemmaMagicFormatPostProcessor: NoopLocalGemmaMagicFormatPostProcessor(availability: .available),
            localLLMModelManager: localManager
        )
        localAppState.llmProvider = .automatic

        let apiAppState = makeTestAppState()
        apiAppState.llmProvider = .automatic

        let presenter = MagicFormatProviderPresenter(appState: appleAppState)

        XCTAssertEqual(presenter.providerOptions, [
            .localGemma,
            .appleFoundationModels,
            .openAICompatible
        ])
        XCTAssertFalse(presenter.providerOptions.contains(.automatic))
        XCTAssertFalse(presenter.isSelectable(.automatic))
        XCTAssertEqual(presenter.displayedProviderSelection, .appleFoundationModels)
        XCTAssertEqual(MagicFormatProviderPresenter(appState: localAppState).displayedProviderSelection, .localGemma)
        XCTAssertEqual(MagicFormatProviderPresenter(appState: apiAppState).displayedProviderSelection, .openAICompatible)
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

    func testHistoryKeepsTheTranscriptWhenMagicFormatChangesIt() async {
        let result = await dictate(transcript: "um so lets meet at five", polishedTo: "Let's meet at 5.")

        XCTAssertEqual(result?.text, "Let's meet at 5.")
        XCTAssertEqual(result?.rawText, "um so lets meet at five")
    }

    func testHistoryKeepsNoTranscriptWhenMagicFormatLeavesItUnchanged() async {
        let result = await dictate(transcript: "Let's meet at 5.", polishedTo: "Let's meet at 5.")

        XCTAssertEqual(result?.text, "Let's meet at 5.")
        XCTAssertNil(result?.rawText)
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
        // Fast success cancels the slow warning; the pill settles on the polishing
        // stage label (no "taking longer than usual" upgrade).
        XCTAssertEqual(appState.floatingIndicatorState, .processing(message: "Polishing..."))
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
                timeoutSeconds: 9
            )
        )

        let appState = makeTestAppState(
            llmPostProcessor: fakeLLM,
            llmSettingsStore: store,
            keychainService: keychain
        )

        XCTAssertEqual(appState.llmBaseSystemPrompt, "BASE\n\nUSER")
        XCTAssertEqual(store.latest.systemPrompt, "")
        XCTAssertEqual(store.latest.timeoutSeconds, LLMDefaults.defaultTimeoutSeconds)
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
                timeoutSeconds: 9
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
                timeoutSeconds: 9
            )
        )

        let appState = makeTestAppState(
            llmPostProcessor: fakeLLM,
            llmSettingsStore: store,
            keychainService: keychain
        )

        XCTAssertEqual(appState.llmBaseSystemPrompt, "BASE\n\nUSER")
        XCTAssertEqual(store.latest.systemPrompt, "")
    }

    /// One full dictation with Magic Format on: capture, transcribe, polish,
    /// insert. Returns the history entry it stored.
    private func dictate(transcript: String, polishedTo polished: String) async -> RecentResult? {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = makeValidCapturedAudio()
        let started = expectation(description: "capture started")
        audioCapture.onStartCapture = { _ in started.fulfill() }
        let transcription = StubTranscriptionService()
        transcription.transcribeResult = .success(transcript)
        let appState = makeTestAppState(
            transcriptionService: transcription,
            audioCaptureService: audioCapture,
            llmPostProcessor: FakeLLMPostProcessor(result: .success(polished)),
            keychainService: TestKeychainService(value: "api-key")
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        appState.llmEnabled = true
        appState.llmProvider = .openAICompatible
        appState.refreshLLMKeyStatus()

        appState.toggleFloatingIndicatorRecording()
        await fulfillment(of: [started], timeout: 1)
        appState.toggleFloatingIndicatorRecording()
        await waitUntil(timeout: 2) { !appState.recentResults.isEmpty && appState.phase == .ready }
        return appState.recentResults.first
    }
}
