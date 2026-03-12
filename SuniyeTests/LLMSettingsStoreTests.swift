import XCTest
@testable import Suniye

final class LLMSettingsStoreTests: XCTestCase {
    func testKeywordParsingDeduplicatesAndTrims() {
        let raw = "foo, Bar\nfoo\n BAR \n,\nqux"
        let parsed = LLMDefaults.parseKeywords(from: raw)

        XCTAssertEqual(parsed, ["foo", "Bar", "qux"])
    }

    func testCustomModelFallsBackWhenInvalid() {
        var settings = LLMSettings()
        settings.selectedModelPreset = .custom
        settings.customModelId = "not-valid"

        XCTAssertEqual(settings.effectiveModelId, "google/gemini-2.5-flash")

        settings.customModelId = "openai/gpt-4.1-mini"
        XCTAssertEqual(settings.effectiveModelId, "openai/gpt-4.1-mini")
    }

    func testStoreRoundTrip() {
        let suite = "dev.suniye.tests.llmsettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = LLMSettingsStore(userDefaults: defaults, storageKey: "llm")

        var settings = LLMSettings()
        settings.isEnabled = true
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

    func testPresetMetadataMatchesMainWindowModelList() {
        XCTAssertEqual(LLMModelPreset.gemini25Flash.displayName, "google/gemini-2.5-flash")
        XCTAssertEqual(LLMModelPreset.gpt41Mini.displayName, "openai/gpt-4.1-mini")
        XCTAssertEqual(LLMModelPreset.gpt41Mini.subtitle, "OpenAI, balanced")
    }
}
