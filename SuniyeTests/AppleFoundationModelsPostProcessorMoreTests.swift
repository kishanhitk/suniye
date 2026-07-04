import XCTest
@testable import Suniye

final class AppleFoundationModelsPostProcessorMoreTests: XCTestCase {
    // MARK: - polish error mapping

    func testPolishRethrowsLLMPostProcessorErrors() async {
        let client = ThrowingAppleClient(error: LLMPostProcessorError.unauthorized)
        let processor = AppleFoundationModelsPostProcessor(client: client)

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
        let client = ThrowingAppleClient(error: FakeError(message: "model crashed"))
        let processor = AppleFoundationModelsPostProcessor(client: client)

        do {
            _ = try await processor.polish(text: "raw text", config: makeConfig())
            XCTFail("Expected provider error")
        } catch let error as LLMPostProcessorError {
            XCTAssertEqual(error.errorDescription, "LLM provider error: model crashed")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - generate

    func testGenerateReturnsSanitizedOutput() async throws {
        let client = ScriptedAppleClient(outputs: ["  Rewritten text.  "])
        let processor = AppleFoundationModelsPostProcessor(client: client)

        let output = try await processor.generate(
            instructions: "Rewrite it.",
            userText: "raw text",
            config: makeConfig()
        )

        XCTAssertEqual(output, "Rewritten text.")
        XCTAssertEqual(client.recordedInstructions, ["Rewrite it."])
        XCTAssertEqual(client.recordedPrompts, ["raw text"])
    }

    func testGenerateThrowsWhenUnavailable() async {
        let client = ScriptedAppleClient(availability: .deviceNotEligible, outputs: [])
        let processor = AppleFoundationModelsPostProcessor(client: client)

        do {
            _ = try await processor.generate(instructions: "sys", userText: "user", config: makeConfig())
            XCTFail("Expected invalid configuration")
        } catch let error as LLMPostProcessorError {
            XCTAssertEqual(
                error.errorDescription,
                LLMPostProcessorError.invalidConfiguration("device_not_eligible").errorDescription
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGenerateThrowsEmptyOutputForWhitespaceResponse() async {
        let client = ScriptedAppleClient(outputs: ["   \n  "])
        let processor = AppleFoundationModelsPostProcessor(client: client)

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
        let client = ThrowingAppleClient(error: LLMPostProcessorError.emptyOutput)
        let processor = AppleFoundationModelsPostProcessor(client: client)

        do {
            _ = try await processor.generate(instructions: "sys", userText: "user", config: makeConfig())
            XCTFail("Expected empty output")
        } catch let error as LLMPostProcessorError {
            XCTAssertEqual(error.logValue, LLMPostProcessorError.emptyOutput.logValue)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGenerateMapsTimeoutToLLMTimeout() async {
        let client = ScriptedAppleClient(outputs: ["late"], responseDelayNanoseconds: 300_000_000)
        let processor = AppleFoundationModelsPostProcessor(client: client)

        do {
            _ = try await processor.generate(
                instructions: "sys",
                userText: "user",
                config: makeConfig(timeoutSeconds: 0.02)
            )
            XCTFail("Expected timeout")
        } catch let error as LLMPostProcessorError {
            XCTAssertEqual(error.logValue, LLMPostProcessorError.timeout.logValue)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGenerateWrapsUnknownErrorsAsProviderErrors() async {
        let client = ThrowingAppleClient(error: FakeError(message: "boom"))
        let processor = AppleFoundationModelsPostProcessor(client: client)

        do {
            _ = try await processor.generate(instructions: "sys", userText: "user", config: makeConfig())
            XCTFail("Expected provider error")
        } catch let error as LLMPostProcessorError {
            XCTAssertEqual(error.errorDescription, "LLM provider error: boom")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGenerateFailsWhenCallerCancels() async {
        let client = ScriptedAppleClient(outputs: ["never delivered"], responseDelayNanoseconds: 10_000_000_000)
        let processor = AppleFoundationModelsPostProcessor(client: client)

        let work = Task<Error?, Never> {
            do {
                _ = try await processor.generate(
                    instructions: "sys",
                    userText: "user",
                    config: makeConfig(timeoutSeconds: 30)
                )
                return nil
            } catch {
                return error
            }
        }

        await client.waitUntilGenerateStarted()
        work.cancel()
        let error = await work.value

        XCTAssertNotNil(error, "cancellation must surface as an error, not a successful result")
    }

    // MARK: - testSetup

    func testSetupSucceedsWhenAvailable() async throws {
        let processor = AppleFoundationModelsPostProcessor(client: ScriptedAppleClient(outputs: []))

        try await processor.testSetup(config: makeConfig())
    }

    func testSetupThrowsWhenUnavailable() async {
        let client = ScriptedAppleClient(availability: .modelNotReady, outputs: [])
        let processor = AppleFoundationModelsPostProcessor(client: client)

        do {
            try await processor.testSetup(config: makeConfig())
            XCTFail("Expected invalid configuration")
        } catch let error as LLMPostProcessorError {
            XCTAssertEqual(
                error.errorDescription,
                LLMPostProcessorError.invalidConfiguration("model_not_ready").errorDescription
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - TimeoutRace fast-completion path

    func testRepeatedInstantGenerationsCompleteBeforeTimeout() async throws {
        // Exercises the TimeoutRace branch where the result lands before wait()
        // registers its continuation; repeated instant completions make that
        // interleaving effectively certain across the loop.
        let client = ScriptedAppleClient(outputs: Array(repeating: "OK", count: 50))
        let processor = AppleFoundationModelsPostProcessor(client: client)

        for _ in 0 ..< 50 {
            let output = try await processor.generate(
                instructions: "sys",
                userText: "user",
                config: makeConfig(timeoutSeconds: 5)
            )
            XCTAssertEqual(output, "OK")
        }
    }

    // MARK: - Unsupported client

    func testUnsupportedClientReportsUnsupportedRuntime() async {
        let client = UnsupportedAppleFoundationModelsClient()

        XCTAssertEqual(client.availability, .unsupportedSDKOrRuntime)

        do {
            _ = try await client.generate(instructions: "sys", prompt: "user", maxTokens: 8)
            XCTFail("Expected invalid configuration")
        } catch let error as LLMPostProcessorError {
            XCTAssertEqual(
                error.errorDescription,
                LLMPostProcessorError.invalidConfiguration("unsupported_sdk_or_runtime").errorDescription
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeConfig(timeoutSeconds: Double = 3) -> AppleMagicFormatConfig {
        AppleMagicFormatConfig(
            systemPrompt: "Clean dictation for Suniye.",
            keywords: ["Suniye"],
            timeoutSeconds: timeoutSeconds,
            maxTokens: 256
        )
    }
}

private final class ScriptedAppleClient: AppleFoundationModelsClient {
    var availability: AppleFoundationModelsAvailability
    private var outputs: [String]
    private let responseDelayNanoseconds: UInt64
    private(set) var recordedInstructions: [String] = []
    private(set) var recordedPrompts: [String] = []

    init(
        availability: AppleFoundationModelsAvailability = .available,
        outputs: [String],
        responseDelayNanoseconds: UInt64 = 0
    ) {
        self.availability = availability
        self.outputs = outputs
        self.responseDelayNanoseconds = responseDelayNanoseconds
    }

    func waitUntilGenerateStarted() async {
        for _ in 0 ..< 500 where recordedPrompts.isEmpty {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func generate(instructions: String, prompt: String, maxTokens: Int) async throws -> String {
        recordedInstructions.append(instructions)
        recordedPrompts.append(prompt)
        if responseDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: responseDelayNanoseconds)
        }
        guard !outputs.isEmpty else {
            return ""
        }
        return outputs.removeFirst()
    }
}

private final class ThrowingAppleClient: AppleFoundationModelsClient {
    var availability: AppleFoundationModelsAvailability = .available
    private let error: Error

    init(error: Error) {
        self.error = error
    }

    func generate(instructions: String, prompt: String, maxTokens: Int) async throws -> String {
        throw error
    }
}
