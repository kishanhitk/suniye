import Foundation

/// Wall-clock budget for one uncapped generation: the configured floor plus one
/// second per 80 input characters (~20 tokens, a slow Mac's decode rate), so a
/// legitimate long polish finishes and a runaway is still bounded near twice
/// the legitimate decode. Timing out falls back to the untouched input.
enum MagicFormatGenerationBudget {
    static func timeoutSeconds(floor: Double, inputCharacterCount: Int) -> Double {
        floor + Double(inputCharacterCount) / 80
    }
}

/// One Magic Format engine as the pipeline uses it: a ready check, its output
/// cleanup, and one generation request. The extension is the pipeline that
/// every engine shares: ready check first, request shape, time budget,
/// truncation check, sanitize and empty check.
protocol MagicFormatGenerator {
    /// The request puts the prompt and the transcript in one user turn.
    var usesSingleTurnPrompt: Bool { get }
    /// Throws `LLMPostProcessorError.invalidConfiguration` when the engine cannot run.
    func checkReady() throws
    func sanitize(_ raw: String) -> String
    /// Errors are `LLMPostProcessorError`, or `CancellationError` where the
    /// engine lets a cancel through.
    func generation(for request: MagicFormatGenerationRequest, timeoutSeconds: Double) async throws -> ChatCompletionResult
}

extension MagicFormatGenerator {
    func polish(text: String, systemPrompt: String, keywords: [String], timeoutFloorSeconds: Double) async throws -> String {
        try checkReady()
        let timeoutSeconds = MagicFormatGenerationBudget.timeoutSeconds(
            floor: timeoutFloorSeconds,
            inputCharacterCount: text.count
        )
        return try await MagicFormatPipeline.polish(
            text: text,
            systemPrompt: systemPrompt,
            keywords: keywords,
            singleTurn: usesSingleTurnPrompt,
            sanitize: sanitize
        ) { request in
            try await generation(for: request, timeoutSeconds: timeoutSeconds).untruncatedText
        }
    }

    /// Edit Mode: one freeform request, without the dictation output policy.
    func rewrite(instructions: String, userText: String, timeoutFloorSeconds: Double) async throws -> String {
        try checkReady()
        let generation = try await generation(
            for: MagicFormatGenerationRequest(instructions: instructions, prompt: userText),
            timeoutSeconds: MagicFormatGenerationBudget.timeoutSeconds(
                floor: timeoutFloorSeconds,
                inputCharacterCount: userText.count
            )
        )
        return try requireOutput(generation.untruncatedText)
    }

    /// The sanitized text; `emptyOutput` when nothing is left.
    func requireOutput(_ raw: String) throws -> String {
        let sanitized = sanitize(raw)
        guard !sanitized.isEmpty else {
            throw LLMPostProcessorError.emptyOutput
        }
        return sanitized
    }
}
