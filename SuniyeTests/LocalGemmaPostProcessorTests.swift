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

    func testGemmaInstructionsUseSharedFormattingIntentPolicy() async throws {
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
        XCTAssertTrue(client.instructions.first?.contains("Formatting intent detected") == true)
        XCTAssertTrue(client.instructions.first?.contains("Preserve that lead-in") == true)
        XCTAssertFalse(client.instructions.first?.contains("Return exactly this structure") == true)
    }

    func testGemmaAcceptsThingsListLeadIn() async throws {
        let client = FakeLocalGemmaClient(outputs: [
            "The things we need are:\n- Laptop\n- Bag\n- Phone\n- Charger",
        ])
        let processor = LocalGemmaPostProcessor(client: client)

        let output = try await processor.polish(
            text: "The things we need are laptop, bag, phone, and charger.",
            config: makeConfig()
        )

        XCTAssertEqual(output, "The things we need are:\n- Laptop\n- Bag\n- Phone\n- Charger")
        XCTAssertTrue(client.instructions.first?.contains("Formatting intent detected") == true)
        XCTAssertTrue(client.instructions.first?.contains("Preserve that lead-in") == true)
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
        let arguments = LocalGemmaDefaults.serverArguments(modelPath: "/tmp/model.gguf", port: 51_234, apiKey: "local-key")

        XCTAssertEqual(arguments.first, "--model")
        XCTAssertTrue(arguments.contains("/tmp/model.gguf"))
        XCTAssertTrue(arguments.contains("51234"))
        XCTAssertTrue(arguments.contains("--reasoning"))
        XCTAssertTrue(arguments.contains("off"))
        XCTAssertTrue(arguments.contains("--api-key"))
        XCTAssertTrue(arguments.contains("local-key"))
        XCTAssertTrue(arguments.contains("--no-webui"))
    }

    func testCompletionRequestsIncludeBearerAuth() throws {
        let endpoint = LocalGemmaServerEndpoint(
            baseURL: URL(string: "http://127.0.0.1:51234")!,
            apiKey: "secret-local-key"
        )

        let request = try LocalGemmaCompletionRequestFactory.makeRequest(
            endpoint: endpoint,
            instructions: "Clean text.",
            prompt: "<transcript>raw</transcript>",
            maxTokens: 64,
            modelName: "Gemma",
            timeoutSeconds: 3
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-local-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:51234/v1/chat/completions")
    }

    func testPolishPassesConfiguredIdleTimeoutToClient() async throws {
        let client = FakeLocalGemmaClient(outputs: ["polished text"])
        let processor = LocalGemmaPostProcessor(client: client)

        _ = try await processor.polish(
            text: "raw text",
            config: makeConfig(idleTimeoutSeconds: 900)
        )

        XCTAssertEqual(client.idleTimeouts.first, 900)
    }

    func testPrewarmOnColdRuntimeTriggersGeneration() async {
        let client = FakeLocalGemmaClient(runtimeWarm: false, outputs: ["OK"])
        let processor = LocalGemmaPostProcessor(client: client)

        await processor.prewarm(config: makeConfig(idleTimeoutSeconds: 900))

        XCTAssertEqual(client.callCount, 1)
        XCTAssertEqual(client.maxTokens.first, LocalGemmaDefaults.prewarmMaxTokens)
        XCTAssertEqual(client.idleTimeouts.first, 900)
    }

    func testPrewarmSkipsWhenRuntimeAlreadyWarm() async {
        let client = FakeLocalGemmaClient(runtimeWarm: true, outputs: ["OK"])
        let processor = LocalGemmaPostProcessor(client: client)

        await processor.prewarm(config: makeConfig())

        XCTAssertEqual(client.callCount, 0)
    }

    func testPrewarmSkipsWhenUnavailable() async {
        let client = FakeLocalGemmaClient(availability: .modelNotInstalled, outputs: ["OK"])
        let processor = LocalGemmaPostProcessor(client: client)

        await processor.prewarm(config: makeConfig())

        XCTAssertEqual(client.callCount, 0)
    }

    func testPrewarmSwallowsGenerationErrors() async {
        let client = FakeLocalGemmaClient(runtimeWarm: false, outputs: [])
        let processor = LocalGemmaPostProcessor(client: client)

        // No output configured -> generate throws; prewarm must not propagate it.
        await processor.prewarm(config: makeConfig())

        XCTAssertEqual(client.callCount, 1)
    }

    private func makeConfig(idleTimeoutSeconds: Double = 600) -> LocalGemmaMagicFormatConfig {
        LocalGemmaMagicFormatConfig(
            systemPrompt: LLMDefaults.defaultGemmaMagicFormatPrompt,
            keywords: [],
            startupTimeoutSeconds: 0.1,
            generationTimeoutSeconds: 0.1,
            idleTimeoutSeconds: idleTimeoutSeconds,
            maxTokens: 128
        )
    }
}

private final class FakeLocalGemmaClient: LocalGemmaClient {
    var availability: LocalGemmaAvailability
    var runtimeWarm: Bool
    private let outputs: [String]
    private(set) var callCount = 0
    private(set) var instructions: [String] = []
    private(set) var prompts: [String] = []
    private(set) var maxTokens: [Int] = []
    private(set) var idleTimeouts: [Double] = []

    init(availability: LocalGemmaAvailability = .available, runtimeWarm: Bool = false, outputs: [String]) {
        self.availability = availability
        self.runtimeWarm = runtimeWarm
        self.outputs = outputs
    }

    func isRuntimeWarm() async -> Bool {
        runtimeWarm
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
        self.maxTokens.append(maxTokens)
        idleTimeouts.append(idleTimeoutSeconds)
        let index = callCount
        callCount += 1
        guard index < outputs.count else {
            throw LLMPostProcessorError.emptyOutput
        }
        return outputs[index]
    }
}
