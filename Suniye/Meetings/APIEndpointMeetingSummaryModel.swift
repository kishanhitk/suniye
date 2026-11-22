import Foundation
import SuniyeAnalytics

/// What a summary request to the user's API endpoint needs.
struct APIEndpointSummarySetup: Equatable {
    let endpointURL: URL
    let apiKey: String
    let modelID: String

    /// Nil unless there is a key and a model ID, and the endpoint's host is
    /// the one that the user agreed to send meeting text to. Magic Format
    /// shares the endpoint, so a later change of its host needs a new
    /// agreement.
    init?(settings: MeetingSettings, endpointURL: URL?, apiKey: String?) {
        guard let endpointURL,
              let host = endpointURL.host, host == settings.apiSummaryAgreedHost,
              let apiKey, !apiKey.isEmpty,
              let modelID = LLMDefaults.normalizedModelId(settings.apiSummaryModelID)
        else { return nil }
        self.endpointURL = endpointURL
        self.apiKey = apiKey
        self.modelID = modelID
    }
}

/// The user's OpenAI-compatible endpoint as a summary model. The transcript
/// and the notes leave the Mac.
struct APIEndpointMeetingSummaryModel: MeetingSummaryModel {
    /// A hosted model's answer starts after it read the whole prompt.
    static let generationFloorSeconds = 120.0

    let client: ChatCompletionClient
    /// Read for each request, so a change in Settings counts at once.
    let setup: () -> APIEndpointSummarySetup?

    var writesWholeSummary: Bool { true }

    func contextTokens() async -> Int {
        MeetingSummaryWriter.hostedContextTokens
    }

    func tokenCount(_ text: String) async -> Int? {
        nil
    }

    func generate(_ request: MeetingSummaryRequest) async throws -> String {
        guard let setup = setup() else {
            throw MeetingSummaryError.failed(.notSetUp)
        }
        // No `temperature` and no `max_tokens`: reasoning models refuse the
        // first, and count their reasoning in the second.
        let payload = ChatCompletionPayload(
            model: setup.modelID,
            messages: [
                ChatCompletionMessage(role: "system", content: request.instructions),
                ChatCompletionMessage(role: "user", content: request.input),
            ],
            temperature: nil
        )
        let result: ChatCompletionResult
        do {
            result = try await client.complete(
                endpointURL: setup.endpointURL,
                apiKey: setup.apiKey,
                payload: payload,
                timeoutSeconds: MagicFormatGenerationBudget.timeoutSeconds(
                    floor: Self.generationFloorSeconds,
                    inputCharacterCount: request.text.count
                )
            )
        } catch let error as ChatCompletionError {
            AppLogger.shared.log(.error, "meeting summary api request failed error=\(error.logValue)")
            throw MeetingSummaryError.failed(Self.failure(of: error))
        }
        guard result.finishReason != ChatCompletionResult.lengthStop else {
            throw MeetingSummaryError.failed(.truncated)
        }
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw MeetingSummaryError.failed(.empty)
        }
        return text
    }

    private static func failure(of error: ChatCompletionError) -> MeetingSummaryFailure {
        switch error {
        case .unauthorized:
            return .keyRejected
        case .network:
            return .network
        case .timeout:
            return .timeout
        case .provider, .malformedResponse:
            return .serviceError
        }
    }
}
