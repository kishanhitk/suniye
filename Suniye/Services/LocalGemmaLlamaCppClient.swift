import Foundation

final class LocalGemmaLlamaCppClient: LocalGemmaClient {
    private let locator: LocalGemmaRuntimeLocator
    private let server: LlamaServer

    init(
        locator: LocalGemmaRuntimeLocator = LocalGemmaRuntimeLocator(),
        server: LlamaServer = LlamaServer()
    ) {
        self.locator = locator
        self.server = server
    }

    var availability: LocalGemmaAvailability {
        switch locator.resolve() {
        case .success:
            return .available
        case let .failure(availability):
            return availability
        }
    }

    func isRuntimeWarm() async -> Bool {
        guard case let .success(runtime) = locator.resolve() else {
            return false
        }
        return await server.isWarm(for: runtime.launch)
    }

    func generate(
        instructions: String,
        prompt: String,
        maxTokens: Int?,
        sampling: LocalGemmaSampling,
        startupTimeoutSeconds: Double,
        idleTimeoutSeconds: Double,
        timeoutSeconds: Double
    ) async throws -> ChatCompletionResult {
        let runtime = try resolveRuntime()
        let result = try await mappingErrors {
            try await server.complete(
                LocalGemmaCompletionRequestFactory.makePayload(
                    instructions: instructions,
                    prompt: prompt,
                    maxTokens: maxTokens,
                    sampling: sampling,
                    modelName: runtime.model.displayName
                ),
                launch: runtime.launch,
                startupTimeoutSeconds: startupTimeoutSeconds,
                idleTimeoutSeconds: idleTimeoutSeconds,
                timeoutSeconds: timeoutSeconds
            )
        }
        // One line per generation (probe included): cached_tokens ≈ prompt_tokens of a
        // preceding probe proves the prewarm primed the KV cache; 0 means a full
        // prefill landed on the critical path.
        if let t = result.timings {
            AppLogger.shared.log(
                .info,
                "local gemma generation prompt_tokens=\(t.promptTokens) cached_tokens=\(t.cachedTokens) predicted_tokens=\(t.predictedTokens) prefill_ms=\(t.prefillMs) decode_ms=\(t.decodeMs)"
            )
        }
        return result
    }

    func tokenCount(_ text: String, startupTimeoutSeconds: Double, idleTimeoutSeconds: Double) async throws -> Int {
        let runtime = try resolveRuntime()
        return try await mappingErrors {
            try await server.tokenCount(
                text,
                launch: runtime.launch,
                startupTimeoutSeconds: startupTimeoutSeconds,
                idleTimeoutSeconds: idleTimeoutSeconds
            )
        }
    }

    func stopRuntime() async {
        await server.stop()
    }

    private func resolveRuntime() throws -> LocalGemmaRuntime {
        switch locator.resolve() {
        case let .success(runtime):
            return runtime
        case let .failure(availability):
            throw LLMPostProcessorError.invalidConfiguration(availability.logValue)
        }
    }

    private func mappingErrors<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as LlamaServerError {
            throw Self.postProcessorError(for: error)
        } catch let error as ChatCompletionError {
            throw LLMPostProcessorError(error)
        }
    }

    private static func postProcessorError(for error: LlamaServerError) -> LLMPostProcessorError {
        switch error {
        case .launchFailed:
            return .provider("server_start_failed")
        case let .exited(reason):
            return .provider(reason)
        case .startupTimedOut:
            return .timeout
        case .startupCanceled:
            return .provider("server_start_canceled")
        case .tokenizeFailed:
            return .provider("tokenize_failed")
        }
    }
}

enum LocalGemmaCompletionRequestFactory {
    static func makeRequest(
        endpoint: LlamaServerEndpoint,
        instructions: String,
        prompt: String,
        maxTokens: Int?,
        sampling: LocalGemmaSampling,
        modelName: String,
        timeoutSeconds: Double
    ) throws -> URLRequest {
        try ChatCompletionRequestFactory.makeRequest(
            endpointURL: endpoint.chatCompletionsURL,
            apiKey: endpoint.apiKey,
            payload: makePayload(
                instructions: instructions,
                prompt: prompt,
                maxTokens: maxTokens,
                sampling: sampling,
                modelName: modelName
            ),
            timeoutSeconds: timeoutSeconds
        )
    }

    static func makePayload(instructions: String, prompt: String, maxTokens: Int?, sampling: LocalGemmaSampling, modelName: String) -> ChatCompletionPayload {
        let userContent = """
        \(instructions)

        \(prompt)
        """

        return ChatCompletionPayload(
            model: modelName,
            messages: [ChatCompletionMessage(role: "user", content: userContent)],
            temperature: 0,
            topK: 1,
            topP: 1,
            maxTokens: maxTokens,
            stream: false,
            dryMultiplier: sampling == .greedyWithoutRepeats ? 0.8 : nil,
            dryPenaltyLastN: sampling == .greedyWithoutRepeats ? 256 : nil
        )
    }
}
