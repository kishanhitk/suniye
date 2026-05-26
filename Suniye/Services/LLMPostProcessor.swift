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
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isValidPlainText(_ output: String, for input: String) -> Bool {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }
        if trimmed.contains("```") {
            return false
        }

        let lowercased = trimmed.lowercased()
        if lowercased.contains("<transcript") || lowercased.contains("</transcript>") {
            return false
        }

        if trimmed.rangeOfCharacter(from: .newlines) != nil,
           !isValidMultilineOutput(trimmed, for: input) {
            return false
        }

        let inputLength = input.trimmingCharacters(in: .whitespacesAndNewlines).count
        let maxReasonableLength = max(inputLength * 3, inputLength + 240)
        if trimmed.count > maxReasonableLength {
            return false
        }

        return true
    }

    private static func isBoundary(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { !CharacterSet.alphanumerics.contains($0) }
    }

    private static func isValidMultilineOutput(_ output: String, for input: String) -> Bool {
        guard allowsMultilineOutput(for: input) else {
            return false
        }

        let lines = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard lines.count <= 20, lines.allSatisfy({ !$0.isEmpty }) else {
            return false
        }

        return true
    }

    static func allowsMultilineOutput(for input: String) -> Bool {
        let lowercased = input.lowercased()
        let phraseTriggers = [
            "new line",
            "new lines",
            "next line",
            "line break",
            "line breaks",
            "separate lines",
            "separate line",
            "bullet list",
            "bulleted list",
            "numbered list",
            "todo list",
            "to do list",
            "as a list",
            "make a list",
            "format as a list",
            "turn this into a list",
            "in order",
            "in an order",
            "ordered list",
            "ordered sequence",
        ]
        if phraseTriggers.contains(where: { lowercased.contains($0) }) {
            return true
        }

        if containsOrdinalSequence(in: lowercased) {
            return true
        }

        if containsWord("items", in: lowercased),
           lowercased.contains(":") || lowercased.contains(",") || lowercased.contains(" and ") {
            return true
        }

        let wordTriggers = [
            "list",
            "bullets",
            "bullet",
            "checklist",
            "steps",
            "agenda",
        ]
        return wordTriggers.contains { containsWord($0, in: lowercased) }
    }

    private static func containsOrdinalSequence(in text: String) -> Bool {
        let ordinalWords = [
            "first",
            "second",
            "third",
            "fourth",
            "fifth",
            "sixth",
            "seventh",
            "eighth",
            "ninth",
            "tenth",
        ]
        return ordinalWords.filter { containsWord($0, in: text) }.count >= 2
    }

    private static func containsWord(_ word: String, in text: String) -> Bool {
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let range = text.range(of: word, range: searchStart ..< text.endIndex) {
            let hasLeadingBoundary = range.lowerBound == text.startIndex || isBoundary(text[text.index(before: range.lowerBound)])
            let hasTrailingBoundary = range.upperBound == text.endIndex || isBoundary(text[range.upperBound])
            if hasLeadingBoundary && hasTrailingBoundary {
                return true
            }
            searchStart = range.upperBound
        }
        return false
    }
}
