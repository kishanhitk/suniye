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

    func testRewriteUsesLocalGemmaWithEditModeConfig() async throws {
        let gemma = CapturingLocalGemmaMagicFormatPostProcessor(
            availability: .available,
            runtimeWarm: true,
            result: .success("rewritten output")
        )
        let coordinator = makeCoordinator(api: CapturingLLMPostProcessor(result: .success("unused")), gemma: gemma)
        let request = makeRequest(
            provider: .localGemma,
            hasAPIKey: false,
            readAPIKey: { nil },
            localGemmaAvailability: .available
        )
        let userText = EditModePromptBuilder.userText(instruction: "make this formal", selectedText: "hey there")

        let output = try await coordinator.rewrite(
            instructions: EditModePromptBuilder.rewriteSystemPrompt,
            userText: userText,
            request: request
        )

        XCTAssertEqual(output, "rewritten output")
        XCTAssertEqual(gemma.lastGenerateInstructions, EditModePromptBuilder.rewriteSystemPrompt)
        XCTAssertEqual(gemma.lastGenerateUserText, userText)
        // Edit-mode config: no Magic Format prompt or vocabulary leaks in, and the
        // output budget/timeout are the edit-mode values.
        XCTAssertEqual(gemma.lastConfig?.systemPrompt, "")
        XCTAssertEqual(gemma.lastConfig?.keywords, [])
        XCTAssertEqual(gemma.lastConfig?.maxTokens, LLMDefaults.editModeMaxTokens)
        XCTAssertEqual(gemma.lastConfig?.generationTimeoutSeconds, LocalGemmaDefaults.editModeGenerationTimeoutSeconds)
    }

    func testRewriteCancelsInFlightPrewarm() async throws {
        let gemma = CapturingLocalGemmaMagicFormatPostProcessor(
            availability: .available,
            runtimeWarm: true,
            result: .success("rewritten output")
        )
        gemma.prewarmBlocksUntilCanceled = true
        let coordinator = makeCoordinator(api: CapturingLLMPostProcessor(result: .success("unused")), gemma: gemma)
        let request = makeRequest(
            provider: .localGemma,
            hasAPIKey: false,
            readAPIKey: { nil },
            localGemmaAvailability: .available
        )

        let prewarm = coordinator.prewarmLocalIfEligible(
            requestedProvider: .localGemma,
            settings: LLMSettings(),
            appleAvailability: .deviceNotEligible,
            localGemmaAvailability: .available
        )
        XCTAssertNotNil(prewarm)
        try await waitUntil { gemma.prewarmCallCount == 1 }

        let output = try await coordinator.rewrite(instructions: "sys", userText: "user", request: request)
        await prewarm?.value

        XCTAssertEqual(output, "rewritten output")
        XCTAssertTrue(gemma.prewarmWasCanceled)
    }

    private func makeCoordinator(
        api: LLMPostProcessor,
        gemma: LocalGemmaMagicFormatPostProcessor = NoopLocalGemmaMagicFormatPostProcessor(availability: .modelNotInstalled)
    ) -> MagicFormatCoordinator {
        MagicFormatCoordinator(
            apiPostProcessor: api,
            applePostProcessor: NoopAppleMagicFormatPostProcessor(availability: .deviceNotEligible),
            localGemmaPostProcessor: gemma
        )
    }

    private func makeRequest(
        provider: MagicFormatProvider,
        hasAPIKey: Bool,
        readAPIKey: @escaping () -> String?,
        onAPIKeyReadFailed: @escaping () -> Void = {},
        localGemmaAvailability: LocalGemmaAvailability = .modelNotInstalled
    ) -> MagicFormatCoordinator.PolishRequest {
        MagicFormatCoordinator.PolishRequest(
            requestedProvider: provider,
            settings: LLMSettings(),
            hasAPIKey: hasAPIKey,
            appleAvailability: .deviceNotEligible,
            localGemmaAvailability: localGemmaAvailability,
            readAPIKey: readAPIKey,
            onAPIKeyReadFailed: onAPIKeyReadFailed,
            startSlowWarning: { Task {} },
            setStage: { _ in }
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                throw FakeError(message: "condition not met within \(timeout)s")
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
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
