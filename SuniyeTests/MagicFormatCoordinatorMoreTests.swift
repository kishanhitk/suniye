import SuniyeAnalytics
import XCTest
@testable import Suniye

@MainActor
final class MagicFormatCoordinatorMoreTests: XCTestCase {
    func testRewriteErrorDescription() {
        XCTAssertEqual(
            MagicFormatRewriteError.providerNotConfigured.errorDescription,
            "Magic Format provider is not ready"
        )
    }

    // MARK: - polish fallbacks (API provider)

    func testAPIPolishFallsBackToRawTextOnWhitespaceOutput() async {
        let coordinator = makeCoordinator(api: FakeLLMPostProcessor(result: .success("   \n ")))
        let request = makeRequest(provider: .openAICompatible)

        let output = await coordinator.polish(input: "polish me", rawText: "raw text", request: request)

        XCTAssertEqual(output.text, "raw text")
        XCTAssertFalse(output.ran) // fell back to raw → not counted as polished
        XCTAssertEqual(output.fallbackReason, .emptyOutput)
        XCTAssertEqual(output.provider, .openAICompatible) // provider recorded even on fallback
    }

    func testAnalyticsModelOverrideMasksAPIModelInOutcome() async {
        // The custom preset's model id is user free text — the override (set at
        // request build) must replace it in the outcome so analytics and logs
        // never see the raw id.
        let coordinator = makeCoordinator(api: FakeLLMPostProcessor(result: .success("polished")))
        var request = makeRequest(provider: .openAICompatible)
        request.analyticsModelOverride = "custom"

        let output = await coordinator.polish(input: "polish me", rawText: "raw text", request: request)

        XCTAssertTrue(output.ran)
        XCTAssertEqual(output.model, "custom")
    }

    func testEveryLLMErrorMapsToASpecificFallbackReason() {
        // Reason fidelity: no producible error may silently degrade to .unknown —
        // the fallback-reasons dashboard card exists to diagnose these.
        XCTAssertEqual(CleanupFallbackReason(LLMPostProcessorError.invalidConfiguration("x")), .invalidConfig)
        XCTAssertEqual(CleanupFallbackReason(LLMPostProcessorError.timeout), .timeout)
        XCTAssertEqual(CleanupFallbackReason(LLMPostProcessorError.unauthorized), .unauthorized)
        XCTAssertEqual(CleanupFallbackReason(LLMPostProcessorError.provider("x")), .providerError)
        XCTAssertEqual(CleanupFallbackReason(LLMPostProcessorError.malformedResponse), .malformedResponse)
        XCTAssertEqual(CleanupFallbackReason(LLMPostProcessorError.emptyOutput), .emptyOutput)
        XCTAssertEqual(CleanupFallbackReason(LLMPostProcessorError.network("x")), .network)
    }

    func testUnresolvedLocalProviderRecordsAttemptedProviderAndReason() async {
        let coordinator = makeCoordinator()
        let request = makeRequest(provider: .localGemma, localGemmaAvailability: .runtimeUnavailable)

        let output = await coordinator.polish(input: "polish me", rawText: "raw text", request: request)

        XCTAssertEqual(output.text, "raw text")
        XCTAssertFalse(output.ran)
        XCTAssertEqual(output.provider, .localGemma) // which provider was attempted
        XCTAssertEqual(output.fallbackReason, .providerUnavailable)
    }

    func testAPIPolishFallsBackToRawTextOnUnknownError() async {
        let coordinator = makeCoordinator(api: FakeLLMPostProcessor(result: .failure(FakeError(message: "surprise"))))
        let request = makeRequest(provider: .openAICompatible)

        let output = await coordinator.polish(input: "polish me", rawText: "raw text", request: request)

        XCTAssertEqual(output.text, "raw text")
        XCTAssertFalse(output.ran) // fell back to raw → not counted as polished
    }

    func testPolishReportsRanEvenWhenOutputEqualsInput() async {
        // The exact "Magic Format 0%" bug: an idempotent polish (a provider runs
        // but returns text identical to the input) still RAN, so it must count as
        // polished — `ran` is not "did the text change".
        let coordinator = makeCoordinator(api: FakeLLMPostProcessor(result: .success("polish me")))
        let request = makeRequest(provider: .openAICompatible)

        let output = await coordinator.polish(input: "polish me", rawText: "raw text", request: request)

        XCTAssertEqual(output.text, "polish me")
        XCTAssertTrue(output.ran)
        XCTAssertNotNil(output.provider) // provider recorded even on an idempotent polish
    }

    // MARK: - polish fallbacks (Apple provider)

    func testApplePolishFallsBackToRawTextOnWhitespaceOutput() async {
        let apple = CapturingAppleMagicFormatPostProcessor(availability: .available, result: .success("  "))
        let coordinator = makeCoordinator(apple: apple)
        let request = makeRequest(provider: .appleFoundationModels, appleAvailability: .available)

        let output = await coordinator.polish(input: "polish me", rawText: "raw text", request: request)

        XCTAssertEqual(output.text, "raw text")
        XCTAssertFalse(output.ran) // fell back to raw → not counted as polished
        XCTAssertEqual(apple.callCount, 1)
    }

    func testApplePolishFallsBackToRawTextOnUnknownError() async {
        let apple = CapturingAppleMagicFormatPostProcessor(
            availability: .available,
            result: .failure(FakeError(message: "surprise"))
        )
        let coordinator = makeCoordinator(apple: apple)
        let request = makeRequest(provider: .appleFoundationModels, appleAvailability: .available)

        let output = await coordinator.polish(input: "polish me", rawText: "raw text", request: request)

        XCTAssertEqual(output.text, "raw text")
        XCTAssertFalse(output.ran) // fell back to raw → not counted as polished
    }

    // MARK: - polish fallbacks (local Gemma provider)

    func testGemmaPolishFallsBackToRawTextOnWhitespaceOutput() async {
        let gemma = CapturingLocalGemmaMagicFormatPostProcessor(availability: .available, result: .success(" \n "))
        let coordinator = makeCoordinator(gemma: gemma)
        let request = makeRequest(provider: .localGemma, localGemmaAvailability: .available)

        let output = await coordinator.polish(input: "polish me", rawText: "raw text", request: request)

        XCTAssertEqual(output.text, "raw text")
        XCTAssertFalse(output.ran) // fell back to raw → not counted as polished
        XCTAssertEqual(gemma.callCount, 1)
    }

    func testGemmaPolishFallsBackToRawTextOnLLMError() async {
        let gemma = CapturingLocalGemmaMagicFormatPostProcessor(
            availability: .available,
            result: .failure(LLMPostProcessorError.timeout)
        )
        let coordinator = makeCoordinator(gemma: gemma)
        let request = makeRequest(provider: .localGemma, localGemmaAvailability: .available)

        let output = await coordinator.polish(input: "polish me", rawText: "raw text", request: request)

        XCTAssertEqual(output.text, "raw text")
        XCTAssertFalse(output.ran) // fell back to raw → not counted as polished
        XCTAssertEqual(output.fallbackReason, .timeout) // typed reason survives the boundary
    }

    func testGemmaPolishFallsBackToRawTextOnUnknownError() async {
        let gemma = CapturingLocalGemmaMagicFormatPostProcessor(
            availability: .available,
            result: .failure(FakeError(message: "surprise"))
        )
        let coordinator = makeCoordinator(gemma: gemma)
        let request = makeRequest(provider: .localGemma, localGemmaAvailability: .available)

        let output = await coordinator.polish(input: "polish me", rawText: "raw text", request: request)

        XCTAssertEqual(output.text, "raw text")
        XCTAssertFalse(output.ran) // fell back to raw → not counted as polished
    }

    // MARK: - rewrite

    func testRewriteAdvertisesLocalModelStartupWhenRuntimeCold() async throws {
        let gemma = CapturingLocalGemmaMagicFormatPostProcessor(
            availability: .available,
            runtimeWarm: false,
            result: .success("rewritten")
        )
        let coordinator = makeCoordinator(gemma: gemma)
        var stages: [String] = []
        let request = makeRequest(
            provider: .localGemma,
            localGemmaAvailability: .available,
            setStage: { stages.append($0) }
        )

        let output = try await coordinator.rewrite(instructions: "sys", userText: "user", request: request)

        XCTAssertEqual(output, "rewritten")
        XCTAssertEqual(stages, [MagicFormatCoordinator.Stage.startingLocalModel])
    }

    func testRewriteThrowsEmptyOutputForWhitespaceResult() async {
        let gemma = CapturingLocalGemmaMagicFormatPostProcessor(
            availability: .available,
            runtimeWarm: true,
            result: .success("   ")
        )
        let coordinator = makeCoordinator(gemma: gemma)
        let request = makeRequest(provider: .localGemma, localGemmaAvailability: .available)

        do {
            _ = try await coordinator.rewrite(instructions: "sys", userText: "user", request: request)
            XCTFail("Expected empty output")
        } catch let error as LLMPostProcessorError {
            XCTAssertEqual(error.logValue, LLMPostProcessorError.emptyOutput.logValue)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Helpers

    private func makeCoordinator(
        api: LLMPostProcessor = FakeLLMPostProcessor(result: .success("unused")),
        apple: AppleMagicFormatPostProcessor = NoopAppleMagicFormatPostProcessor(availability: .deviceNotEligible),
        gemma: LocalGemmaMagicFormatPostProcessor = NoopLocalGemmaMagicFormatPostProcessor(availability: .modelNotInstalled)
    ) -> MagicFormatCoordinator {
        MagicFormatCoordinator(
            apiPostProcessor: api,
            applePostProcessor: apple,
            localGemmaPostProcessor: gemma
        )
    }

    private func makeRequest(
        provider: MagicFormatProvider,
        appleAvailability: AppleFoundationModelsAvailability = .deviceNotEligible,
        localGemmaAvailability: LocalGemmaAvailability = .modelNotInstalled,
        setStage: @escaping (String) -> Void = { _ in }
    ) -> MagicFormatCoordinator.PolishRequest {
        MagicFormatCoordinator.PolishRequest(
            requestedProvider: provider,
            settings: LLMSettings(),
            hasAPIKey: true,
            appleAvailability: appleAvailability,
            localGemmaAvailability: localGemmaAvailability,
            readAPIKey: { "sk-test-key" },
            onAPIKeyReadFailed: {},
            startSlowWarning: { Task {} },
            setStage: setStage
        )
    }
}
