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

    func testStoreRoundTrip() {
        let suite = "dev.suniye.tests.llmsettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = LLMSettingsStore(userDefaults: defaults, storageKey: "llm")

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
        settings.maxTokens = 256

        store.save(settings)

        let loaded = store.load()
        XCTAssertEqual(loaded, settings)
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
          "timeoutSeconds": 3,
          "maxTokens": 128
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(LLMSettings.self, from: data)

        XCTAssertEqual(settings.provider, .automatic)
        XCTAssertEqual(settings.appleSystemPrompt, LLMDefaults.defaultAppleMagicFormatPrompt)
        XCTAssertEqual(settings.gemmaSystemPrompt, LLMDefaults.defaultGemmaMagicFormatPrompt)
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
        XCTAssertTrue(LLMDefaults.defaultGemmaMagicFormatPrompt.contains("Do not infer a list from ordinary use"))
        XCTAssertTrue(LLMDefaults.defaultAppleMagicFormatPrompt.contains("Use one line by default"))
    }

    func testDefaultLocalPromptsAvoidAppSpecificExamples() {
        let prompts = [
            LLMDefaults.defaultAppleMagicFormatPrompt,
            LLMDefaults.defaultGemmaMagicFormatPrompt,
        ]
        let appSpecificTerms = [
            "<transcript>",
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

    func testTimeoutAndTokenClamping() {
        let settings = LLMSettings(timeoutSeconds: 99, maxTokens: 2)
        XCTAssertEqual(settings.timeoutSeconds, LLMDefaults.maxTimeoutSeconds)
        XCTAssertEqual(settings.maxTokens, LLMDefaults.minMaxTokens)
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

    func testPresetMetadataMatchesMainWindowModelList() {
        XCTAssertEqual(LLMModelPreset.gemini25Flash.displayName, "Gemini 2.5 Flash")
        XCTAssertEqual(LLMModelPreset.gpt41Mini.displayName, "GPT-4.1 Mini")
        XCTAssertEqual(LLMModelPreset.gpt41Mini.subtitle, "OpenAI, balanced")
    }

    func testMagicFormatProviderMetadataIncludesLocalGemma() {
        XCTAssertEqual(MagicFormatProvider.localGemma.displayName, "Local Gemma")
        XCTAssertEqual(MagicFormatProvider.localGemma.description, "Local formatting with Gemma 4 Q4.")
        XCTAssertTrue(MagicFormatProvider.allCases.contains(.localGemma))
    }

    func testMagicFormatPresetMetadataMatchesFriendlyEditingStyles() {
        XCTAssertEqual(LLMModelPreset.gemini25Flash.magicFormatLabel, "Fast")
        XCTAssertEqual(LLMModelPreset.gpt41Mini.magicFormatLabel, "Balanced")
        XCTAssertEqual(LLMModelPreset.custom.magicFormatLabel, "Custom")
        XCTAssertEqual(LLMModelPreset.gemini25Flash.magicFormatDescription, "Quick fixes with lower cost.")
        XCTAssertEqual(LLMModelPreset.gpt41Mini.magicFormatDescription, "Best default for most dictation.")
        XCTAssertEqual(LLMModelPreset.custom.magicFormatDescription, "Use the exact model ID supported by your endpoint.")
    }
}
