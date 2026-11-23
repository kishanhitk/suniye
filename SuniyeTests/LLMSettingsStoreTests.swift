import XCTest
@testable import Suniye

final class LLMSettingsStoreTests: XCTestCase {
    func testKeywordParsingDeduplicatesAndTrims() {
        let raw = "foo, Bar\nfoo\n BAR \n,\nqux"
        let parsed = LLMDefaults.parseKeywords(from: raw)

        XCTAssertEqual(parsed, ["foo", "Bar", "qux"])
    }

    func testCustomModelAcceptsNativeAndProviderPrefixedIDs() {
        var settings = LLMSettings()
        settings.selectedModelPreset = .custom
        settings.customModelId = "gpt-4.1-mini"

        XCTAssertEqual(settings.validatedModelId, "gpt-4.1-mini")

        settings.customModelId = "openai/gpt-4.1-mini"
        XCTAssertEqual(settings.validatedModelId, "openai/gpt-4.1-mini")
    }

    func testCustomModelRequiresNonEmptySingleLineID() {
        var settings = LLMSettings()
        settings.selectedModelPreset = .custom
        settings.customModelId = "   "

        XCTAssertNil(settings.validatedModelId)
        XCTAssertEqual(settings.modelValidationError, "Enter a valid custom model name.")

        settings.customModelId = "gpt-4.1-mini\nbeta"
        XCTAssertNil(settings.validatedModelId)
        XCTAssertEqual(settings.modelValidationError, "Enter a valid custom model name.")
    }

    /// The stored JSON is a contract with every installed copy: a blob that a
    /// released build wrote must load and save back with the same keys and values.
    func testStoredBlobOfAReleasedBuildSavesBackUnchanged() throws {
        let stored = #"{"isEnabled":true,"provider":"localGemma","selectedModelPreset":"custom","customModelId":"my/model","endpointURLString":"https://example.com/v1/chat/completions","baseSystemPrompt":"API prompt","appleSystemPrompt":"Apple prompt","gemmaSystemPrompt":"Gemma prompt","systemPrompt":"","keywordsRaw":"Suniye, Kishan","autoLearnedKeywordsRaw":"Zed","learnFromEditsEnabled":false,"timeoutSeconds":12,"localModelKeepAlive":"oneHour","appPromptBindings":[{"id":"A1B2C3D4-0000-0000-0000-000000000001","bundleID":"com.tinyspeck.slackmacgap","appDisplayName":"Slack","prompt":"casual"}]}"#
        let suite = "dev.suniye.tests.llm.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data(stored.utf8), forKey: "dev.suniye.llm.settings")
        let store = LLMSettingsStore(userDefaults: defaults)

        store.save(store.load())

        let saved = try XCTUnwrap(defaults.data(forKey: "dev.suniye.llm.settings"))
        XCTAssertEqual(
            try JSONSerialization.jsonObject(with: saved) as? NSDictionary,
            try JSONSerialization.jsonObject(with: Data(stored.utf8)) as? NSDictionary
        )
    }

    func testStoreRoundTrip() {
        let suite = "dev.suniye.tests.llmsettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = LLMSettingsStore(userDefaults: defaults)

        var settings = LLMSettings()
        settings.isEnabled = true
        settings.provider = .appleFoundationModels
        settings.selectedModelPreset = .custom
        settings.customModelId = "openai/gpt-4.1-mini"
        settings.baseSystemPrompt = "base"
        settings.appleSystemPrompt = "apple"
        settings.gemmaSystemPrompt = "gemma"
        settings.systemPrompt = "custom"
        settings.keywordsRaw = "swift, xcode"
        settings.timeoutSeconds = 7.5

        store.save(settings)

        let loaded = store.load()
        XCTAssertEqual(loaded, settings)
    }

    func testKeepAliveDurationRoundTrips() {
        let suite = "dev.suniye.tests.llmsettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = LLMSettingsStore(userDefaults: defaults)

        var settings = LLMSettings()
        settings.localModelKeepAlive = .oneHour
        store.save(settings)

        XCTAssertEqual(store.load().localModelKeepAlive, .oneHour)
    }

    func testMissingKeepAliveDecodesToTenMinutes() throws {
        let data = """
        {
          "isEnabled": true,
          "selectedModelPreset": "gpt41Mini",
          "customModelId": "",
          "endpointURLString": "\(LLMDefaults.defaultEndpointURLString)",
          "baseSystemPrompt": "api prompt",
          "systemPrompt": "",
          "keywordsRaw": "",
          "timeoutSeconds": 12,
          "maxTokens": 128
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(LLMSettings.self, from: data)

        XCTAssertEqual(settings.localModelKeepAlive, .tenMinutes)
    }

    func testMissingProviderAndLocalPromptsDecodeToDefaults() throws {
        let data = """
        {
          "isEnabled": true,
          "selectedModelPreset": "gpt41Mini",
          "customModelId": "",
          "endpointURLString": "\(LLMDefaults.defaultEndpointURLString)",
          "baseSystemPrompt": "api prompt",
          "systemPrompt": "",
          "keywordsRaw": "",
          "timeoutSeconds": 12,
          "maxTokens": 128
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(LLMSettings.self, from: data)

        XCTAssertEqual(settings.provider, .automatic)
        XCTAssertEqual(settings.appleSystemPrompt, LLMDefaults.defaultAppleMagicFormatPrompt)
        XCTAssertEqual(settings.gemmaSystemPrompt, LLMDefaults.defaultGemmaMagicFormatPrompt)
        XCTAssertFalse(settings.hasExplicitAppleSystemPrompt)
        XCTAssertFalse(settings.hasExplicitGemmaSystemPrompt)
    }

    func testAppleGemmaAndAPIPromptsAreIndependent() {
        var settings = LLMSettings()
        settings.baseSystemPrompt = "api prompt"
        settings.appleSystemPrompt = "apple prompt"
        settings.gemmaSystemPrompt = "gemma prompt"

        XCTAssertEqual(settings.composedSystemPrompt, "api prompt")
        XCTAssertEqual(settings.composedAppleSystemPrompt, "apple prompt")
        XCTAssertEqual(settings.composedGemmaSystemPrompt, "gemma prompt")
    }

    func testDefaultGemmaPromptIsTunedSeparatelyFromApplePrompt() {
        XCTAssertNotEqual(LLMDefaults.defaultGemmaMagicFormatPrompt, LLMDefaults.defaultAppleMagicFormatPrompt)
        XCTAssertTrue(LLMDefaults.defaultGemmaMagicFormatPrompt.contains("Ordinary \"and\" alone does not make a list"))
        XCTAssertTrue(LLMDefaults.defaultAppleMagicFormatPrompt.contains("You are a text-transformation tool"))
    }

    func testDefaultLocalPromptsAvoidAppSpecificExamples() {
        let prompts = [
            LLMDefaults.defaultAppleMagicFormatPrompt,
            LLMDefaults.defaultGemmaMagicFormatPrompt,
        ]
        // "<transcript>" is intentionally allowed: the wrapper tag is part of the
        // generation contract (MagicFormatPipeline wraps input in it) and the tuned
        // prompt references it to stop the model from echoing the tags.
        let appSpecificTerms = [
            "Suniye",
            "Magic Format",
            "Apple Intelligence",
            "Foundation Models",
            "AppState",
            "postProcessText",
            "MainActor",
            "sherpa",
            "xcodegen",
            "Linear ticket",
            "git branch",
        ]

        for prompt in prompts {
            for term in appSpecificTerms {
                XCTAssertFalse(prompt.contains(term), "Default prompt should not contain app-specific term: \(term)")
            }
        }
    }

    func testTimeoutClamping() {
        let settings = LLMSettings(timeoutSeconds: 99)
        XCTAssertEqual(settings.timeoutSeconds, LLMDefaults.maxTimeoutSeconds)
    }

    func testComposedPromptUsesBaseAndUserSections() {
        var settings = LLMSettings()
        settings.baseSystemPrompt = "BASE"
        settings.systemPrompt = "USER"
        XCTAssertEqual(settings.composedSystemPrompt, "BASE\n\nUser customization:\nUSER")

        settings.systemPrompt = "   "
        XCTAssertEqual(settings.composedSystemPrompt, "BASE")
    }

    func testEndpointNormalizationAcceptsBaseOrCompletionsPath() {
        var settings = LLMSettings()
        settings.endpointURLString = "https://api.openai.com/v1"
        XCTAssertEqual(settings.validatedEndpointURL?.absoluteString, "https://api.openai.com/v1/chat/completions")

        settings.endpointURLString = "https://example.com/proxy/chat/completions"
        XCTAssertEqual(settings.validatedEndpointURL?.absoluteString, "https://example.com/proxy/chat/completions")
    }

    func testPresetModelIdsAdaptToEndpointProvider() {
        var settings = LLMSettings()
        settings.selectedModelPreset = .gpt41Mini
        settings.endpointURLString = LLMDefaults.defaultEndpointURLString
        XCTAssertEqual(settings.validatedModelId, "openai/gpt-4.1-mini")

        settings.endpointURLString = "https://api.openai.com/v1/chat/completions"
        XCTAssertEqual(settings.validatedModelId, "gpt-4.1-mini")
        XCTAssertEqual(settings.displayModelId(for: .gpt41Mini), "gpt-4.1-mini")
    }

    func testInvalidEndpointDoesNotFallBackToDefaultProvider() {
        var settings = LLMSettings()
        settings.endpointURLString = "not a url"

        XCTAssertNil(settings.validatedEndpointURL)
        XCTAssertFalse(settings.isEndpointValid)
        XCTAssertEqual(settings.endpointValidationError, "Enter a valid service URL.")

        settings.endpointURLString = "https://"
        XCTAssertNil(settings.validatedEndpointURL)
        XCTAssertFalse(settings.isEndpointValid)

        settings.endpointURLString = "http:///path"
        XCTAssertNil(settings.validatedEndpointURL)
        XCTAssertFalse(settings.isEndpointValid)
    }

    func testLoadReturnsDefaultsWhenNothingIsStored() {
        let suite = "dev.suniye.tests.llm.empty.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = LLMSettingsStore(userDefaults: defaults)

        XCTAssertEqual(store.load(), LLMSettings())
    }

    func testSaveSilentlySkipsUnencodableSettings() {
        let suite = "dev.suniye.tests.llm.unencodable.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = LLMSettingsStore(userDefaults: defaults)

        // Bypass the clamping initializer; infinity is not representable by
        // the JSON encoder, so save must bail out without writing anything.
        var unencodable = LLMSettings()
        unencodable.timeoutSeconds = .infinity

        store.save(unencodable)

        XCTAssertNil(defaults.data(forKey: "dev.suniye.llm.settings"))
        XCTAssertEqual(store.load(), LLMSettings())
    }
}
