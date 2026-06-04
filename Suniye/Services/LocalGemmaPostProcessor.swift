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
    static let idleTimeoutSeconds = 180.0
    static let shutdownTimeoutSeconds = 2.0
    static let maxTokens = 256

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

        let output = try await client.generate(
            instructions: "Reply with OK.",
            prompt: "Connection test.",
            maxTokens: 8,
            startupTimeoutSeconds: config.startupTimeoutSeconds,
            timeoutSeconds: config.generationTimeoutSeconds
        )
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
