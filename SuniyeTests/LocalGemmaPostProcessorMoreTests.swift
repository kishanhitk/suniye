import XCTest
@testable import Suniye

final class LocalGemmaPostProcessorMoreTests: XCTestCase {
    // MARK: - LocalGemmaClient protocol defaults

    func testClientProtocolDefaultsAreColdAndInert() async {
        let client = MinimalGemmaClient()

        let warm = await client.isRuntimeWarm()
        await client.stopRuntime()

        XCTAssertFalse(warm)
    }

    // MARK: - polish error mapping

    func testPolishRethrowsLLMPostProcessorErrors() async {
        let client = ScriptedGemmaClient(results: [.failure(LLMPostProcessorError.unauthorized)])
        let processor = LocalGemmaPostProcessor(client: client)

        do {
            _ = try await processor.polish(text: "raw text", config: makeConfig())
            XCTFail("Expected unauthorized error")
        } catch let error as LLMPostProcessorError {
            XCTAssertEqual(error.logValue, LLMPostProcessorError.unauthorized.logValue)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPolishWrapsUnknownErrorsAsProviderErrors() async {
        let client = ScriptedGemmaClient(results: [.failure(FakeError(message: "socket died"))])
        let processor = LocalGemmaPostProcessor(client: client)

        do {
            _ = try await processor.polish(text: "raw text", config: makeConfig())
            XCTFail("Expected provider error")
        } catch let error as LLMPostProcessorError {
            XCTAssertEqual(error.logValue, "provider_error")
            XCTAssertEqual(error.errorDescription, "LLM provider error: socket died")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - generate

    func testGenerateSanitizesControlTokens() async throws {
        let client = ScriptedGemmaClient(results: [.success("<|channel>final\nRewritten text<end_of_turn>")])
        let processor = LocalGemmaPostProcessor(client: client)

        let output = try await processor.generate(
            instructions: "Rewrite it.",
            userText: "raw text",
            config: makeConfig()
        )

        XCTAssertEqual(output, "Rewritten text")
        XCTAssertEqual(client.instructions, ["Rewrite it."])
        XCTAssertEqual(client.prompts, ["raw text"])
    }

    func testGenerateThrowsWhenUnavailable() async {
        let client = ScriptedGemmaClient(availability: .modelNotInstalled, results: [])
        let processor = LocalGemmaPostProcessor(client: client)

        do {
            _ = try await processor.generate(instructions: "sys", userText: "user", config: makeConfig())
            XCTFail("Expected invalid configuration")
        } catch let error as LLMPostProcessorError {
            XCTAssertEqual(
                error.errorDescription,
                LLMPostProcessorError.invalidConfiguration("model_not_installed").errorDescription
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGenerateThrowsEmptyOutputForControlTokenOnlyResponse() async {
        let client = ScriptedGemmaClient(results: [.success("<end_of_turn>")])
        let processor = LocalGemmaPostProcessor(client: client)

        do {
            _ = try await processor.generate(instructions: "sys", userText: "user", config: makeConfig())
            XCTFail("Expected empty output")
        } catch let error as LLMPostProcessorError {
            XCTAssertEqual(error.logValue, LLMPostProcessorError.emptyOutput.logValue)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGenerateRethrowsLLMPostProcessorErrors() async {
        let client = ScriptedGemmaClient(results: [.failure(LLMPostProcessorError.timeout)])
        let processor = LocalGemmaPostProcessor(client: client)

        do {
            _ = try await processor.generate(instructions: "sys", userText: "user", config: makeConfig())
            XCTFail("Expected timeout")
        } catch let error as LLMPostProcessorError {
            XCTAssertEqual(error.logValue, LLMPostProcessorError.timeout.logValue)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGenerateWrapsUnknownErrorsAsProviderErrors() async {
        let client = ScriptedGemmaClient(results: [.failure(FakeError(message: "boom"))])
        let processor = LocalGemmaPostProcessor(client: client)

        do {
            _ = try await processor.generate(instructions: "sys", userText: "user", config: makeConfig())
            XCTFail("Expected provider error")
        } catch let error as LLMPostProcessorError {
            XCTAssertEqual(error.errorDescription, "LLM provider error: boom")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - testSetup

    func testSetupThrowsWhenUnavailable() async {
        let client = ScriptedGemmaClient(availability: .unsupportedHardware, results: [])
        let processor = LocalGemmaPostProcessor(client: client)

        do {
            try await processor.testSetup(config: makeConfig())
            XCTFail("Expected invalid configuration")
        } catch let error as LLMPostProcessorError {
            XCTAssertEqual(
                error.errorDescription,
                LLMPostProcessorError.invalidConfiguration("unsupported_hardware").errorDescription
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSetupThrowsEmptyOutputForControlTokenOnlyProbe() async {
        let client = ScriptedGemmaClient(results: [.success("<eos>")])
        let processor = LocalGemmaPostProcessor(client: client)

        do {
            try await processor.testSetup(config: makeConfig())
            XCTFail("Expected empty output")
        } catch let error as LLMPostProcessorError {
            XCTAssertEqual(error.logValue, LLMPostProcessorError.emptyOutput.logValue)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - stopRuntime

    func testStopRuntimeForwardsToClient() async {
        let client = ScriptedGemmaClient(results: [])
        let processor = LocalGemmaPostProcessor(client: client)

        await processor.stopRuntime()

        XCTAssertEqual(client.stopRuntimeCallCount, 1)
    }

    private func makeConfig() -> LocalGemmaMagicFormatConfig {
        LocalGemmaMagicFormatConfig(
            systemPrompt: LLMDefaults.defaultGemmaMagicFormatPrompt,
            keywords: [],
            startupTimeoutSeconds: 0.1,
            generationTimeoutSeconds: 0.1,
            idleTimeoutSeconds: 600,
            maxTokens: 128
        )
    }
}

/// Implements only the protocol requirements so the LocalGemmaClient extension
/// defaults (cold runtime, no-op stop) are exercised.
private struct MinimalGemmaClient: LocalGemmaClient {
    var availability: LocalGemmaAvailability {
        .available
    }

    func generate(
        instructions: String,
        prompt: String,
        maxTokens: Int,
        startupTimeoutSeconds: Double,
        idleTimeoutSeconds: Double,
        timeoutSeconds: Double
    ) async throws -> String {
        "OK"
    }
}

private final class ScriptedGemmaClient: LocalGemmaClient {
    var availability: LocalGemmaAvailability
    private var results: [Result<String, Error>]
    private(set) var instructions: [String] = []
    private(set) var prompts: [String] = []
    private(set) var stopRuntimeCallCount = 0

    init(availability: LocalGemmaAvailability = .available, results: [Result<String, Error>]) {
        self.availability = availability
        self.results = results
    }

    func isRuntimeWarm() async -> Bool {
        false
    }

    func generate(
        instructions: String,
        prompt: String,
        maxTokens: Int,
        startupTimeoutSeconds: Double,
        idleTimeoutSeconds: Double,
        timeoutSeconds: Double
    ) async throws -> String {
        self.instructions.append(instructions)
        prompts.append(prompt)
        guard !results.isEmpty else {
            throw LLMPostProcessorError.emptyOutput
        }
        return try results.removeFirst().get()
    }

    func stopRuntime() async {
        stopRuntimeCallCount += 1
    }
}
