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
        settings.selectedMagicFormatMode = .email
        settings.promptOverridesByMode = [MagicFormatMode.email.rawValue: "email prompt"]
        settings.selectedModelPreset = .custom
        settings.customModelId = "openai/gpt-4.1-mini"
        settings.baseSystemPrompt = "base"
        settings.systemPrompt = "custom"
        settings.keywordsRaw = "swift, xcode"
        settings.timeoutSeconds = 7.5
        settings.maxTokens = 256

        store.save(settings)

        let loaded = store.load()
        XCTAssertEqual(loaded, settings)
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

    func testMagicFormatModePromptsUseOverridesAndDefaults() {
        var settings = LLMSettings()
        settings.selectedMagicFormatMode = .message

        XCTAssertEqual(settings.composedSystemPrompt, MagicFormatMode.message.defaultPrompt)

        settings.promptOverridesByMode[MagicFormatMode.message.rawValue] = "custom message prompt"

        XCTAssertEqual(settings.composedSystemPrompt, "custom message prompt")
        XCTAssertTrue(settings.hasPromptOverride(for: .message))
    }

    func testLegacyCustomPromptMigratesToCustomModeOnDecode() throws {
        let data = """
        {
          "isEnabled": true,
          "baseSystemPrompt": "BASE",
          "systemPrompt": "USER",
          "selectedModelPreset": "gpt41Mini",
          "customModelId": "",
          "endpointURLString": "\(LLMDefaults.defaultEndpointURLString)",
          "keywordsRaw": "",
          "timeoutSeconds": 9,
          "maxTokens": 256
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(LLMSettings.self, from: data)

        XCTAssertEqual(settings.selectedMagicFormatMode, .custom)
        XCTAssertEqual(settings.promptOverride(for: .custom), "BASE\n\nUSER")
        XCTAssertEqual(settings.timeoutSeconds, 9)
        XCTAssertEqual(settings.maxTokens, 256)
    }

    func testLegacyDefaultPromptMigratesToCleanDictationOnDecode() throws {
        let data = """
        {
          "isEnabled": true,
          "baseSystemPrompt": \(Self.jsonString(LLMDefaults.defaultBaseSystemPrompt)),
          "systemPrompt": "",
          "selectedModelPreset": "gemini25Flash",
          "customModelId": "",
          "endpointURLString": "\(LLMDefaults.defaultEndpointURLString)",
          "keywordsRaw": "",
          "timeoutSeconds": 3,
          "maxTokens": 128
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(LLMSettings.self, from: data)

        XCTAssertEqual(settings.selectedMagicFormatMode, .cleanDictation)
        XCTAssertTrue(settings.promptOverridesByMode.isEmpty)
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

    func testMagicFormatPresetMetadataMatchesFriendlyEditingStyles() {
        XCTAssertEqual(LLMModelPreset.gemini25Flash.magicFormatLabel, "Fast")
        XCTAssertEqual(LLMModelPreset.gpt41Mini.magicFormatLabel, "Balanced")
        XCTAssertEqual(LLMModelPreset.custom.magicFormatLabel, "Custom")
        XCTAssertEqual(LLMModelPreset.gemini25Flash.magicFormatDescription, "Quick fixes with lower cost.")
        XCTAssertEqual(LLMModelPreset.gpt41Mini.magicFormatDescription, "Best default for most dictation.")
        XCTAssertEqual(LLMModelPreset.custom.magicFormatDescription, "Use the exact model ID supported by your endpoint.")
    }

    private static func jsonString(_ value: String) -> String {
        let data = try! JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8)!
    }
}
