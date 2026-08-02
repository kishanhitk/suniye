import XCTest
@testable import Suniye

final class ComputerUseModelConfigurationTests: XCTestCase {
    func testFactoryRequiresEnabledExplicitAPIProviderAndKey() {
        let settings = LLMSettings(
            isEnabled: true,
            provider: .automatic,
            endpointURLString: "https://example.com/v1/chat/completions"
        )

        XCTAssertNil(
            ComputerUseModelConfigurationFactory.make(
                settings: settings,
                apiKey: "api-key"
            )
        )

        let apiSettings = LLMSettings(
            isEnabled: true,
            provider: .openAICompatible,
            endpointURLString: "https://example.com/v1/chat/completions"
        )
        XCTAssertNil(
            ComputerUseModelConfigurationFactory.make(
                settings: apiSettings,
                apiKey: "  "
            )
        )
        XCTAssertNil(
            ComputerUseModelConfigurationFactory.make(
                settings: apiSettings,
                apiKey: nil
            )
        )
    }

    func testFactoryMapsConfiguredModelWithoutEnablingScreenshotUpload() throws {
        let settings = LLMSettings(
            isEnabled: true,
            provider: .openAICompatible,
            selectedModelPreset: .custom,
            customModelId: "  ui-model  ",
            endpointURLString: "https://example.com/v1/chat/completions",
            timeoutSeconds: 8,
            maxTokens: 256
        )

        let configuration = try XCTUnwrap(
            ComputerUseModelConfigurationFactory.make(
                settings: settings,
                apiKey: "  secret  "
            )
        )

        XCTAssertEqual(configuration.endpointURL.absoluteString, "https://example.com/v1/chat/completions")
        XCTAssertEqual(configuration.modelID, "ui-model")
        XCTAssertEqual(configuration.apiKey, "secret")
        XCTAssertEqual(configuration.timeoutSeconds, 8)
        XCTAssertEqual(configuration.maxTokens, 256)
        XCTAssertFalse(configuration.allowsScreenshotUpload)
        XCTAssertNil(configuration.validationMessage)

        let uploadConfiguration = configuration.withScreenshotUpload(true)
        XCTAssertTrue(uploadConfiguration.allowsScreenshotUpload)
        XCTAssertEqual(uploadConfiguration.modelID, configuration.modelID)
        XCTAssertEqual(uploadConfiguration.apiKey, configuration.apiKey)
    }
}
