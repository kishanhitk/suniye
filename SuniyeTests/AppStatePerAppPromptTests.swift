import XCTest
@testable import Suniye

@MainActor
final class AppStatePerAppPromptTests: XCTestCase {
    private let slackBundleID = "com.tinyspeck.slackmacgap"

    func testAddAppPromptBindingAppendsAndPersists() {
        let store = TestLLMSettingsStore()
        let appState = makeTestAppState(llmSettingsStore: store)

        appState.addAppPromptBinding(bundleID: slackBundleID, appDisplayName: "Slack", prompt: "Keep it terse.")

        XCTAssertEqual(appState.llmAppPromptBindings.count, 1)
        XCTAssertEqual(appState.llmAppPromptBindings.first?.bundleID, slackBundleID)
        XCTAssertEqual(appState.llmAppPromptBindings.first?.prompt, "Keep it terse.")
        XCTAssertEqual(store.latest.appPromptBindings, appState.llmAppPromptBindings)
    }

    func testAddAppPromptBindingSeedsPromptFromActiveProvider() {
        let appState = makeTestAppState()
        appState.llmProvider = .openAICompatible

        appState.addAppPromptBinding(bundleID: slackBundleID, appDisplayName: "Slack")

        XCTAssertEqual(appState.llmAppPromptBindings.first?.prompt, appState.llmBaseSystemPrompt)
    }

    func testAddDuplicateBundleIDUpdatesExistingBinding() {
        let appState = makeTestAppState()
        appState.addAppPromptBinding(bundleID: slackBundleID, appDisplayName: "Slack", prompt: "first")

        appState.addAppPromptBinding(bundleID: " COM.TINYSPECK.SLACKMACGAP ", appDisplayName: "Slack Beta", prompt: "second")

        XCTAssertEqual(appState.llmAppPromptBindings.count, 1)
        XCTAssertEqual(appState.llmAppPromptBindings.first?.appDisplayName, "Slack Beta")
        XCTAssertEqual(appState.llmAppPromptBindings.first?.prompt, "second")
    }

    func testAddAppPromptBindingIgnoresEmptyBundleID() {
        let appState = makeTestAppState()

        appState.addAppPromptBinding(bundleID: "  ", appDisplayName: "Mystery", prompt: "x")

        XCTAssertTrue(appState.llmAppPromptBindings.isEmpty)
    }

    func testUpdateAndRemoveAppPromptBinding() {
        let store = TestLLMSettingsStore()
        let appState = makeTestAppState(llmSettingsStore: store)
        appState.addAppPromptBinding(bundleID: slackBundleID, appDisplayName: "Slack", prompt: "old")
        let id = appState.llmAppPromptBindings[0].id

        appState.updateAppPromptBinding(id: id, prompt: "new")
        XCTAssertEqual(appState.llmAppPromptBindings.first?.prompt, "new")

        appState.removeAppPromptBinding(id: id)
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
        let keychain = TestKeychainService(value: "api-key")
        let appState = makeTestAppState(
            llmPostProcessor: capturingLLM,
            keychainService: keychain
        )
        appState.llmEnabled = true
        appState.llmProvider = .openAICompatible
        appState.refreshLLMKeyStatus()
        appState.addAppPromptBinding(bundleID: slackBundleID, appDisplayName: "Slack", prompt: "Keep it terse.")

        let output = await appState.postProcessTextIfEnabled("raw text", frontmostAppBundleID: slackBundleID)

        XCTAssertEqual(output, "polished")
        XCTAssertEqual(capturingLLM.lastConfig?.systemPrompt, "Keep it terse.")
    }

    func testPostProcessingUsesDefaultPromptForUnboundApp() async {
        let capturingLLM = CapturingLLMPostProcessor(result: .success("polished"))
        let keychain = TestKeychainService(value: "api-key")
        let appState = makeTestAppState(
            llmPostProcessor: capturingLLM,
            keychainService: keychain
        )
        appState.llmEnabled = true
        appState.llmProvider = .openAICompatible
        appState.refreshLLMKeyStatus()
        appState.addAppPromptBinding(bundleID: slackBundleID, appDisplayName: "Slack", prompt: "Keep it terse.")

        _ = await appState.postProcessTextIfEnabled("raw text", frontmostAppBundleID: "com.apple.mail")

        XCTAssertEqual(capturingLLM.lastConfig?.systemPrompt, LLMDefaults.defaultBaseSystemPrompt)
    }

    func testPostProcessingUsesDefaultPromptWhenNoAppCaptured() async {
        let capturingLLM = CapturingLLMPostProcessor(result: .success("polished"))
        let keychain = TestKeychainService(value: "api-key")
        let appState = makeTestAppState(
            llmPostProcessor: capturingLLM,
            keychainService: keychain
        )
        appState.llmEnabled = true
        appState.llmProvider = .openAICompatible
        appState.refreshLLMKeyStatus()
        appState.addAppPromptBinding(bundleID: slackBundleID, appDisplayName: "Slack", prompt: "Keep it terse.")

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
        appState.addAppPromptBinding(bundleID: slackBundleID, appDisplayName: "Slack", prompt: "Keep it terse.")

        let output = await appState.postProcessTextIfEnabled("raw text", frontmostAppBundleID: slackBundleID)

        XCTAssertEqual(output, "apple polished")
        XCTAssertEqual(fakeApple.lastConfig?.systemPrompt, "Keep it terse.")
    }

    func testPostProcessingIgnoresBlankPerAppPrompt() async {
        let capturingLLM = CapturingLLMPostProcessor(result: .success("polished"))
        let keychain = TestKeychainService(value: "api-key")
        let appState = makeTestAppState(
            llmPostProcessor: capturingLLM,
            keychainService: keychain
        )
        appState.llmEnabled = true
        appState.llmProvider = .openAICompatible
        appState.refreshLLMKeyStatus()
        appState.addAppPromptBinding(bundleID: slackBundleID, appDisplayName: "Slack", prompt: "   \n ")

        _ = await appState.postProcessTextIfEnabled("raw text", frontmostAppBundleID: slackBundleID)

        XCTAssertEqual(capturingLLM.lastConfig?.systemPrompt, LLMDefaults.defaultBaseSystemPrompt)
    }
}
