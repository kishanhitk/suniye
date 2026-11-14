import Foundation

enum LocalGemmaDefaults {
    static let providerLogName = "local_gemma"
    static let modelID = LocalLLMModelCatalog.preferredModelID
    static let modelEntry = LocalLLMModelCatalog.entry(for: modelID)
    static let modelDisplayName = modelEntry.displayName
    static let modelRepository = modelEntry.repository
    static let modelFilename = modelEntry.filename
    static let expectedSizeText = modelEntry.expectedSizeText
    static let startupTimeoutSeconds = 90.0
    /// One budget for polish and Edit Mode: without an output cap the decode
    /// length is bounded only by the context window, the same bound both share.
    static let generationTimeoutSeconds = 30.0
    static let idleTimeoutSeconds = 600.0
    static let probeMaxTokens = 8
    static let probeText = "warm up"
    /// ~80 minutes of dictation. Gemma 4 E2B keeps full attention on 3 of its
    /// layers, so their KV cache is 96 MiB here (24 MiB at 4096) on top of a
    /// fixed 12 MiB sliding-window cache.
    static let contextSize = 16_384

    static func serverArguments(modelPath: String) -> [String] {
        return [
            "--model", modelPath,
            "--ctx-size", "\(contextSize)",
            "--parallel", "1",
            "--reasoning", "off",
        ]
    }
}

/// How the local model picks each token.
enum LocalGemmaSampling {
    /// The most likely token. Magic Format keeps the user's words, repeats
    /// included.
    case greedy
    /// The most likely token, with a penalty on a token that extends a repeat
    /// of the last 256 tokens: greedy decoding alone can write one note line
    /// again and again until the output limit.
    case greedyWithoutRepeats
}

protocol LocalGemmaClient {
    var availability: LocalGemmaAvailability { get }
    func isRuntimeWarm() async -> Bool
    /// `maxTokens` nil lets the model run to its end-of-turn or the context
    /// window.
    func generate(
        instructions: String,
        prompt: String,
        maxTokens: Int?,
        sampling: LocalGemmaSampling,
        startupTimeoutSeconds: Double,
        idleTimeoutSeconds: Double,
        timeoutSeconds: Double
    ) async throws -> ChatCompletionResult
    func tokenCount(_ text: String, startupTimeoutSeconds: Double, idleTimeoutSeconds: Double) async throws -> Int
    func stopRuntime() async
}

extension LocalGemmaClient {
    func isRuntimeWarm() async -> Bool { false }
    func stopRuntime() async {}

    func tokenCount(_ text: String, startupTimeoutSeconds: Double, idleTimeoutSeconds: Double) async throws -> Int {
        throw LLMPostProcessorError.invalidConfiguration("token_count_unsupported")
    }
}

final class LocalGemmaPostProcessor: LocalGemmaMagicFormatPostProcessor {
    private let client: LocalGemmaClient
    /// Fired with llama-server's counters after every user-facing generation
    /// (polish / Edit Mode rewrite) — never for the warm-up probe, whose full
    /// prefill is expected and would read as a cache miss. Analytics-only; may be nil.
    private let onGeneration: (@Sendable (ChatCompletionTimings) -> Void)?

    init(
        client: LocalGemmaClient = LocalGemmaLlamaCppClient(),
        onGeneration: (@Sendable (ChatCompletionTimings) -> Void)? = nil
    ) {
        self.client = client
        self.onGeneration = onGeneration
    }

    var availability: LocalGemmaAvailability {
        client.availability
    }

    func isRuntimeWarm() async -> Bool {
        await client.isRuntimeWarm()
    }

    /// Best-effort warm-up so the model is resident (and its Metal/KV kernels compiled)
    /// and the slot's prompt cache holds the polish prefix before the first real
    /// request. Safe to call speculatively on dictation start: it no-ops when
    /// unavailable, shares any in-flight startup, never throws into the caller, and
    /// aborts promptly when the caller cancels it (freeing the generation slot).
    ///
    /// It probes even when the process is already warm: llama-server has ONE slot,
    /// and any other request shape (an Edit Mode rewrite) evicts the polish prefix
    /// from it. A probe against a primed cache is ~100 ms of slot time off the
    /// critical path; skipping it would silently hand the next dictation the full
    /// prefill. Process warmth and cache shape are different things.
    func prewarm(config: LocalGemmaMagicFormatConfig) async {
        guard availability.isAvailable, !Task.isCancelled else {
            return
        }
        let start = DispatchTime.now()
        do {
            _ = try await runProbe(config: config)
            let elapsedMs = Int((DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
            AppLogger.shared.log(.info, "local gemma prewarm complete latency_ms=\(elapsedMs)")
        } catch is CancellationError {
            AppLogger.shared.log(.debug, "local gemma prewarm canceled by real request")
        } catch {
            let reason = (error as? LLMPostProcessorError)?.logValue ?? "unknown"
            AppLogger.shared.log(.debug, "local gemma prewarm skipped reason=\(reason)")
        }
    }

    /// Tiny generation used to load the model and compile its kernels. Callers apply
    /// their own tail policy (prewarm swallows failures; testSetup validates output).
    ///
    /// The probe is shaped exactly like a real polish (same instructions, same
    /// `<transcript>` wrapper) rather than a throwaway "Reply with OK." — llama-server
    /// caches the KV state of the last prompt, and only a byte-identical prefix hits.
    /// With the ~2.4k-token system prompt, a mismatched probe left the first real
    /// request paying ~1.6s of prefill on the critical path.
    private func runProbe(config: LocalGemmaMagicFormatConfig) async throws -> String {
        let request = MagicFormatPipeline.makeRequest(
            text: LocalGemmaDefaults.probeText,
            systemPrompt: config.systemPrompt,
            keywords: config.keywords,
            retrying: false
        )
        return try await client.generate(
            instructions: request.instructions,
            prompt: request.prompt,
            maxTokens: LocalGemmaDefaults.probeMaxTokens,
            sampling: .greedy,
            startupTimeoutSeconds: config.startupTimeoutSeconds,
            idleTimeoutSeconds: config.idleTimeoutSeconds,
            timeoutSeconds: config.generationTimeoutSeconds
        ).text
    }

    func polish(text: String, config: LocalGemmaMagicFormatConfig) async throws -> String {
        try await makeGenerator(config).polish(
            text: text,
            systemPrompt: config.systemPrompt,
            keywords: config.keywords,
            timeoutFloorSeconds: config.generationTimeoutSeconds
        )
    }

    func generate(instructions: String, userText: String, config: LocalGemmaMagicFormatConfig) async throws -> String {
        try await makeGenerator(config).rewrite(
            instructions: instructions,
            userText: userText,
            timeoutFloorSeconds: config.generationTimeoutSeconds
        )
    }

    /// The probe is capped at `probeMaxTokens`, so a length stop still passes.
    func testSetup(config: LocalGemmaMagicFormatConfig) async throws {
        let generator = makeGenerator(config)
        try generator.checkReady()
        _ = try generator.requireOutput(try await runProbe(config: config))
    }

    func stopRuntime() async {
        await client.stopRuntime()
    }

    private func makeGenerator(_ config: LocalGemmaMagicFormatConfig) -> Generator {
        Generator(client: client, config: config, onGeneration: onGeneration)
    }

    /// A user-facing generation: uncapped, and it reports llama-server's
    /// counters. Turns a cancel into `.provider`.
    private struct Generator: MagicFormatGenerator {
        let client: LocalGemmaClient
        let config: LocalGemmaMagicFormatConfig
        let onGeneration: (@Sendable (ChatCompletionTimings) -> Void)?

        var usesSingleTurnPrompt: Bool { false }

        func checkReady() throws {
            let availability = client.availability
            guard availability.isAvailable else {
                throw LLMPostProcessorError.invalidConfiguration(availability.logValue)
            }
        }

        func sanitize(_ raw: String) -> String {
            LocalGemmaPostProcessor.sanitize(raw)
        }

        func generation(for request: MagicFormatGenerationRequest, timeoutSeconds: Double) async throws -> ChatCompletionResult {
            do {
                let generation = try await client.generate(
                    instructions: request.instructions,
                    prompt: request.prompt,
                    maxTokens: nil,
                    sampling: .greedy,
                    startupTimeoutSeconds: config.startupTimeoutSeconds,
                    idleTimeoutSeconds: config.idleTimeoutSeconds,
                    timeoutSeconds: timeoutSeconds
                )
                if let timings = generation.timings {
                    onGeneration?(timings)
                }
                return generation
            } catch {
                throw LLMPostProcessorError(wrapping: error)
            }
        }
    }

    /// Removes Gemma's thought and turn markers.
    static func sanitize(_ raw: String) -> String {
        var sanitized = MagicFormatOutputSanitizer.sanitize(raw)

        if let thoughtEnd = sanitized.range(of: "<channel|>", options: .backwards) {
            sanitized = String(sanitized[thoughtEnd.upperBound...])
        }

        let controlTokens = [
            "<|channel>final\n",
            "<|channel>final",
            "<end_of_turn>",
            "<eos>",
        ]
        for token in controlTokens {
            sanitized = sanitized.replacingOccurrences(of: token, with: "")
        }

        return MagicFormatOutputSanitizer.sanitize(sanitized)
    }
}
