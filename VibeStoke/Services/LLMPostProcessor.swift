import Foundation

struct LLMConfig: Equatable {
    let modelId: String
    let systemPrompt: String
    let keywords: [String]
    let timeoutSeconds: Double
    let maxTokens: Int
    let apiKey: String
}

protocol LLMPostProcessor {
    func polish(text: String, config: LLMConfig) async throws -> String
}

enum LLMPostProcessorError: LocalizedError {
    case invalidConfiguration(String)
    case timeout
    case unauthorized
    case provider(String)
    case malformedResponse
    case emptyOutput
    case network(String)

    var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(reason):
            return "Invalid LLM configuration: \(reason)"
        case .timeout:
            return "LLM request timed out"
        case .unauthorized:
            return "OpenRouter authorization failed"
        case let .provider(reason):
            return "OpenRouter provider error: \(reason)"
        case .malformedResponse:
            return "OpenRouter returned malformed response"
        case .emptyOutput:
            return "LLM returned empty output"
        case let .network(reason):
            return "Network error: \(reason)"
        }
    }
}
