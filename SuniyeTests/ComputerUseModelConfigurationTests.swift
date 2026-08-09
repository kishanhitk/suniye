import XCTest
@testable import Suniye

final class ComputerUseModelConfigurationTests: XCTestCase {
    func testConfigurationUsesTheSavedEndpointModelAndKeyWithoutMagicFormatGating() throws {
        let settings = LLMSettings(
            isEnabled: false,
            provider: .automatic,
            selectedModelPreset: .custom,
            customModelId: "gpt-5.6-luna",
            endpointURLString: "https://example.com/v1/chat/completions"
        )

        let configuration = try XCTUnwrap(
            ComputerUseModelConfigurationFactory.make(
                settings: settings,
                apiKey: "  secret  "
            )
        )

        XCTAssertEqual(
            configuration,
            ComputerUseRemoteModelConfiguration(
                endpointURL: URL(string: "https://example.com/v1/chat/completions")!,
                modelID: "gpt-5.6-luna",
                apiKey: "secret"
            )
        )
    }
}
