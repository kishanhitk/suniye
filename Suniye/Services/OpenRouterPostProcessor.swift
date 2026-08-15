import Foundation

final class OpenRouterPostProcessor: LLMPostProcessor {
    private let client: ChatCompletionClient

    init(session: URLSession = .shared) {
        self.client = ChatCompletionClient(session: session)
    }

    func polish(text: String, config: LLMConfig) async throws -> String {
        try validateConfig(config)

        return try await MagicFormatPipeline.polish(
            text: text,
            systemPrompt: config.systemPrompt,
            keywords: config.keywords
        ) { request in
            try await client.complete(
                endpointURL: config.endpointURL,
                apiKey: config.apiKey,
                payload: makePayload(
                    modelId: config.modelId,
                    instructions: request.instructions,
                    inputText: request.prompt,
                    maxTokens: request.maxTokens
                ),
                timeoutSeconds: config.timeoutSeconds
            ).text
        }
    }

    func generate(instructions: String, userText: String, config: LLMConfig) async throws -> String {
        try validateConfig(config)
        let output = try await client.complete(
            endpointURL: config.endpointURL,
            apiKey: config.apiKey,
            payload: makePayload(
                modelId: config.modelId,
                instructions: instructions,
                inputText: userText,
                maxTokens: LLMDefaults.editModeMaxTokens
            ),
            timeoutSeconds: config.timeoutSeconds
        ).text
        let sanitized = sanitizeOutput(output)
        guard !sanitized.isEmpty else {
            throw LLMPostProcessorError.emptyOutput
        }
        return sanitized
    }

    func testSetup(config: LLMConfig) async throws {
        try validateConfig(config)
        let output = try await client.complete(
            endpointURL: config.endpointURL,
            apiKey: config.apiKey,
            payload: makeSetupPayload(config: config),
            timeoutSeconds: config.timeoutSeconds
        ).text
        let sanitized = sanitizeOutput(output)
        guard !sanitized.isEmpty else {
            throw LLMPostProcessorError.emptyOutput
        }
    }

    private func validateConfig(_ config: LLMConfig) throws {
        guard LLMDefaults.isValidModelId(config.modelId) else {
            throw LLMPostProcessorError.invalidConfiguration("model_id")
        }
        guard !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMPostProcessorError.invalidConfiguration("api_key")
        }
    }

    private func makePayload(modelId: String, instructions: String, inputText: String, maxTokens: Int?) -> ChatCompletionPayload {
        let messages = [
            ChatCompletionMessage(role: "system", content: instructions),
            ChatCompletionMessage(role: "user", content: inputText),
        ]

        return ChatCompletionPayload(model: modelId, messages: messages, maxTokens: maxTokens)
    }

    private func makeSetupPayload(config: LLMConfig) -> ChatCompletionPayload {
        let instructions = [
            config.systemPrompt,
            "For this setup test, reply with OK.",
        ]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        return makePayload(
            modelId: config.modelId,
            instructions: instructions,
            inputText: "Connection test.",
            maxTokens: nil
        )
    }

    func sanitizeOutput(_ raw: String) -> String {
        MagicFormatOutputSanitizer.sanitize(raw)
    }
}
