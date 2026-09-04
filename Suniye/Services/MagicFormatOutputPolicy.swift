import Foundation

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

    private static func isValidMultilineOutput(_ output: String, for input: String) -> Bool {
        guard MagicFormatFormattingIntentDetector.detect(in: input).allowsMultiline else {
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
}

struct MagicFormatGenerationRequest {
    let instructions: String
    let prompt: String
}

enum MagicFormatPipeline {
    static func polish(
        text: String,
        systemPrompt: String,
        keywords: [String],
        singleTurn: Bool = false,
        sanitize: (String) -> String = MagicFormatOutputSanitizer.sanitize,
        generate: (MagicFormatGenerationRequest) async throws -> String
    ) async throws -> String {
        let trimmedInput = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
            throw LLMPostProcessorError.emptyOutput
        }

        var lastInvalidOutputWasEmpty = false
        for attempt in 0 ..< 2 {
            let request: MagicFormatGenerationRequest
            if singleTurn {
                // Fold the prompt and transcript into ONE user turn with no system
                // instructions and no <transcript> tags. The on-device Apple model
                // obeys transcript-embedded commands when the rules live in a separate
                // instruction channel; a single turn resists prompt injection. It also
                // tends to echo XML tags, so the transcript uses a plain delimiter.
                request = MagicFormatGenerationRequest(
                    instructions: "",
                    prompt: makeSingleTurnPrompt(
                        systemPrompt: systemPrompt,
                        keywords: keywords,
                        text: trimmedInput,
                        retrying: attempt > 0
                    )
                )
            } else {
                request = makeRequest(
                    text: trimmedInput,
                    systemPrompt: systemPrompt,
                    keywords: keywords,
                    retrying: attempt > 0
                )
            }

            let raw = try await generate(request)
            let sanitized = sanitize(raw)
            if MagicFormatOutputSanitizer.isValidPlainText(sanitized, for: trimmedInput) {
                return sanitized
            }
            lastInvalidOutputWasEmpty = sanitized.isEmpty
        }

        throw lastInvalidOutputWasEmpty ? LLMPostProcessorError.emptyOutput : LLMPostProcessorError.malformedResponse
    }

    /// The instruction-channel request shape (instructions + tagged transcript). Shared
    /// with the local Gemma warm-up probe so the probe fills llama-server's prompt cache
    /// with the same multi-thousand-token prefix a real polish will send.
    static func makeRequest(
        text: String,
        systemPrompt: String,
        keywords: [String],
        retrying: Bool
    ) -> MagicFormatGenerationRequest {
        MagicFormatGenerationRequest(
            instructions: MagicFormatPromptComposer.makeInstructions(
                systemPrompt: systemPrompt,
                keywords: keywords,
                text: text,
                retrying: retrying
            ),
            prompt: makePrompt(text: text)
        )
    }

    private static func makePrompt(text: String) -> String {
        """
        <transcript>
        \(text)
        </transcript>
        """
    }

    private static func makeSingleTurnPrompt(systemPrompt: String, keywords: [String], text: String, retrying: Bool) -> String {
        var head = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !keywords.isEmpty {
            head += "\n\nVocabulary terms to preserve exactly when present: \(keywords.joined(separator: ", "))."
        }
        if retrying {
            // The model is deterministic, so a byte-identical retry would just replay the
            // rejected output. Vary the second attempt with a correction directive.
            head += "\n\nYour previous answer was rejected. Return ONLY the cleaned transcript text on the fewest lines the transcript dictates — no preamble, no commentary, no <transcript> tags."
        }
        return """
        \(head)

        ===
        Dictated transcript to clean (output only the cleaned text):
        \(text)
        """
    }
}

enum MagicFormatFormattingIntent: Equatable {
    case singleLine
    case multilineList
    case multilineListWithLeadIn

    var allowsMultiline: Bool {
        switch self {
        case .singleLine:
            return false
        case .multilineList, .multilineListWithLeadIn:
            return true
        }
    }
}

enum MagicFormatFormattingIntentDetector {
    static func detect(in input: String) -> MagicFormatFormattingIntent {
        let lowercased = input.lowercased()
        if hasLikelyItemListLeadIn(for: lowercased) {
            return .multilineListWithLeadIn
        }

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
            return .multilineList
        }

        if containsOrdinalSequence(in: lowercased) {
            return .multilineList
        }

        let wordTriggers = [
            "list",
            "bullets",
            "bullet",
            "checklist",
            "steps",
            "agenda",
        ]
        if wordTriggers.contains(where: { containsWord($0, in: lowercased) }) {
            return .multilineList
        }

        return .singleLine
    }

    static func hasLikelyItemListLeadIn(for input: String) -> Bool {
        let lowercased = input.lowercased()
        let listLeadInNouns = [
            "items",
            "things",
        ]
        guard listLeadInNouns.contains(where: { containsWord($0, in: lowercased) }) else {
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

    private static func isBoundary(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { !CharacterSet.alphanumerics.contains($0) }
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
        let formattingIntent = MagicFormatFormattingIntentDetector.detect(in: text)

        if !keywords.isEmpty {
            sections.append("Vocabulary terms to preserve exactly when present: \(keywords.joined(separator: ", ")).")
        }

        switch formattingIntent {
        case .singleLine:
            break
        case .multilineListWithLeadIn:
            sections.append("""
            Formatting intent detected: this transcript appears to contain an item list with a user-provided lead-in. Preserve that lead-in as the first line ending with a colon, then return one bullet per item.

            Do not return only bullets. If the transcript has no explicit colon, infer the lead-in from the words before the item run and remove only separator noise before the first item. Use plain hyphen bullets for unordered item lists. Use numbered lines only for ordered actions, steps, or explicit numbered lists. Correct obvious item-word dictation errors only when the surrounding items make the intended object clear. Do not invent extra items.
            """)
        case .multilineList:
            sections.append("Formatting intent detected: return a plain-text multi-line list with one item per line. Use plain hyphen bullets for unordered item lists. Use numbered lines only for ordered actions, steps, or explicit numbered lists. Do not add headings or extra items.")
        }

        if retrying {
            if formattingIntent.allowsMultiline {
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
