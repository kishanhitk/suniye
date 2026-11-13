import Foundation

/// The local model as a summary model. It takes the client that Magic Format
/// uses, so both run on one llama-server.
struct LocalGemmaMeetingSummaryModel: MeetingSummaryModel {
    /// A summary request can take minutes on a slow Mac: a long prefill, then
    /// up to `MeetingSummaryWriter.summaryOutputTokens` of output.
    static let generationFloorSeconds = 120.0

    let client: LocalGemmaClient

    var provider: MeetingSummaryProvider {
        .localModel
    }

    func contextTokens() async -> Int {
        LocalGemmaDefaults.contextSize
    }

    /// Nil when the server cannot count; the writer then estimates.
    func tokenCount(_ text: String) async -> Int? {
        try? await client.tokenCount(
            text,
            startupTimeoutSeconds: LocalGemmaDefaults.startupTimeoutSeconds,
            idleTimeoutSeconds: LocalGemmaDefaults.idleTimeoutSeconds
        )
    }

    func generate(_ request: MeetingSummaryRequest) async throws -> String {
        let result = try await client.generate(
            instructions: request.instructions,
            prompt: request.input,
            maxTokens: request.maxOutputTokens,
            startupTimeoutSeconds: LocalGemmaDefaults.startupTimeoutSeconds,
            idleTimeoutSeconds: LocalGemmaDefaults.idleTimeoutSeconds,
            timeoutSeconds: MagicFormatGenerationBudget.timeoutSeconds(
                floor: Self.generationFloorSeconds,
                inputCharacterCount: request.text.count
            )
        )
        let text = LocalGemmaPostProcessor.sanitize(try result.untruncatedText)
        guard !text.isEmpty else {
            throw LLMPostProcessorError.emptyOutput
        }
        return text
    }
}
