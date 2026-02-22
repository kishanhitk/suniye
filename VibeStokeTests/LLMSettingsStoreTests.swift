import XCTest
@testable import VibeStoke

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

        settings.customModelId = "openai/gpt-oss-20b"
        XCTAssertEqual(settings.effectiveModelId, "openai/gpt-oss-20b")
    }

    func testStoreRoundTrip() {
        let suite = "dev.vibestroke.tests.llmsettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = LLMSettingsStore(userDefaults: defaults, storageKey: "llm")

        var settings = LLMSettings()
        settings.isEnabled = true
        settings.selectedModelPreset = .custom
        settings.customModelId = "openai/gpt-oss-20b"
        settings.systemPrompt = "custom"
        settings.keywordsRaw = "swift, xcode"

        store.save(settings)

        let loaded = store.load()
        XCTAssertEqual(loaded, settings)
    }
}
