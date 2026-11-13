import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, *)
struct AppleMeetingSummaryModel: MeetingSummaryModel {
    private var model: SystemLanguageModel {
        SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
    }

    func contextTokens() async -> Int {
        model.contextSize
    }

    func tokenCount(_ text: String) async -> Int? {
        guard #available(macOS 26.4, *) else { return nil }
        return try? await model.tokenCount(for: text)
    }

    /// One prompt with no separate instructions: in the Magic Format evals,
    /// single-turn prompts resisted commands inside the transcript.
    func generate(_ request: MeetingSummaryRequest) async throws -> String {
        let session = LanguageModelSession(model: model)
        do {
            let response = try await session.respond(
                to: request.text,
                options: GenerationOptions(sampling: .greedy, temperature: 0)
            )
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let error as LanguageModelSession.GenerationError {
            if case .exceededContextWindowSize = error {
                throw LLMPostProcessorError.outputTruncated
            }
            throw error
        }
    }
}
#endif
