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

    func testFactoryMapsConfiguredModel() throws {
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
        XCTAssertEqual(configuration.timeoutSeconds, ComputerUseRemoteModelDefaults.timeoutSeconds)
        XCTAssertEqual(configuration.maxTokens, ComputerUseRemoteModelDefaults.maxTokens)
        XCTAssertNil(configuration.validationMessage)
    }
}
