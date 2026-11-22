import Foundation
import SuniyeAnalytics

/// The user's ChatGPT plan as a summary model. The transcript and the notes
/// go to OpenAI.
struct ChatGPTMeetingSummaryModel: MeetingSummaryModel {
    let client: ChatGPTPlanClient
    /// The model that the user chose, read for each request.
    let model: () -> String

    var writesWholeSummary: Bool { true }

    func contextTokens() async -> Int {
        MeetingSummaryWriter.hostedContextTokens
    }

    func tokenCount(_ text: String) async -> Int? {
        nil
    }

    func generate(_ request: MeetingSummaryRequest) async throws -> String {
        let text: String
        do {
            text = try await client.respond(model: model(), instructions: request.instructions, input: request.input)
        } catch let error as ChatGPTError {
            throw MeetingSummaryError.failed(MeetingSummaryFailure(error))
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MeetingSummaryError.failed(.empty)
        }
        return trimmed
    }
}

extension MeetingSummaryFailure {
    init(_ error: ChatGPTError) {
        switch error {
        case .signInEnded:
            self = .signInEnded
        case .planLimit:
            self = .planLimit
        case .planNotAllowed:
            self = .planNotAllowed
        case .network:
            self = .network
        case .timeout:
            self = .timeout
        case .service:
            self = .serviceError
        case .incomplete:
            self = .truncated
        }
    }
}
