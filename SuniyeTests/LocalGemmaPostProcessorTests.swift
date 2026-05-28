import XCTest
@testable import Suniye

final class LocalGemmaPostProcessorTests: XCTestCase {
    func testPolishReturnsTrimmedOutput() async throws {
        let client = FakeLocalGemmaClient(outputs: [" polished text "])
        let processor = LocalGemmaPostProcessor(client: client)

        let output = try await processor.polish(
            text: "raw text",
            config: makeConfig()
        )

        XCTAssertEqual(output, "polished text")
        XCTAssertEqual(client.callCount, 1)
    }

    func testControlTokensAreRemovedFromOutput() async throws {
        let client = FakeLocalGemmaClient(outputs: [
            "<|channel>thought\nthinking<channel|><|channel>final\nPolished text<end_of_turn>",
        ])
        let processor = LocalGemmaPostProcessor(client: client)

        let output = try await processor.polish(
            text: "raw text",
            config: makeConfig()
        )

        XCTAssertEqual(output, "Polished text")
    }

    func testGemmaInstructionsUseGenericPromptWithoutListHeuristics() async throws {
        let client = FakeLocalGemmaClient(outputs: [
            "These are the items we should have:\n- Laptop\n- Back\n- Phone\n- Charger",
        ])
        let processor = LocalGemmaPostProcessor(client: client)

        let output = try await processor.polish(
            text: "These are the items we should have on laptop, back, phone, charger.",
            config: makeConfig()
        )

        XCTAssertEqual(output, "These are the items we should have:\n- Laptop\n- Back\n- Phone\n- Charger")
        XCTAssertTrue(client.instructions.first?.contains("You clean one dictated transcript") == true)
        XCTAssertFalse(client.instructions.first?.contains("Formatting intent detected") == true)
        XCTAssertFalse(client.instructions.first?.contains("Return exactly this structure") == true)
    }

    func testInvalidOutputRetriesOnce() async throws {
        let client = FakeLocalGemmaClient(outputs: [
            "<transcript>raw text</transcript>",
            "polished text",
        ])
        let processor = LocalGemmaPostProcessor(client: client)

        let output = try await processor.polish(
            text: "raw text",
            config: makeConfig()
        )

        XCTAssertEqual(output, "polished text")
        XCTAssertEqual(client.callCount, 2)
        XCTAssertTrue(client.instructions.last?.contains("Retry correction") == true)
    }

    func testUnavailableClientThrowsInvalidConfiguration() async {
        let client = FakeLocalGemmaClient(availability: .modelNotInstalled, outputs: [])
        let processor = LocalGemmaPostProcessor(client: client)

        do {
            _ = try await processor.polish(text: "raw text", config: makeConfig())
            XCTFail("Expected invalid configuration")
        } catch let error as LLMPostProcessorError {
            XCTAssertEqual(error.errorDescription, LLMPostProcessorError.invalidConfiguration("model_not_installed").errorDescription)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSetupCallsClient() async throws {
        let client = FakeLocalGemmaClient(outputs: ["OK"])
        let processor = LocalGemmaPostProcessor(client: client)

        try await processor.testSetup(config: makeConfig())

        XCTAssertEqual(client.callCount, 1)
        XCTAssertEqual(client.prompts.first, "Connection test.")
    }

    func testServerArgumentsDisableReasoning() {
        let arguments = LocalGemmaDefaults.serverArguments(modelPath: "/tmp/model.gguf", port: 51_234)

        XCTAssertEqual(arguments.first, "--model")
        XCTAssertTrue(arguments.contains("/tmp/model.gguf"))
        XCTAssertTrue(arguments.contains("51234"))
        XCTAssertTrue(arguments.contains("--reasoning"))
        XCTAssertTrue(arguments.contains("off"))
    }

    private func makeConfig() -> LocalGemmaMagicFormatConfig {
        LocalGemmaMagicFormatConfig(
            systemPrompt: LLMDefaults.defaultGemmaMagicFormatPrompt,
            keywords: [],
            startupTimeoutSeconds: 0.1,
            generationTimeoutSeconds: 0.1,
            maxTokens: 128
        )
    }
}

private final class FakeLocalGemmaClient: LocalGemmaClient {
    var availability: LocalGemmaAvailability
    private let outputs: [String]
    private(set) var callCount = 0
    private(set) var instructions: [String] = []
    private(set) var prompts: [String] = []

    init(availability: LocalGemmaAvailability = .available, outputs: [String]) {
        self.availability = availability
        self.outputs = outputs
    }

    func generate(instructions: String, prompt: String, maxTokens: Int, timeoutSeconds: Double) async throws -> String {
        self.instructions.append(instructions)
        prompts.append(prompt)
        let index = callCount
        callCount += 1
        guard index < outputs.count else {
            throw LLMPostProcessorError.emptyOutput
        }
        return outputs[index]
    }
}
