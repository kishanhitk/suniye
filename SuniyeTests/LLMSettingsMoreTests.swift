import XCTest
@testable import Suniye

final class LLMSettingsMoreTests: XCTestCase {
    func testPresetModelIdDefaultsToOpenRouterNamespace() {
        XCTAssertEqual(LLMModelPreset.gemini25Flash.modelId, "google/gemini-2.5-flash")
        XCTAssertEqual(LLMModelPreset.gpt41Mini.modelId, "openai/gpt-4.1-mini")
        XCTAssertEqual(LLMModelPreset.custom.modelId, "")
    }

    func testAppendingBlankAppInstructionsReturnsUnchangedSettings() {
        let settings = LLMSettings(systemPrompt: "user extra")

        XCTAssertEqual(settings.appendingAppInstructions("   \n "), settings)
    }

    func testEndpointProviderForNilURLDefaultsToOpenRouter() {
        XCTAssertEqual(LLMDefaults.endpointProvider(for: nil), .openRouter)
    }
}
