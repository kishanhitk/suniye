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
    static let generationTimeoutSeconds = 15.0
    static let idleTimeoutSeconds = 600.0
    static let shutdownTimeoutSeconds = 2.0
    static let maxTokens = 256
    static let probeMaxTokens = 8

    static func serverArguments(modelPath: String, port: Int, apiKey: String) -> [String] {
        return [
            "--model", modelPath,
            "--host", "127.0.0.1",
            "--port", "\(port)",
            "--ctx-size", "4096",
            "--parallel", "1",
            "--reasoning", "off",
            "--api-key", apiKey,
            "--no-webui",
            "--log-disable",
        ]
    }
}

protocol LocalGemmaClient {
    var availability: LocalGemmaAvailability { get }
    func isRuntimeWarm() async -> Bool
    func generate(
        instructions: String,
        prompt: String,
        maxTokens: Int,
        startupTimeoutSeconds: Double,
        idleTimeoutSeconds: Double,
        timeoutSeconds: Double
    ) async throws -> String
    func stopRuntime() async
}

extension LocalGemmaClient {
    func isRuntimeWarm() async -> Bool { false }
    func stopRuntime() async {}
}

final class LocalGemmaPostProcessor: LocalGemmaMagicFormatPostProcessor {
    private let client: LocalGemmaClient

    init(client: LocalGemmaClient = LocalGemmaLlamaCppClient()) {
        self.client = client
    }

    var availability: LocalGemmaAvailability {
        client.availability
    }

    func isRuntimeWarm() async -> Bool {
        await client.isRuntimeWarm()
    }

    /// Best-effort warm-up so the model is resident (and its Metal/KV kernels compiled)
    /// before the first real polish request. Safe to call speculatively on dictation
    /// start: it no-ops when the runtime is already warm or unavailable, shares any
    /// in-flight startup, never throws into the caller, and aborts promptly when the
    /// caller cancels it (freeing the generation slot for the real request).
    func prewarm(config: LocalGemmaMagicFormatConfig) async {
        guard availability.isAvailable, !Task.isCancelled else {
            return
        }
        if await isRuntimeWarm() {
            return
        }
        do {
            _ = try await runProbe(prompt: "Warm up.", config: config)
            AppLogger.shared.log(.info, "local gemma prewarm complete")
        } catch is CancellationError {
            AppLogger.shared.log(.debug, "local gemma prewarm canceled by real request")
        } catch {
            let reason = (error as? LLMPostProcessorError)?.logValue ?? "unknown"
            AppLogger.shared.log(.debug, "local gemma prewarm skipped reason=\(reason)")
        }
    }

    /// Tiny generation used to load the model and compile its kernels. Callers apply
    /// their own tail policy (prewarm swallows failures; testSetup validates output).
    private func runProbe(prompt: String, config: LocalGemmaMagicFormatConfig) async throws -> String {
        try await client.generate(
            instructions: "Reply with OK.",
            prompt: prompt,
            maxTokens: LocalGemmaDefaults.probeMaxTokens,
            startupTimeoutSeconds: config.startupTimeoutSeconds,
            idleTimeoutSeconds: config.idleTimeoutSeconds,
            timeoutSeconds: config.generationTimeoutSeconds
        )
    }

    func polish(text: String, config: LocalGemmaMagicFormatConfig) async throws -> String {
        guard availability.isAvailable else {
            throw LLMPostProcessorError.invalidConfiguration(availability.logValue)
        }

        return try await MagicFormatPipeline.polish(
            text: text,
            systemPrompt: config.systemPrompt,
            keywords: config.keywords,
            maxTokens: config.maxTokens,
            sanitize: sanitizeGemmaOutput
        ) { request in
            do {
                return try await client.generate(
                    instructions: request.instructions,
                    prompt: request.prompt,
                    maxTokens: request.maxTokens ?? config.maxTokens,
                    startupTimeoutSeconds: config.startupTimeoutSeconds,
                    idleTimeoutSeconds: config.idleTimeoutSeconds,
                    timeoutSeconds: config.generationTimeoutSeconds
                )
            } catch let error as LLMPostProcessorError {
                throw error
            } catch {
                throw LLMPostProcessorError.provider(error.localizedDescription)
            }
        }
    }

    func testSetup(config: LocalGemmaMagicFormatConfig) async throws {
        guard availability.isAvailable else {
            throw LLMPostProcessorError.invalidConfiguration(availability.logValue)
        }

        let output = try await runProbe(prompt: "Connection test.", config: config)
        guard !sanitizeGemmaOutput(output).isEmpty else {
            throw LLMPostProcessorError.emptyOutput
        }
    }

    func stopRuntime() async {
        await client.stopRuntime()
    }

    private func sanitizeGemmaOutput(_ raw: String) -> String {
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
