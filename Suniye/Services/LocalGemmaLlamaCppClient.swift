import Foundation

final class LocalGemmaLlamaCppClient: LocalGemmaClient {
    private let locator: LocalGemmaRuntimeLocator
    private let server: LlamaServer
    private let completionClient: ChatCompletionClient

    init(
        locator: LocalGemmaRuntimeLocator = LocalGemmaRuntimeLocator(),
        server: LlamaServer? = nil,
        session: URLSession = .shared,
        onModelLoad: (@Sendable (String, Int) -> Void)? = nil,
        onKeepAliveEvicted: (@Sendable (String) -> Void)? = nil
    ) {
        self.locator = locator
        self.server = server ?? LlamaServer(
            healthSession: session,
            onModelLoad: onModelLoad,
            onKeepAliveEvicted: onKeepAliveEvicted
        )
        self.completionClient = ChatCompletionClient(session: session)
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
        startupTimeoutSeconds: Double,
        idleTimeoutSeconds: Double,
        timeoutSeconds: Double
    ) async throws -> ChatCompletionResult {
        let runtime: LocalGemmaRuntime
        switch locator.resolve() {
        case let .success(resolved):
            runtime = resolved
        case let .failure(availability):
            throw LLMPostProcessorError.invalidConfiguration(availability.logValue)
        }

        // The cold-start `model_load` event is emitted inside the server actor's
        // `start()` success path — the actor serializes startup, so a real load
        // fires exactly one event with the true spawn+health latency, even when a
        // prewarm probe and a real request race for the same (shared) startup.
        let endpoint: LlamaServerEndpoint
        do {
            endpoint = try await server.endpoint(
                for: runtime.launch,
                startupTimeoutSeconds: startupTimeoutSeconds,
                idleTimeoutSeconds: idleTimeoutSeconds
            )
        } catch let error as LlamaServerError {
            throw Self.postProcessorError(for: error)
        }
        defer {
            Task {
                await server.scheduleIdleShutdown(after: idleTimeoutSeconds)
            }
        }

        // A canceled caller (prewarm probe preempted by a real request) must not
        // occupy the server's single generation slot; startup above is a shared
        // task and completes for the real caller regardless.
        try Task.checkCancellation()

        let result = try await completionClient.complete(
            endpointURL: endpoint.baseURL.appendingPathComponent("v1/chat/completions"),
            apiKey: endpoint.apiKey,
            payload: LocalGemmaCompletionRequestFactory.makePayload(
                instructions: instructions,
                prompt: prompt,
                maxTokens: maxTokens,
                modelName: runtime.model.displayName
            ),
            timeoutSeconds: timeoutSeconds
        )
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

    func stopRuntime() async {
        await server.stop()
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
        }
    }
}

enum LocalGemmaCompletionRequestFactory {
    static func makeRequest(
        endpoint: LlamaServerEndpoint,
        instructions: String,
        prompt: String,
        maxTokens: Int?,
        modelName: String,
        timeoutSeconds: Double
    ) throws -> URLRequest {
        try ChatCompletionRequestFactory.makeRequest(
            endpointURL: endpoint.baseURL.appendingPathComponent("v1/chat/completions"),
            apiKey: endpoint.apiKey,
            payload: makePayload(
                instructions: instructions,
                prompt: prompt,
                maxTokens: maxTokens,
                modelName: modelName
            ),
            timeoutSeconds: timeoutSeconds
        )
    }

    static func makePayload(instructions: String, prompt: String, maxTokens: Int?, modelName: String) -> ChatCompletionPayload {
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
            stream: false
        )
    }
}
