import XCTest
@testable import Suniye

/// Magic Format through the API endpoint: the dictation, the request on the
/// wire, and the text that reaches the field.
@MainActor
final class MagicFormatFlowTests: XCTestCase {
    private static let endpoint = "https://openrouter.ai/api/v1/chat/completions"
    private static let slackBundleID = "com.tinyspeck.slackmacgap"

    private func launchWithAPIEndpoint() async throws -> FlowApp {
        var llm = LLMSettings()
        llm.isEnabled = true
        llm.provider = .openAICompatible
        let app = try FlowApp(self, llm: llm)
        await app.launch()
        await app.appState.saveLLMAPIKey("sk-or-v1-flow")
        return app
    }

    func testThePolishedTextIsTypedAndHistoryKeepsWhatWasSaid() async throws {
        let app = try await launchWithAPIEndpoint()
        app.appState.addVocabularyTerm("Suniye")
        let binding = try XCTUnwrap(app.appState.addAppPromptBinding(bundleID: Self.slackBundleID, appDisplayName: "Slack"))
        app.appState.updateAppPromptBinding(id: binding.id, prompt: "Keep it casual for chat.")
        app.frontmostBundleID = Self.slackBundleID
        let endpoint = ChatEndpoint(reply: "Hey, can we move standup to ten?")

        await app.dictate(saying: "hey um can we move standup to ten")

        let request = try XCTUnwrap(endpoint.requests.first)
        XCTAssertEqual(endpoint.requests.count, 1)
        XCTAssertEqual(request.url?.absoluteString, Self.endpoint)
        XCTAssertEqual(request.authorization, "Bearer sk-or-v1-flow")
        XCTAssertEqual(request.body["model"] as? String, LLMModelPreset.gemini25Flash.modelId)
        XCTAssertNil(request.body["max_tokens"], "no output cap: a long dictation must not be cut")
        let system = try XCTUnwrap(request.content(of: "system"))
        XCTAssertTrue(system.contains("Keep it casual for chat."), "the Slack prompt is sent")
        XCTAssertTrue(system.contains("Suniye"), "the vocabulary is sent")
        XCTAssertTrue(request.content(of: "user")?.contains("hey um can we move standup to ten") == true)

        XCTAssertEqual(app.focusedApp.text, "Hey, can we move standup to ten?")
        let saved = try XCTUnwrap(app.appState.recentResults.first)
        XCTAssertEqual(saved.text, "Hey, can we move standup to ten?")
        XCTAssertEqual(saved.rawText, "hey um can we move standup to ten")
        XCTAssertTrue(saved.wasLLMPolished)
    }

    func testAnAnswerCutShortTypesWhatWasSaid() async throws {
        let app = try await launchWithAPIEndpoint()
        let endpoint = ChatEndpoint(reply: "Please send the quarterly report to", finishReason: "length")

        await app.dictate(saying: "Please send the quarterly report to the whole team by Friday.")

        XCTAssertEqual(endpoint.requests.count, 1)
        XCTAssertEqual(app.focusedApp.text, "Please send the quarterly report to the whole team by Friday.")
    }

    func testAServerErrorTypesWhatWasSaid() async throws {
        let app = try await launchWithAPIEndpoint()
        let endpoint = ChatEndpoint(reply: "Provider returned error", statusCode: 500)

        await app.dictate(saying: "Lunch at noon?")

        XCTAssertEqual(endpoint.requests.count, 1)
        XCTAssertEqual(app.focusedApp.text, "Lunch at noon?")
        XCTAssertEqual(app.appState.recentResults.first?.text, "Lunch at noon?")
    }

    func testEditModeRewritesTheSelectedText() async throws {
        let app = try await launchWithAPIEndpoint()
        app.focusedApp.setFieldText("hey how r u", selected: true)
        let endpoint = ChatEndpoint(reply: "Hello, how are you?")
        app.stubEngine.transcribeResult = .success("make this formal")

        app.hotkeys.onEditModeHotkeyDown?()
        await waitUntil { app.appState.phase == .recording }
        app.hotkeys.onEditModeHotkeyUp?()
        await waitUntil { app.appState.phase == .ready && !endpoint.requests.isEmpty }

        let request = try XCTUnwrap(endpoint.requests.first)
        XCTAssertEqual(request.content(of: "system"), EditModePromptBuilder.rewriteSystemPrompt)
        XCTAssertEqual(request.content(of: "user"), "<instruction>\nmake this formal\n</instruction>\n\n<text>\nhey how r u\n</text>")
        XCTAssertEqual(app.focusedApp.text, "Hello, how are you?")
        XCTAssertEqual(app.appState.recentResults.first?.text, "Hello, how are you?")
    }
}

/// The API key from the settings field to the Keychain item and the request header.
@MainActor
final class KeychainFlowTests: XCTestCase {
    func testTheKeyIsSavedTrimmedSentWithRequestsAndRemovedOnClear() async throws {
        var llm = LLMSettings()
        llm.isEnabled = true
        llm.provider = .openAICompatible
        let app = try FlowApp(self, llm: llm)
        await app.launch()
        XCTAssertFalse(app.appState.hasLLMAPIKey)

        await app.appState.saveLLMAPIKey("  sk-or-v1-pasted-with-spaces \n")
        await app.appState.saveLLMAPIKey("   ")

        XCTAssertEqual(app.apiKeyItem.data.flatMap { String(data: $0, encoding: .utf8) }, "sk-or-v1-pasted-with-spaces")
        XCTAssertEqual(app.appState.llmKeyOperationError, "API key can't be empty.", "an empty entry keeps the saved key")
        XCTAssertTrue(app.appState.hasLLMAPIKey)

        let endpoint = ChatEndpoint(reply: "Done.")
        await app.dictate(saying: "done")
        XCTAssertEqual(endpoint.requests.map(\.authorization), ["Bearer sk-or-v1-pasted-with-spaces"])

        await app.appState.clearLLMAPIKey()
        await app.dictate(saying: "done again")

        XCTAssertNil(app.apiKeyItem.data)
        XCTAssertFalse(app.appState.hasLLMAPIKey)
        XCTAssertEqual(endpoint.requests.count, 1, "no request goes out without a key")
        XCTAssertTrue(app.focusedApp.text.hasSuffix("done again"))
    }
}
