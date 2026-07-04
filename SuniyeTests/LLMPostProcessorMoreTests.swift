import XCTest
@testable import Suniye

final class LLMPostProcessorMoreTests: XCTestCase {
    // MARK: - LocalGemmaMagicFormatPostProcessor protocol defaults

    func testLocalGemmaFormatterProtocolDefaultsAreColdAndInert() async {
        let formatter = MinimalLocalGemmaFormatter()
        let config = LocalGemmaMagicFormatConfig(
            systemPrompt: "",
            keywords: [],
            startupTimeoutSeconds: 1,
            generationTimeoutSeconds: 1,
            idleTimeoutSeconds: 1,
            maxTokens: 32
        )

        let warm = await formatter.isRuntimeWarm()
        await formatter.prewarm(config: config)
        await formatter.stopRuntime()

        XCTAssertFalse(warm)
    }

    // MARK: - Availability status text

    func testAppleAvailabilityStatusTextCoversEveryCase() {
        XCTAssertEqual(AppleFoundationModelsAvailability.available.statusText, "Apple Intelligence ready.")
        XCTAssertEqual(
            AppleFoundationModelsAvailability.deviceNotEligible.statusText,
            "Apple Intelligence is not available on this Mac."
        )
        XCTAssertEqual(
            AppleFoundationModelsAvailability.appleIntelligenceNotEnabled.statusText,
            "Turn on Apple Intelligence in System Settings."
        )
        XCTAssertEqual(
            AppleFoundationModelsAvailability.modelNotReady.statusText,
            "Apple Intelligence model is downloading or preparing."
        )
        XCTAssertEqual(
            AppleFoundationModelsAvailability.unsupportedSDKOrRuntime.statusText,
            "Apple Intelligence requires macOS 26 or newer."
        )
    }

    func testLocalGemmaAvailabilityStatusTextCoversEveryCase() {
        XCTAssertEqual(LocalGemmaAvailability.available.statusText, "Local model ready.")
        XCTAssertEqual(LocalGemmaAvailability.unsupportedHardware.statusText, "Local model requires Apple Silicon.")
        XCTAssertEqual(LocalGemmaAvailability.runtimeUnavailable.statusText, "Local model runtime is not available.")
        XCTAssertEqual(LocalGemmaAvailability.modelNotInstalled.statusText, "Local model is not installed.")
    }
}

/// Implements only the protocol requirements so the extension defaults
/// (cold runtime, no-op prewarm/stop) are exercised.
private struct MinimalLocalGemmaFormatter: LocalGemmaMagicFormatPostProcessor {
    var availability: LocalGemmaAvailability {
        .available
    }

    func polish(text: String, config: LocalGemmaMagicFormatConfig) async throws -> String {
        text
    }

    func testSetup(config: LocalGemmaMagicFormatConfig) async throws {}

    func generate(instructions: String, userText: String, config: LocalGemmaMagicFormatConfig) async throws -> String {
        userText
    }
}
