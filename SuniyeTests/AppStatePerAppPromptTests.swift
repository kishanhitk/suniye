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

    func testAddAppPromptBindingAppendsSeedsFromActiveProviderAndPersists() {
        let store = TestLLMSettingsStore()
        let appState = makeTestAppState(llmSettingsStore: store)
        appState.llmProvider = .openAICompatible

        let binding = appState.addAppPromptBinding(bundleID: slackBundleID, appDisplayName: "Slack")

        XCTAssertEqual(appState.llmAppPromptBindings.count, 1)
        XCTAssertEqual(binding?.bundleID, slackBundleID)
        XCTAssertEqual(binding?.prompt, appState.llmBaseSystemPrompt)
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

    func testPostProcessingUsesPerAppPromptForBoundApp() async {
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
        XCTAssertEqual(capturingLLM.lastConfig?.systemPrompt, "Keep it terse.")
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

    func testPostProcessingAppliesPerAppPromptToAppleProvider() async {
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
        XCTAssertEqual(fakeApple.lastConfig?.systemPrompt, "Keep it terse.")
    }

    func testPostProcessingAppliesPerAppPromptToLocalGemmaProvider() async {
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
        XCTAssertEqual(fakeGemma.lastConfig?.systemPrompt, "Keep it terse.")
    }

    /// With no matching binding, the local model must receive the shipped default
    /// prompt untouched (guards the referential-edit prompt against override leaks).
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

        XCTAssertEqual(capturingLLM.lastConfig?.systemPrompt, "Keep it terse.")
        XCTAssertEqual(insertion.insertedTexts, ["polished"])
        XCTAssertEqual(appState.phase, .ready)
    }
}
