import XCTest
@testable import Suniye

final class AppleFoundationModelsPostProcessorTests: XCTestCase {
    func testPolishReturnsValidSanitizedOutput() async throws {
        let client = FakeAppleFoundationModelsClient(outputs: ["Output: Final text."])
        let processor = AppleFoundationModelsPostProcessor(client: client)

        let output = try await processor.polish(text: " raw text ", config: makeConfig())

        XCTAssertEqual(output, "Final text.")
        XCTAssertEqual(client.prompts.first, "<transcript>\nraw text\n</transcript>")
        XCTAssertTrue(client.instructions.first?.contains("Suniye") == true)
    }

    func testInvalidOutputRetriesOnce() async throws {
        let client = FakeAppleFoundationModelsClient(outputs: [
            "Sure, here is the cleaned text:\n\nFinal text.",
            "Final text.",
        ])
        let processor = AppleFoundationModelsPostProcessor(client: client)

        let output = try await processor.polish(text: "raw text", config: makeConfig())

        XCTAssertEqual(output, "Final text.")
        XCTAssertEqual(client.callCount, 2)
        XCTAssertTrue(client.instructions.last?.contains("Retry correction") == true)
    }

    func testLegitimateSentenceStartersAreAccepted() async throws {
        let client = FakeAppleFoundationModelsClient(outputs: [
            "Sure, let's do that.",
            "Here is the update.",
            "Sorry, I cannot make it today.",
        ])
        let processor = AppleFoundationModelsPostProcessor(client: client)

        let sureOutput = try await processor.polish(text: "sure let's do that", config: makeConfig())
        let hereOutput = try await processor.polish(text: "here is the update", config: makeConfig())
        let sorryOutput = try await processor.polish(text: "sorry I cannot make it today", config: makeConfig())

        XCTAssertEqual(sureOutput, "Sure, let's do that.")
        XCTAssertEqual(hereOutput, "Here is the update.")
        XCTAssertEqual(sorryOutput, "Sorry, I cannot make it today.")
        XCTAssertEqual(client.callCount, 3)
    }

    func testSingleLinePreambleLeadInRetries() async throws {
        let client = FakeAppleFoundationModelsClient(outputs: [
            "Here is the cleaned text: Final text.",
            "Final text.",
        ])
        let processor = AppleFoundationModelsPostProcessor(client: client)

        let output = try await processor.polish(text: "raw text", config: makeConfig())

        XCTAssertEqual(output, "Final text.")
        XCTAssertEqual(client.callCount, 2)
    }

    func testInvalidOutputAfterRetryThrowsMalformedResponse() async {
        let client = FakeAppleFoundationModelsClient(outputs: [
            "Sure, here is the cleaned text:\n\nCleaned text.",
            "<transcript>Cleaned text.</transcript>",
        ])
        let processor = AppleFoundationModelsPostProcessor(client: client)

        do {
            _ = try await processor.polish(text: "raw text", config: makeConfig())
            XCTFail("Expected malformed response")
        } catch let error as LLMPostProcessorError {
            XCTAssertEqual(error.errorDescription, LLMPostProcessorError.malformedResponse.errorDescription)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testUnavailableClientThrowsInvalidConfiguration() async {
        let client = FakeAppleFoundationModelsClient(
            availability: .appleIntelligenceNotEnabled,
            outputs: ["Final text."]
        )
        let processor = AppleFoundationModelsPostProcessor(client: client)

        do {
            _ = try await processor.polish(text: "raw text", config: makeConfig())
            XCTFail("Expected invalid configuration")
        } catch let error as LLMPostProcessorError {
            XCTAssertEqual(error.errorDescription, LLMPostProcessorError.invalidConfiguration("apple_intelligence_not_enabled").errorDescription)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTimeoutMapsToLLMTimeout() async {
        let client = FakeAppleFoundationModelsClient(
            outputs: ["Final text."],
            responseDelayNanoseconds: 100_000_000
        )
        let processor = AppleFoundationModelsPostProcessor(client: client)

        do {
            _ = try await processor.polish(text: "raw text", config: makeConfig(timeoutSeconds: 0.01))
            XCTFail("Expected timeout")
        } catch let error as LLMPostProcessorError {
            XCTAssertEqual(error.errorDescription, LLMPostProcessorError.timeout.errorDescription)
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

private final class FakeAppleFoundationModelsClient: AppleFoundationModelsClient {
    var availability: AppleFoundationModelsAvailability
    private var outputs: [String]
    private let responseDelayNanoseconds: UInt64
    private(set) var instructions: [String] = []
    private(set) var prompts: [String] = []

    init(
        availability: AppleFoundationModelsAvailability = .available,
        outputs: [String],
        responseDelayNanoseconds: UInt64 = 0
    ) {
        self.availability = availability
        self.outputs = outputs
        self.responseDelayNanoseconds = responseDelayNanoseconds
    }

    var callCount: Int {
        prompts.count
    }

    func generate(instructions: String, prompt: String, maxTokens: Int) async throws -> String {
        if responseDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: responseDelayNanoseconds)
        }
        self.instructions.append(instructions)
        prompts.append(prompt)
        if outputs.isEmpty {
            return ""
        }
        return outputs.removeFirst()
    }
}
