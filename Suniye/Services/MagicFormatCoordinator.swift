import Foundation

enum EffectiveMagicFormatProvider {
    case appleFoundationModels
    case localGemma
    case openAICompatible
}

@MainActor
final class MagicFormatCoordinator {
    struct PolishRequest {
        let requestedProvider: MagicFormatProvider
        let settings: LLMSettings
        let hasAPIKey: Bool
        let appleAvailability: AppleFoundationModelsAvailability
        let localGemmaAvailability: LocalGemmaAvailability
        let readAPIKey: () -> String?
        let onAPIKeyReadFailed: () -> Void
        let startSlowWarning: () -> Task<Void, Never>
        let setStatusText: (String) -> Void
        let setProcessingMessage: (String) -> Void
    }

    private let apiPostProcessor: LLMPostProcessor
    private let applePostProcessor: AppleMagicFormatPostProcessor
    private let localGemmaPostProcessor: LocalGemmaMagicFormatPostProcessor

    init(
        apiPostProcessor: LLMPostProcessor,
        applePostProcessor: AppleMagicFormatPostProcessor,
        localGemmaPostProcessor: LocalGemmaMagicFormatPostProcessor
    ) {
        self.apiPostProcessor = apiPostProcessor
        self.applePostProcessor = applePostProcessor
        self.localGemmaPostProcessor = localGemmaPostProcessor
    }

    static func resolvedProvider(
        requestedProvider: MagicFormatProvider,
        appleAvailability: AppleFoundationModelsAvailability,
        localGemmaAvailability: LocalGemmaAvailability
    ) -> EffectiveMagicFormatProvider? {
        switch requestedProvider {
        case .automatic:
            if appleAvailability.isAvailable {
                return .appleFoundationModels
            }
            if localGemmaAvailability.isAvailable {
                return .localGemma
            }
            return .openAICompatible
        case .appleFoundationModels:
            return appleAvailability.isAvailable ? .appleFoundationModels : nil
        case .localGemma:
            return localGemmaAvailability.isAvailable ? .localGemma : nil
        case .openAICompatible:
            return .openAICompatible
        }
    }

    static func usesAppleSettings(
        requestedProvider: MagicFormatProvider,
        appleAvailability: AppleFoundationModelsAvailability
    ) -> Bool {
        switch requestedProvider {
        case .automatic:
            return appleAvailability.isAvailable
        case .appleFoundationModels:
            return true
        case .localGemma, .openAICompatible:
            return false
        }
    }

    static func usesLocalGemmaSettings(
        requestedProvider: MagicFormatProvider,
        appleAvailability: AppleFoundationModelsAvailability,
        localGemmaAvailability: LocalGemmaAvailability
    ) -> Bool {
        switch requestedProvider {
        case .automatic:
            return !appleAvailability.isAvailable && localGemmaAvailability.isAvailable
        case .localGemma:
            return true
        case .appleFoundationModels, .openAICompatible:
            return false
        }
    }

    static func needsAPIConfiguration(
        requestedProvider: MagicFormatProvider,
        appleAvailability: AppleFoundationModelsAvailability,
        localGemmaAvailability: LocalGemmaAvailability
    ) -> Bool {
        switch requestedProvider {
        case .automatic:
            return !appleAvailability.isAvailable && !localGemmaAvailability.isAvailable
        case .appleFoundationModels, .localGemma:
            return false
        case .openAICompatible:
            return true
        }
    }

    func polish(input: String, rawText: String, request: PolishRequest) async -> String {
        guard let provider = Self.resolvedProvider(
            requestedProvider: request.requestedProvider,
            appleAvailability: request.appleAvailability,
            localGemmaAvailability: request.localGemmaAvailability
        ) else {
            AppLogger.shared.log(.warning, "llm fallback raw reason=local_provider_unavailable apple_availability=\(request.appleAvailability.logValue) gemma_availability=\(request.localGemmaAvailability.logValue)")
            return rawText
        }

        switch provider {
        case .appleFoundationModels:
            return await polishWithApple(input: input, rawText: rawText, request: request)
        case .localGemma:
            return await polishWithLocalGemma(input: input, rawText: rawText, request: request)
        case .openAICompatible:
            return await polishWithAPI(input: input, rawText: rawText, request: request)
        }
    }

    private func polishWithAPI(input: String, rawText: String, request: PolishRequest) async -> String {
        guard let endpointURL = request.settings.validatedEndpointURL else {
            AppLogger.shared.log(.warning, "llm fallback raw reason=invalid_endpoint")
            return rawText
        }

        guard let modelId = request.settings.validatedModelId else {
            AppLogger.shared.log(.warning, "llm fallback raw reason=invalid_model")
            return rawText
        }

        guard request.hasAPIKey else {
            AppLogger.shared.log(.warning, "llm fallback raw reason=missing_key")
            return rawText
        }

        guard let apiKey = request.readAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            AppLogger.shared.log(.warning, "llm fallback raw reason=key_read_failed")
            request.onAPIKeyReadFailed()
            return rawText
        }

        let config = Self.makeAPIConfig(settings: request.settings, apiKey: apiKey, endpointURL: endpointURL, modelId: modelId)
        let startTime = Date()
        let slowWarningTask = request.startSlowWarning()
        request.setStatusText("Polishing...")
        defer {
            slowWarningTask.cancel()
        }

        do {
            let polished = try await apiPostProcessor.polish(text: input, config: config)
            let normalized = polished.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else {
                AppLogger.shared.log(.warning, "llm fallback raw reason=empty_output model=\(config.modelId)")
                return rawText
            }
            let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
            AppLogger.shared.log(.info, "llm polish success provider=api model=\(config.modelId) latency_ms=\(latencyMs)")
            return normalized
        } catch {
            let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
            if let llmError = error as? LLMPostProcessorError {
                AppLogger.shared.log(.warning, "llm fallback raw provider=api reason=\(llmError.logValue) model=\(config.modelId) latency_ms=\(latencyMs)")
            } else {
                AppLogger.shared.log(.warning, "llm fallback raw provider=api reason=unknown model=\(config.modelId) latency_ms=\(latencyMs)")
            }
            return rawText
        }
    }

    private func polishWithApple(input: String, rawText: String, request: PolishRequest) async -> String {
        let config = Self.makeAppleConfig(settings: request.settings)
        let startTime = Date()
        let slowWarningTask = request.startSlowWarning()
        request.setStatusText("Polishing...")
        defer {
            slowWarningTask.cancel()
        }

        do {
            let polished = try await applePostProcessor.polish(text: input, config: config)
            let normalized = polished.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else {
                AppLogger.shared.log(.warning, "llm fallback raw provider=apple reason=empty_output")
                return rawText
            }
            let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
            AppLogger.shared.log(.info, "llm polish success provider=apple_foundation_models latency_ms=\(latencyMs)")
            return normalized
        } catch {
            let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
            if let llmError = error as? LLMPostProcessorError {
                AppLogger.shared.log(.warning, "llm fallback raw provider=apple reason=\(llmError.logValue) latency_ms=\(latencyMs)")
            } else {
                AppLogger.shared.log(.warning, "llm fallback raw provider=apple reason=unknown latency_ms=\(latencyMs)")
            }
            return rawText
        }
    }

    private func polishWithLocalGemma(input: String, rawText: String, request: PolishRequest) async -> String {
        let config = Self.makeLocalGemmaConfig(settings: request.settings)
        let startTime = Date()
        let slowWarningTask = request.startSlowWarning()
        let isRuntimeWarm = await localGemmaPostProcessor.isRuntimeWarm()
        if isRuntimeWarm {
            request.setStatusText("Polishing...")
        } else {
            request.setStatusText("Starting local model...")
            request.setProcessingMessage("Starting local model...")
        }
        defer {
            slowWarningTask.cancel()
        }

        do {
            let polished = try await localGemmaPostProcessor.polish(text: input, config: config)
            let normalized = polished.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else {
                AppLogger.shared.log(.warning, "llm fallback raw provider=\(LocalGemmaDefaults.providerLogName) reason=empty_output")
                return rawText
            }
            let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
            AppLogger.shared.log(.info, "llm polish success provider=\(LocalGemmaDefaults.providerLogName) model=\(LocalGemmaDefaults.modelDisplayName) latency_ms=\(latencyMs)")
            return normalized
        } catch {
            let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
            if let llmError = error as? LLMPostProcessorError {
                AppLogger.shared.log(.warning, "llm fallback raw provider=\(LocalGemmaDefaults.providerLogName) reason=\(llmError.logValue) latency_ms=\(latencyMs)")
            } else {
                AppLogger.shared.log(.warning, "llm fallback raw provider=\(LocalGemmaDefaults.providerLogName) reason=unknown latency_ms=\(latencyMs)")
            }
            return rawText
        }
    }

    static func makeAPIConfig(settings: LLMSettings, apiKey: String, endpointURL: URL, modelId: String) -> LLMConfig {
        LLMConfig(
            modelId: modelId,
            endpointURL: endpointURL,
            systemPrompt: settings.composedSystemPrompt,
            keywords: settings.keywords,
            timeoutSeconds: settings.timeoutSeconds,
            apiKey: apiKey
        )
    }

    static func makeAppleConfig(settings: LLMSettings) -> AppleMagicFormatConfig {
        AppleMagicFormatConfig(
            systemPrompt: settings.composedAppleSystemPrompt,
            keywords: settings.keywords,
            timeoutSeconds: settings.timeoutSeconds,
            maxTokens: LLMDefaults.appleMaxTokens
        )
    }

    static func makeLocalGemmaConfig(settings: LLMSettings) -> LocalGemmaMagicFormatConfig {
        LocalGemmaMagicFormatConfig(
            systemPrompt: settings.composedGemmaSystemPrompt,
            keywords: settings.keywords,
            startupTimeoutSeconds: LocalGemmaDefaults.startupTimeoutSeconds,
            generationTimeoutSeconds: LocalGemmaDefaults.generationTimeoutSeconds,
            idleTimeoutSeconds: settings.localModelKeepAlive.seconds,
            maxTokens: LocalGemmaDefaults.maxTokens
        )
    }

}
