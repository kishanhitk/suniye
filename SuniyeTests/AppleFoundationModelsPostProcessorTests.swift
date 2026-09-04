import XCTest
@testable import Suniye

final class AppleFoundationModelsPostProcessorTests: XCTestCase {
    func testPolishReturnsTrimmedOutputWithoutStrippingPrefixes() async throws {
        let client = FakeAppleFoundationModelsClient(outputs: ["Output: Final text."])
        let processor = AppleFoundationModelsPostProcessor(client: client)

        let output = try await processor.polish(text: " raw text ", config: makeConfig())

        XCTAssertEqual(output, "Output: Final text.")
        XCTAssertEqual(client.instructions.first, "")
        XCTAssertTrue(client.prompts.first?.contains("raw text") == true)
        XCTAssertTrue(client.prompts.first?.contains("Suniye") == true)
        XCTAssertFalse(client.prompts.first?.contains("<transcript>") == true)
    }

    func testSingleTurnRequestFoldsPromptAndTranscriptWithoutTags() async throws {
        let client = FakeAppleFoundationModelsClient(outputs: ["Cleaned."])
        let processor = AppleFoundationModelsPostProcessor(client: client)

        _ = try await processor.polish(text: "hello world", config: makeConfig())

        // Apple runs single-turn: no separate instruction channel (which is what makes
        // the model resist transcript-embedded injection commands). The one user turn
        // carries the system prompt, a plain delimiter, and the raw transcript — never
        // <transcript> tags, which the model would otherwise echo.
        XCTAssertEqual(client.instructions.first, "")
        let prompt = try XCTUnwrap(client.prompts.first)
        XCTAssertTrue(prompt.contains("Clean dictation for Suniye."))
        XCTAssertTrue(prompt.contains("Dictated transcript to clean"))
        XCTAssertTrue(prompt.contains("hello world"))
        XCTAssertFalse(prompt.contains("<transcript>"))
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
        XCTAssertEqual(client.instructions.last, "")
        // The model is deterministic, so the retry must vary the prompt or it would
        // just replay the rejected output. Attempt 2 carries a correction directive.
        XCTAssertNotEqual(client.prompts.first, client.prompts.last)
        XCTAssertFalse(client.prompts.first?.contains("previous answer was rejected") == true)
        XCTAssertTrue(client.prompts.last?.contains("previous answer was rejected") == true)
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

    func testLiteralPreambleLikeUserTextIsAccepted() async throws {
        let client = FakeAppleFoundationModelsClient(outputs: [
            "Here is the cleaned text: Final text.",
        ])
        let processor = AppleFoundationModelsPostProcessor(client: client)

        let output = try await processor.polish(text: "raw text", config: makeConfig())

        XCTAssertEqual(output, "Here is the cleaned text: Final text.")
        XCTAssertEqual(client.callCount, 1)
    }

    func testRequestedBulletListOutputIsAccepted() async throws {
        let client = FakeAppleFoundationModelsClient(outputs: [
            "- Buy milk\n- Submit expenses\n- Call the dentist at 2 PM",
        ])
        let processor = AppleFoundationModelsPostProcessor(client: client)

        let output = try await processor.polish(
            text: "make this a bullet list buy milk submit expenses and call dentist at two",
            config: makeConfig()
        )

        XCTAssertEqual(output, "- Buy milk\n- Submit expenses\n- Call the dentist at 2 PM")
        XCTAssertEqual(client.callCount, 1)
        XCTAssertEqual(client.instructions.first, "")
        XCTAssertFalse(client.prompts.first?.contains("<transcript>") == true)
    }

    func testListOfCommaSeparatedItemsOutputIsAcceptedAndPromptedGenerically() async throws {
        let client = FakeAppleFoundationModelsClient(outputs: [
            "List of items to order:\n- Fan\n- Laptop\n- Book",
        ])
        let processor = AppleFoundationModelsPostProcessor(client: client)

        let output = try await processor.polish(
            text: "List of items to order: Fan, laptop, book.",
            config: makeConfig()
        )

        XCTAssertEqual(output, "List of items to order:\n- Fan\n- Laptop\n- Book")
        XCTAssertEqual(client.callCount, 1)
        XCTAssertEqual(client.instructions.first, "")
        XCTAssertFalse(client.prompts.first?.contains("<transcript>") == true)
    }

    func testListOfItemsSeparatedByAndOutputIsAcceptedAndPromptedGenerically() async throws {
        let client = FakeAppleFoundationModelsClient(outputs: [
            "List of items to order:\n- Fan\n- Laptop\n- Book",
        ])
        let processor = AppleFoundationModelsPostProcessor(client: client)

        let output = try await processor.polish(
            text: "List of items to order: fan laptop and book.",
            config: makeConfig()
        )

        XCTAssertEqual(output, "List of items to order:\n- Fan\n- Laptop\n- Book")
        XCTAssertEqual(client.callCount, 1)
        XCTAssertEqual(client.instructions.first, "")
    }

    func testListLeadInOutputIsAcceptedAndPromptedToPreserveLeadIn() async throws {
        let client = FakeAppleFoundationModelsClient(outputs: [
            "These are the items you should order:\n- Laptop\n- Bag\n- Phone\n- Charger",
        ])
        let processor = AppleFoundationModelsPostProcessor(client: client)

        let output = try await processor.polish(
            text: "These are the items you should have to order: laptop, bag, phone, charger.",
            config: makeConfig()
        )

        XCTAssertEqual(output, "These are the items you should order:\n- Laptop\n- Bag\n- Phone\n- Charger")
        XCTAssertEqual(client.callCount, 1)
        XCTAssertEqual(client.instructions.first, "")
    }

    func testNoColonListLeadInOutputIsAcceptedAndPromptedToPreserveLeadIn() async throws {
        let client = FakeAppleFoundationModelsClient(outputs: [
            "These are the items we should have:\n- Laptop\n- Back\n- Phone\n- Charger",
        ])
        let processor = AppleFoundationModelsPostProcessor(client: client)

        let output = try await processor.polish(
            text: "These are the items we should have on laptop, back, phone, charger.",
            config: makeConfig()
        )

        XCTAssertEqual(output, "These are the items we should have:\n- Laptop\n- Back\n- Phone\n- Charger")
        XCTAssertEqual(client.callCount, 1)
        XCTAssertEqual(client.instructions.first, "")
    }

    func testThingsListLeadInOutputIsAcceptedAndPromptedToPreserveLeadIn() async throws {
        let client = FakeAppleFoundationModelsClient(outputs: [
            "The things we need are:\n- Laptop\n- Bag\n- Phone\n- Charger",
        ])
        let processor = AppleFoundationModelsPostProcessor(client: client)

        let output = try await processor.polish(
            text: "The things we need are laptop, bag, phone, and charger.",
            config: makeConfig()
        )

        XCTAssertEqual(output, "The things we need are:\n- Laptop\n- Bag\n- Phone\n- Charger")
        XCTAssertEqual(client.callCount, 1)
        XCTAssertEqual(client.instructions.first, "")
    }

    func testRequestedNumberedStepsOutputIsAccepted() async throws {
        let client = FakeAppleFoundationModelsClient(outputs: [
            "1. Open Settings.\n2. Choose Magic Format.\n3. Select Apple Intelligence.",
        ])
        let processor = AppleFoundationModelsPostProcessor(client: client)

        let output = try await processor.polish(
            text: "numbered steps open settings choose magic format select apple intelligence",
            config: makeConfig()
        )

        XCTAssertEqual(output, "1. Open Settings.\n2. Choose Magic Format.\n3. Select Apple Intelligence.")
        XCTAssertEqual(client.callCount, 1)
    }

    func testOrderedFirstSecondOutputIsAccepted() async throws {
        let client = FakeAppleFoundationModelsClient(outputs: [
            "1. Create a Linear ticket.\n2. Create a git branch.",
        ])
        let processor = AppleFoundationModelsPostProcessor(client: client)

        let output = try await processor.polish(
            text: "do these things in an order first create a linear ticket second create a get a branch",
            config: makeConfig()
        )

        XCTAssertEqual(output, "1. Create a Linear ticket.\n2. Create a git branch.")
        XCTAssertEqual(client.callCount, 1)
        XCTAssertEqual(client.instructions.first, "")
        XCTAssertFalse(client.prompts.first?.contains("<transcript>") == true)
    }

    func testUnrequestedMultilineOutputRetries() async throws {
        let client = FakeAppleFoundationModelsClient(outputs: [
            "First line.\nSecond line.",
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
        // Budget is the 0.01 s floor plus 0.1 s for the 8-character input; the
        // fake answers well after that.
        let client = FakeAppleFoundationModelsClient(
            outputs: ["Final text."],
            responseDelayNanoseconds: 500_000_000
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
            timeoutSeconds: timeoutSeconds
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

    func generate(instructions: String, prompt: String) async throws -> String {
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
