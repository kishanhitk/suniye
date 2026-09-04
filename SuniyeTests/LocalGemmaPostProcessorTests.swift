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
        XCTAssertEqual(client.prompts.first, "<transcript>\n\(LocalGemmaDefaults.probeText)\n</transcript>")
    }

    /// The probe exists to fill llama-server's prompt cache; that only works if it
    /// sends the same instructions a real polish sends. For matched (single-line,
    /// no-keyword) inputs the two must be byte-identical, which is the strongest
    /// form of the shared-prefix guarantee.
    func testProbeBuildsIdenticalInstructionsToPolish() async throws {
        let client = FakeLocalGemmaClient(outputs: ["OK", "polished text"])
        let processor = LocalGemmaPostProcessor(client: client)
        let config = makeConfig()

        await processor.prewarm(config: config)
        _ = try await processor.polish(text: "raw text", config: config)

        XCTAssertEqual(client.callCount, 2)
        XCTAssertEqual(client.instructions[0], client.instructions[1])
        XCTAssertTrue(client.instructions[0].hasPrefix(LLMDefaults.defaultGemmaMagicFormatPrompt))
    }

    func testGenerationTimingsReportedForPolishAndRewriteButNotProbe() async throws {
        let timings = ChatCompletionTimings(promptTokens: 38, cachedTokens: 2439, predictedTokens: 31, prefillMs: 94, decodeMs: 489)
        let client = FakeLocalGemmaClient(outputs: ["OK", "polished text", "rewritten"], timings: timings)
        var reported: [ChatCompletionTimings] = []
        let processor = LocalGemmaPostProcessor(client: client) { reported.append($0) }
        let config = makeConfig()

        await processor.prewarm(config: config)
        XCTAssertTrue(reported.isEmpty, "the warm-up probe must not report as a user-facing generation")

        _ = try await processor.polish(text: "raw text", config: config)
        _ = try await processor.generate(instructions: "make it formal", userText: "hey", config: config)

        XCTAssertEqual(client.callCount, 3)
        XCTAssertEqual(reported, [timings, timings])
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
        XCTAssertEqual(client.maxTokens.first, LocalGemmaDefaults.probeMaxTokens)
        XCTAssertEqual(client.idleTimeouts.first, 900)
    }

    /// A warm process is not a primed cache: an Edit Mode rewrite in between leaves
    /// the single slot holding a different prompt, so the probe must run regardless.
    func testPrewarmProbesEvenWhenRuntimeAlreadyWarm() async {
        let client = FakeLocalGemmaClient(runtimeWarm: true, outputs: ["OK"])
        let processor = LocalGemmaPostProcessor(client: client)

        await processor.prewarm(config: makeConfig())

        XCTAssertEqual(client.callCount, 1)
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

    func testPrewarmAbortsPromptlyWhenCanceled() async {
        let client = FakeLocalGemmaClient(runtimeWarm: false, blocksUntilCanceled: true, outputs: ["OK"])
        let processor = LocalGemmaPostProcessor(client: client)

        let prewarm = Task {
            await processor.prewarm(config: makeConfig())
        }
        await client.waitUntilGenerateStarted()
        prewarm.cancel()

        // Must unblock without hanging or throwing into the caller — and the
        // cancellation must actually reach the in-flight generation, not just
        // let it run to completion.
        await prewarm.value
        XCTAssertEqual(client.callCount, 1)
        XCTAssertTrue(client.generateWasCanceled)
    }

    private func makeConfig(idleTimeoutSeconds: Double = 600) -> LocalGemmaMagicFormatConfig {
        LocalGemmaMagicFormatConfig(
            systemPrompt: LLMDefaults.defaultGemmaMagicFormatPrompt,
            keywords: [],
            startupTimeoutSeconds: 0.1,
            generationTimeoutSeconds: 0.1,
            idleTimeoutSeconds: idleTimeoutSeconds
        )
    }
}

private final class FakeLocalGemmaClient: LocalGemmaClient {
    var availability: LocalGemmaAvailability
    var runtimeWarm: Bool
    private let blocksUntilCanceled: Bool
    private let outputs: [String]
    private let timings: ChatCompletionTimings?
    private(set) var callCount = 0
    private(set) var instructions: [String] = []
    private(set) var prompts: [String] = []
    private(set) var maxTokens: [Int?] = []
    private(set) var idleTimeouts: [Double] = []
    private(set) var generateWasCanceled = false

    init(
        availability: LocalGemmaAvailability = .available,
        runtimeWarm: Bool = false,
        blocksUntilCanceled: Bool = false,
        outputs: [String],
        timings: ChatCompletionTimings? = nil
    ) {
        self.availability = availability
        self.runtimeWarm = runtimeWarm
        self.blocksUntilCanceled = blocksUntilCanceled
        self.outputs = outputs
        self.timings = timings
    }

    func isRuntimeWarm() async -> Bool {
        runtimeWarm
    }

    func waitUntilGenerateStarted() async {
        // Bounded poll: a hang here fails the test at its assertion instead of
        // suspending the suite on an unresumed continuation.
        for _ in 0 ..< 500 where callCount == 0 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func generate(
        instructions: String,
        prompt: String,
        maxTokens: Int?,
        startupTimeoutSeconds: Double,
        idleTimeoutSeconds: Double,
        timeoutSeconds: Double
    ) async throws -> ChatCompletionResult {
        self.instructions.append(instructions)
        prompts.append(prompt)
        self.maxTokens.append(maxTokens)
        idleTimeouts.append(idleTimeoutSeconds)
        let index = callCount
        callCount += 1
        if blocksUntilCanceled {
            // Mirrors the real client's cooperative cancellation: throws when canceled.
            do {
                try await Task.sleep(nanoseconds: 10_000_000_000)
            } catch {
                generateWasCanceled = true
                throw error
            }
        }
        guard index < outputs.count else {
            throw LLMPostProcessorError.emptyOutput
        }
        return ChatCompletionResult(text: outputs[index], timings: timings, finishReason: nil)
    }
}
