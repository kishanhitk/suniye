import XCTest
@testable import Suniye

@MainActor
final class MagicFormatCoordinatorRewriteTests: XCTestCase {
    func testRewriteThrowsWhenSelectedLocalProviderUnavailable() async {
        let coordinator = makeCoordinator(api: CapturingLLMPostProcessor(result: .success("unused")))
        let request = makeRequest(
            provider: .appleFoundationModels,
            hasAPIKey: false,
            readAPIKey: { nil }
        )

        await assertThrowsProviderNotConfigured {
            try await coordinator.rewrite(instructions: "sys", userText: "user", request: request)
        }
    }

    func testRewriteThrowsProviderNotConfiguredWithoutAPIKey() async {
        let api = CapturingLLMPostProcessor(result: .success("unused"))
        let coordinator = makeCoordinator(api: api)
        let request = makeRequest(
            provider: .openAICompatible,
            hasAPIKey: false,
            readAPIKey: {
                XCTFail("Key should not be read when hasAPIKey is false")
                return "sk-unused"
            }
        )

        await assertThrowsProviderNotConfigured {
            try await coordinator.rewrite(instructions: "sys", userText: "user", request: request)
        }
        XCTAssertNil(api.lastGenerateInstructions)
    }

    func testRewriteFiresKeyReadFailureCallbackWhenKeyUnreadable() async {
        let api = CapturingLLMPostProcessor(result: .success("unused"))
        let coordinator = makeCoordinator(api: api)
        var keyReadFailedCallCount = 0
        let request = makeRequest(
            provider: .openAICompatible,
            hasAPIKey: true,
            readAPIKey: { nil },
            onAPIKeyReadFailed: { keyReadFailedCallCount += 1 }
        )

        await assertThrowsProviderNotConfigured {
            try await coordinator.rewrite(instructions: "sys", userText: "user", request: request)
        }
        XCTAssertEqual(keyReadFailedCallCount, 1)
        XCTAssertNil(api.lastGenerateInstructions)
    }

    func testRewriteUsesAPIProviderWithStoredKey() async throws {
        let api = CapturingLLMPostProcessor(result: .success("rewritten output"))
        let coordinator = makeCoordinator(api: api)
        let request = makeRequest(
            provider: .openAICompatible,
            hasAPIKey: true,
            readAPIKey: { " sk-test-key " }
        )

        let output = try await coordinator.rewrite(instructions: "sys prompt", userText: "user payload", request: request)

        XCTAssertEqual(output, "rewritten output")
        XCTAssertEqual(api.lastGenerateInstructions, "sys prompt")
        XCTAssertEqual(api.lastGenerateUserText, "user payload")
        XCTAssertEqual(api.lastConfig?.apiKey, "sk-test-key")
    }

    private func makeCoordinator(api: LLMPostProcessor) -> MagicFormatCoordinator {
        MagicFormatCoordinator(
            apiPostProcessor: api,
            applePostProcessor: NoopAppleMagicFormatPostProcessor(availability: .deviceNotEligible),
            localGemmaPostProcessor: NoopLocalGemmaMagicFormatPostProcessor(availability: .modelNotInstalled)
        )
    }

    private func makeRequest(
        provider: MagicFormatProvider,
        hasAPIKey: Bool,
        readAPIKey: @escaping () -> String?,
        onAPIKeyReadFailed: @escaping () -> Void = {}
    ) -> MagicFormatCoordinator.PolishRequest {
        MagicFormatCoordinator.PolishRequest(
            requestedProvider: provider,
            settings: LLMSettings(),
            hasAPIKey: hasAPIKey,
            appleAvailability: .deviceNotEligible,
            localGemmaAvailability: .modelNotInstalled,
            readAPIKey: readAPIKey,
            onAPIKeyReadFailed: onAPIKeyReadFailed,
            startSlowWarning: { Task {} },
            setStage: { _ in }
        )
    }

    private func assertThrowsProviderNotConfigured(_ body: () async throws -> String) async {
        do {
            _ = try await body()
            XCTFail("Expected MagicFormatRewriteError.providerNotConfigured")
        } catch let error as MagicFormatRewriteError {
            XCTAssertEqual(error, .providerNotConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
