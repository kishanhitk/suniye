import Foundation

struct LLMConfig: Equatable {
    let modelId: String
    let endpointURL: URL
    let systemPrompt: String
    let keywords: [String]
    let timeoutSeconds: Double
    let apiKey: String
}

struct AppleMagicFormatConfig: Equatable {
    let systemPrompt: String
    let keywords: [String]
    let timeoutSeconds: Double
    let maxTokens: Int
}

protocol LLMPostProcessor {
    func polish(text: String, config: LLMConfig) async throws -> String
    func testSetup(config: LLMConfig) async throws
}

protocol AppleMagicFormatPostProcessor {
    var availability: AppleFoundationModelsAvailability { get }
    func polish(text: String, config: AppleMagicFormatConfig) async throws -> String
    func testSetup(config: AppleMagicFormatConfig) async throws
}

enum AppleFoundationModelsAvailability: Equatable {
    case available
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unsupportedSDKOrRuntime

    var isAvailable: Bool {
        self == .available
    }

    var statusText: String {
        switch self {
        case .available:
            return "Apple Intelligence ready."
        case .deviceNotEligible:
            return "Apple Intelligence is not available on this Mac."
        case .appleIntelligenceNotEnabled:
            return "Turn on Apple Intelligence in System Settings."
        case .modelNotReady:
            return "Apple Intelligence model is downloading or preparing."
        case .unsupportedSDKOrRuntime:
            return "Apple Intelligence requires macOS 26 or newer."
        }
    }

    var logValue: String {
        switch self {
        case .available:
            return "available"
        case .deviceNotEligible:
            return "device_not_eligible"
        case .appleIntelligenceNotEnabled:
            return "apple_intelligence_not_enabled"
        case .modelNotReady:
            return "model_not_ready"
        case .unsupportedSDKOrRuntime:
            return "unsupported_sdk_or_runtime"
        }
    }
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
            return "LLM authorization failed"
        case let .provider(reason):
            return "LLM provider error: \(reason)"
        case .malformedResponse:
            return "LLM provider returned malformed response"
        case .emptyOutput:
            return "LLM returned empty output"
        case let .network(reason):
            return "Network error: \(reason)"
        }
    }
}

enum MagicFormatOutputSanitizer {
    static func sanitize(_ raw: String) -> String {
        var output = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if output.hasPrefix("```") {
            let lines = output.components(separatedBy: .newlines)
            let filtered = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }
            output = filtered.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let prefixes = ["output:", "polished:", "rewritten:", "text:"]
        for prefix in prefixes {
            if output.lowercased().hasPrefix(prefix),
               let range = output.range(of: ":") {
                output = String(output[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        return output
    }

    static func isValidPlainText(_ output: String, for input: String) -> Bool {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }
        if trimmed.contains("\n") || trimmed.contains("```") {
            return false
        }

        let lowercased = trimmed.lowercased()
        if lowercased.contains("<transcript") || lowercased.contains("</transcript>") {
            return false
        }

        let blockedPrefixes = [
            "sure",
            "here",
            "cleaned",
            "output",
            "the cleaned",
            "i can",
            "i cannot",
            "sorry",
        ]
        if blockedPrefixes.contains(where: { lowercased.hasPrefix($0) }) {
            return false
        }

        let inputLength = input.trimmingCharacters(in: .whitespacesAndNewlines).count
        let maxReasonableLength = max(inputLength * 3, inputLength + 240)
        if trimmed.count > maxReasonableLength {
            return false
        }

        return true
    }
}
