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

struct LocalGemmaMagicFormatConfig: Equatable {
    let systemPrompt: String
    let keywords: [String]
    let startupTimeoutSeconds: Double
    let generationTimeoutSeconds: Double
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

protocol LocalGemmaMagicFormatPostProcessor {
    var availability: LocalGemmaAvailability { get }
    func polish(text: String, config: LocalGemmaMagicFormatConfig) async throws -> String
    func testSetup(config: LocalGemmaMagicFormatConfig) async throws
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

enum LocalGemmaAvailability: Equatable {
    case available
    case runtimeUnavailable
    case modelNotInstalled

    var isAvailable: Bool {
        self == .available
    }

    var statusText: String {
        switch self {
        case .available:
            return "Gemma 4 Q4 ready."
        case .runtimeUnavailable:
            return "Local Gemma runtime is not available."
        case .modelNotInstalled:
            return "Local Gemma 4 Q4 model is not available."
        }
    }

    var logValue: String {
        switch self {
        case .available:
            return "available"
        case .runtimeUnavailable:
            return "runtime_unavailable"
        case .modelNotInstalled:
            return "model_not_installed"
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

        if hasLikelyItemListLeadIn(for: lowercased) {
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

    static func hasLikelyItemListLeadIn(for input: String) -> Bool {
        let lowercased = input.lowercased()
        guard containsWord("items", in: lowercased) else {
            return false
        }
        return lowercased.contains(":") || lowercased.contains(",") || lowercased.contains(" and ")
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

enum MagicFormatPromptComposer {
    static func makeInstructions(
        systemPrompt: String,
        keywords: [String],
        text: String,
        retrying: Bool
    ) -> String {
        var sections = [systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)]

        if !keywords.isEmpty {
            sections.append("Vocabulary terms to preserve exactly when present: \(keywords.joined(separator: ", ")).")
        }

        if MagicFormatOutputSanitizer.allowsMultilineOutput(for: text) {
            if MagicFormatOutputSanitizer.hasLikelyItemListLeadIn(for: text) {
                sections.append("""
                Formatting intent detected: this transcript is an item list with a user-provided lead-in before the item run. Return exactly this structure: first line = the cleaned lead-in ending with a colon; following lines = one bullet per item.

                Do not return only bullets. If the transcript has no colon, infer the lead-in from the words before the item run and remove separator noise before the first item. Use plain hyphen bullets for unordered item lists, including "list of ..." requests where items are separated by commas, pauses, or "and". Use numbered lines only for ordered actions, steps, or explicit numbered lists. Correct obvious ASR item-word errors only when the surrounding items make the intended object clear. Do not invent extra items.

                Example:
                <transcript>these are the supplies we need for pens comma paper comma tape</transcript>
                These are the supplies we need:
                - Pens
                - Paper
                - Tape
                """)
            } else {
                sections.append("Formatting intent detected: return a plain-text multi-line list with one item per line. Use plain hyphen bullets for unordered item lists. Use numbered lines only for ordered actions, steps, or explicit numbered lists. Do not add headings or extra items.")
            }
        }

        if retrying {
            if MagicFormatOutputSanitizer.allowsMultilineOutput(for: text) {
                sections.append("Retry correction: return only the cleaned transcript text as a plain-text list. Do not add wrapper text, markdown, quotes around the answer, or extra commentary.")
            } else {
                sections.append("Retry correction: return only the cleaned transcript text. One line. Do not add wrapper text, markdown, quotes around the answer, or extra commentary.")
            }
        }

        return sections
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}
