import Foundation

final class OpenRouterPostProcessor: LLMPostProcessor {
    private let client: ChatCompletionClient

    init(session: URLSession = .shared) {
        self.client = ChatCompletionClient(session: session)
    }

    func polish(text: String, config: LLMConfig) async throws -> String {
        try await Generator(client: client, config: config).polish(
            text: text,
            systemPrompt: config.systemPrompt,
            keywords: config.keywords,
            timeoutFloorSeconds: config.timeoutSeconds
        )
    }

    func generate(instructions: String, userText: String, config: LLMConfig) async throws -> String {
        try await Generator(client: client, config: config).rewrite(
            instructions: instructions,
            userText: userText,
            timeoutFloorSeconds: config.timeoutSeconds
        )
    }

    /// A length stop still passes: only an empty answer fails the test.
    func testSetup(config: LLMConfig) async throws {
        let generator = Generator(client: client, config: config)
        try generator.checkReady()
        let instructions = [
            config.systemPrompt,
            "For this setup test, reply with OK.",
        ]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        let output = try await generator.generation(
            for: MagicFormatGenerationRequest(instructions: instructions, prompt: "Connection test."),
            timeoutSeconds: config.timeoutSeconds
        ).text
        _ = try generator.requireOutput(output)
    }

    func sanitizeOutput(_ raw: String) -> String {
        MagicFormatOutputSanitizer.sanitize(raw)
    }

    /// Lets a cancel through as `CancellationError`.
    private struct Generator: MagicFormatGenerator {
        let client: ChatCompletionClient
        let config: LLMConfig

        var usesSingleTurnPrompt: Bool { false }

        func checkReady() throws {
            guard LLMDefaults.isValidModelId(config.modelId) else {
                throw LLMPostProcessorError.invalidConfiguration("model_id")
            }
            guard !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LLMPostProcessorError.invalidConfiguration("api_key")
            }
        }

        func sanitize(_ raw: String) -> String {
            MagicFormatOutputSanitizer.sanitize(raw)
        }

        func generation(for request: MagicFormatGenerationRequest, timeoutSeconds: Double) async throws -> ChatCompletionResult {
            let payload = ChatCompletionPayload(
                model: config.modelId,
                messages: [
                    ChatCompletionMessage(role: "system", content: request.instructions),
                    ChatCompletionMessage(role: "user", content: request.prompt),
                ]
            )
            do {
                return try await client.complete(
                    endpointURL: config.endpointURL,
                    apiKey: config.apiKey,
                    payload: payload,
                    timeoutSeconds: timeoutSeconds
                )
            } catch let error as ChatCompletionError {
                throw LLMPostProcessorError(error)
            }
        }
    }
}
