import XCTest
@testable import Suniye

final class LLMSettingsTests: XCTestCase {
    func testAppendingBlankAppInstructionsReturnsUnchangedSettings() {
        let settings = LLMSettings(systemPrompt: "user extra")

        XCTAssertEqual(settings.appendingAppInstructions("   \n "), settings)
    }

    func testEndpointProviderForNilURLDefaultsToOpenRouter() {
        XCTAssertEqual(LLMDefaults.endpointProvider(for: nil), .openRouter)
    }

    func testWhitespaceBasePromptFallsBackToDefaultDuringMerge() {
        var settings = LLMSettings()
        settings.baseSystemPrompt = "   \n "
        settings.systemPrompt = "Extra rule."

        let result = settings.normalizedForCurrentPromptSchema()

        XCTAssertEqual(
            result.settings.baseSystemPrompt,
            LLMDefaults.defaultBaseSystemPrompt + "\n\nExtra rule."
        )
        XCTAssertEqual(result.settings.systemPrompt, "")
        XCTAssertTrue(result.shouldPersist)
    }

    func testMissingProviderPromptsWithoutLegacyCustomizationLoadDefaults() {
        var settings = LLMSettings()
        settings.hasExplicitAppleSystemPrompt = false
        settings.hasExplicitGemmaSystemPrompt = false

        let result = settings.normalizedForCurrentPromptSchema()

        XCTAssertEqual(result.settings.appleSystemPrompt, LLMDefaults.defaultAppleMagicFormatPrompt)
        XCTAssertEqual(result.settings.gemmaSystemPrompt, LLMDefaults.defaultGemmaMagicFormatPrompt)
        XCTAssertFalse(result.shouldPersist)
    }
}
