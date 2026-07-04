import XCTest
@testable import Suniye

@MainActor
final class AppStatePerAppPromptTests: XCTestCase {
    private let slackBundleID = "com.tinyspeck.slackmacgap"

    private func addSlackBinding(to appState: AppState, prompt: String) {
        let binding = appState.addAppPromptBinding(bundleID: slackBundleID, appDisplayName: "Slack")
        XCTAssertNotNil(binding)
        if let binding {
            appState.updateAppPromptBinding(id: binding.id, prompt: prompt)
        }
    }

    private func appendedPrompt(base: String, instructions: String = "Keep it terse.") -> String {
        "\(base)\n\nApp-specific instructions:\n\(instructions)"
    }

    func testAddAppPromptBindingStartsBlankAndPersists() {
        let store = TestLLMSettingsStore()
        let appState = makeTestAppState(llmSettingsStore: store)
        appState.llmProvider = .openAICompatible

        let binding = appState.addAppPromptBinding(bundleID: slackBundleID, appDisplayName: "Slack")

        XCTAssertEqual(appState.llmAppPromptBindings.count, 1)
        XCTAssertEqual(binding?.bundleID, slackBundleID)
        XCTAssertEqual(binding?.prompt, "")
        XCTAssertEqual(store.latest.appPromptBindings, appState.llmAppPromptBindings)
    }

    func testAddDuplicateBundleIDReturnsExistingBindingAndPreservesPrompt() {
        let appState = makeTestAppState()
        addSlackBinding(to: appState, prompt: "Keep it terse.")
        let originalID = appState.llmAppPromptBindings[0].id

        let duplicate = appState.addAppPromptBinding(bundleID: " COM.TINYSPECK.SLACKMACGAP ", appDisplayName: "Slack Beta")

        XCTAssertEqual(appState.llmAppPromptBindings.count, 1)
        XCTAssertEqual(duplicate?.id, originalID)
        XCTAssertEqual(appState.llmAppPromptBindings.first?.appDisplayName, "Slack Beta")
        XCTAssertEqual(appState.llmAppPromptBindings.first?.prompt, "Keep it terse.")
    }

    func testAddAppPromptBindingIgnoresEmptyBundleID() {
        let appState = makeTestAppState()

        XCTAssertNil(appState.addAppPromptBinding(bundleID: "  ", appDisplayName: "Mystery"))
        XCTAssertTrue(appState.llmAppPromptBindings.isEmpty)
    }

    func testUpdateAndRemoveAppPromptBinding() {
        let store = TestLLMSettingsStore()
        let appState = makeTestAppState(llmSettingsStore: store)
        guard let binding = appState.addAppPromptBinding(bundleID: slackBundleID, appDisplayName: "Slack") else {
            return XCTFail("binding not created")
        }

        appState.updateAppPromptBinding(id: binding.id, prompt: "new")
        XCTAssertEqual(appState.llmAppPromptBindings.first?.prompt, "new")

        appState.removeAppPromptBinding(id: binding.id)
        XCTAssertTrue(appState.llmAppPromptBindings.isEmpty)
        XCTAssertTrue(store.latest.appPromptBindings.isEmpty)
    }

    func testBindingsHydrateFromStore() {
        let store = TestLLMSettingsStore()
        var settings = LLMSettings()
        settings.appPromptBindings = [
            AppPromptBinding(bundleID: slackBundleID, appDisplayName: "Slack", prompt: "Keep it terse.")
        ]
        store.save(settings)

        let appState = makeTestAppState(llmSettingsStore: store)

        XCTAssertEqual(appState.llmAppPromptBindings, settings.appPromptBindings)
    }

    // MARK: - Post-processing integration

    func testPostProcessingAppendsPerAppPromptForBoundApp() async {
        let capturingLLM = CapturingLLMPostProcessor(result: .success("polished"))
        let appState = makeTestAppState(
            llmPostProcessor: capturingLLM,
            keychainService: TestKeychainService(value: "api-key")
        )
        appState.llmEnabled = true
        appState.llmProvider = .openAICompatible
        appState.refreshLLMKeyStatus()
        addSlackBinding(to: appState, prompt: "Keep it terse.")

        let output = await appState.postProcessTextIfEnabled("raw text", frontmostAppBundleID: slackBundleID)

        XCTAssertEqual(output, "polished")
        XCTAssertEqual(capturingLLM.lastConfig?.systemPrompt, appendedPrompt(base: LLMDefaults.defaultBaseSystemPrompt))
    }

    func testPostProcessingUsesFileBackedProviderAndPerAppPrompts() async throws {
        let capturingLLM = CapturingLLMPostProcessor(result: .success("polished"))
        let settingsStore = TestLLMSettingsStore()
        var settings = LLMSettings()
        settings.isEnabled = true
        settings.provider = .openAICompatible
        settings.baseSystemPrompt = "settings API prompt"
        settings.appPromptBindings = [
            AppPromptBinding(bundleID: slackBundleID, appDisplayName: "Slack", prompt: "settings Slack prompt")
        ]
        settingsStore.save(settings)

        let promptStoreBaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("suniye-appstate-prompt-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: promptStoreBaseURL) }
        let promptStore = MagicFormatPromptFileStore(promptsDirectoryURL: promptStoreBaseURL)
        try FileManager.default.createDirectory(at: promptStoreBaseURL, withIntermediateDirectories: true)
        try "file API prompt".write(to: promptStore.providerPromptURL(.api), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: promptStoreBaseURL.appendingPathComponent("apps", isDirectory: true), withIntermediateDirectories: true)
        try "file Slack prompt".write(to: promptStore.appPromptURL(bundleID: slackBundleID)!, atomically: true, encoding: .utf8)

        let appState = makeTestAppState(
            llmPostProcessor: capturingLLM,
            llmSettingsStore: settingsStore,
            magicFormatPromptFileStore: promptStore,
            keychainService: TestKeychainService(value: "api-key")
        )
        appState.refreshLLMKeyStatus()

        _ = await appState.postProcessTextIfEnabled("raw text", frontmostAppBundleID: slackBundleID)

        XCTAssertEqual(capturingLLM.lastConfig?.systemPrompt, appendedPrompt(base: "file API prompt", instructions: "file Slack prompt"))
        XCTAssertEqual(settingsStore.latest.baseSystemPrompt, "file API prompt")
        XCTAssertEqual(settingsStore.latest.appPromptBindings.first?.prompt, "file Slack prompt")
    }

    func testUnrelatedSettingsChangeDoesNotOverwriteExternallyEditedPromptFile() throws {
        let settingsStore = TestLLMSettingsStore()
        var settings = LLMSettings()
        settings.baseSystemPrompt = "settings API prompt"
        settingsStore.save(settings)

        let promptStoreBaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("suniye-appstate-prompt-clobber-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: promptStoreBaseURL) }
        let promptStore = MagicFormatPromptFileStore(promptsDirectoryURL: promptStoreBaseURL)
        let appState = makeTestAppState(
            llmSettingsStore: settingsStore,
            magicFormatPromptFileStore: promptStore
        )

        try "external API prompt".write(to: promptStore.providerPromptURL(.api), atomically: true, encoding: .utf8)
        appState.llmEnabled = true

        XCTAssertEqual(try String(contentsOf: promptStore.providerPromptURL(.api), encoding: .utf8), "external API prompt")
        XCTAssertEqual(settingsStore.latest.baseSystemPrompt, "settings API prompt")
    }

    func testPostProcessingUsesDefaultPromptForUnboundApp() async {
        let capturingLLM = CapturingLLMPostProcessor(result: .success("polished"))
        let appState = makeTestAppState(
            llmPostProcessor: capturingLLM,
            keychainService: TestKeychainService(value: "api-key")
        )
        appState.llmEnabled = true
        appState.llmProvider = .openAICompatible
        appState.refreshLLMKeyStatus()
        addSlackBinding(to: appState, prompt: "Keep it terse.")

        _ = await appState.postProcessTextIfEnabled("raw text", frontmostAppBundleID: "com.apple.mail")

        XCTAssertEqual(capturingLLM.lastConfig?.systemPrompt, LLMDefaults.defaultBaseSystemPrompt)
    }

    func testPostProcessingUsesDefaultPromptWhenNoAppCaptured() async {
        let capturingLLM = CapturingLLMPostProcessor(result: .success("polished"))
        let appState = makeTestAppState(
            llmPostProcessor: capturingLLM,
            keychainService: TestKeychainService(value: "api-key")
        )
        appState.llmEnabled = true
        appState.llmProvider = .openAICompatible
        appState.refreshLLMKeyStatus()
        addSlackBinding(to: appState, prompt: "Keep it terse.")

        _ = await appState.postProcessTextIfEnabled("raw text")

        XCTAssertEqual(capturingLLM.lastConfig?.systemPrompt, LLMDefaults.defaultBaseSystemPrompt)
    }

    func testPostProcessingAppendsPerAppPromptToAppleProvider() async {
        let fakeApple = CapturingAppleMagicFormatPostProcessor(
            availability: .available,
            result: .success("apple polished")
        )
        let appState = makeTestAppState(appleMagicFormatPostProcessor: fakeApple)
        appState.llmEnabled = true
        appState.llmProvider = .appleFoundationModels
        addSlackBinding(to: appState, prompt: "Keep it terse.")

        let output = await appState.postProcessTextIfEnabled("raw text", frontmostAppBundleID: slackBundleID)

        XCTAssertEqual(output, "apple polished")
        XCTAssertEqual(fakeApple.lastConfig?.systemPrompt, appendedPrompt(base: LLMDefaults.defaultAppleMagicFormatPrompt))
    }

    func testPostProcessingAppendsPerAppPromptToLocalGemmaProvider() async {
        let fakeGemma = CapturingLocalGemmaMagicFormatPostProcessor(
            availability: .available,
            result: .success("gemma polished")
        )
        let localManager = StubLocalLLMModelManager()
        localManager.installedModelIDs.insert(.gemma4E2BQ4KM)
        let appState = makeTestAppState(
            localGemmaMagicFormatPostProcessor: fakeGemma,
            localLLMModelManager: localManager
        )
        appState.llmEnabled = true
        appState.llmProvider = .localGemma
        addSlackBinding(to: appState, prompt: "Keep it terse.")

        let output = await appState.postProcessTextIfEnabled("raw text", frontmostAppBundleID: slackBundleID)

        XCTAssertEqual(output, "gemma polished")
        XCTAssertEqual(fakeGemma.lastConfig?.systemPrompt, appendedPrompt(base: LLMDefaults.defaultGemmaMagicFormatPrompt))
    }

    /// With no matching binding, the local model must receive the shipped default
    /// prompt untouched (guards the referential-edit prompt against per-app append leaks).
    func testPostProcessingUsesDefaultGemmaPromptForUnboundApp() async {
        let fakeGemma = CapturingLocalGemmaMagicFormatPostProcessor(
            availability: .available,
            result: .success("gemma polished")
        )
        let localManager = StubLocalLLMModelManager()
        localManager.installedModelIDs.insert(.gemma4E2BQ4KM)
        let appState = makeTestAppState(
            localGemmaMagicFormatPostProcessor: fakeGemma,
            localLLMModelManager: localManager
        )
        appState.llmEnabled = true
        appState.llmProvider = .localGemma
        addSlackBinding(to: appState, prompt: "Keep it terse.")

        _ = await appState.postProcessTextIfEnabled("raw text", frontmostAppBundleID: "com.apple.mail")

        XCTAssertEqual(fakeGemma.lastConfig?.systemPrompt, LLMDefaults.defaultGemmaMagicFormatPrompt)
    }

    func testPostProcessingIgnoresBlankPerAppPrompt() async {
        let capturingLLM = CapturingLLMPostProcessor(result: .success("polished"))
        let appState = makeTestAppState(
            llmPostProcessor: capturingLLM,
            keychainService: TestKeychainService(value: "api-key")
        )
        appState.llmEnabled = true
        appState.llmProvider = .openAICompatible
        appState.refreshLLMKeyStatus()
        addSlackBinding(to: appState, prompt: "   \n ")

        _ = await appState.postProcessTextIfEnabled("raw text", frontmostAppBundleID: slackBundleID)

        XCTAssertEqual(capturingLLM.lastConfig?.systemPrompt, LLMDefaults.defaultBaseSystemPrompt)
    }

    // MARK: - Full dictation pipeline

    func testDictationPipelineRoutesPerAppPromptFromCapturedFrontmostApp() async {
        let capturingLLM = CapturingLLMPostProcessor(result: .success("polished"))
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = makeValidCapturedAudio()
        let transcription = StubTranscriptionService()
        transcription.transcribeResult = .success("raw text")
        let insertion = SpyTextInsertionService()
        let started = expectation(description: "capture started")
        audioCapture.onStartCapture = { _ in started.fulfill() }
        let frontmostBundleID = slackBundleID

        let appState = makeTestAppState(
            transcriptionService: transcription,
            audioCaptureService: audioCapture,
            textInsertionService: insertion,
            llmPostProcessor: capturingLLM,
            keychainService: TestKeychainService(value: "api-key"),
            frontmostAppBundleIDProvider: { frontmostBundleID }
        )
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true
        appState.llmEnabled = true
        appState.llmProvider = .openAICompatible
        appState.refreshLLMKeyStatus()
        addSlackBinding(to: appState, prompt: "Keep it terse.")

        appState.startRecordingFromUI()
        await fulfillment(of: [started], timeout: 1)
        appState.stopRecordingFromUI()
        for _ in 0 ..< 500 where appState.phase != .ready {
            await Task.yield()
        }

        XCTAssertEqual(capturingLLM.lastConfig?.systemPrompt, appendedPrompt(base: LLMDefaults.defaultBaseSystemPrompt))
        XCTAssertEqual(insertion.insertedTexts, ["polished"])
        XCTAssertEqual(appState.phase, .ready)
    }
}
