import Foundation

enum EffectiveMagicFormatProvider {
    case appleFoundationModels
    case localGemma
    case openAICompatible
}

enum MagicFormatRewriteError: LocalizedError, Equatable {
    case providerNotConfigured

    var errorDescription: String? {
        "Magic Format provider is not ready"
    }
}

@MainActor
final class MagicFormatCoordinator {
    /// User-facing labels for each polish stage, shown in the status text and the
    /// floating pill. Kept in one place so the two sinks never drift.
    enum Stage {
        static let polishing = "Polishing..."
        static let startingLocalModel = "Starting local model..."
    }

    struct PolishRequest {
        let requestedProvider: MagicFormatProvider
        let settings: LLMSettings
        let hasAPIKey: Bool
        let appleAvailability: AppleFoundationModelsAvailability
        let localGemmaAvailability: LocalGemmaAvailability
        let readAPIKey: () -> String?
        let onAPIKeyReadFailed: () -> Void
        let startSlowWarning: () -> Task<Void, Never>
        /// Advertise the current stage to both the status text and the pill.
        let setStage: (String) -> Void
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

    /// In-flight speculative warm-up. Canceled when a real polish request arrives so
    /// the probe never occupies the server's single generation slot ahead of the user.
    private var prewarmTask: Task<Void, Never>?

    /// Speculatively warm the local runtime iff the request will actually resolve to
    /// the local Gemma provider. No-op for every other provider or when unavailable.
    /// Owns provider resolution + config assembly so it can never drift from `polish`.
    /// Fire-and-forget by design: returns the spawned task (for tests) without
    /// awaiting it, and cancels any prior probe so at most one is ever in flight.
    @discardableResult
    func prewarmLocalIfEligible(
        requestedProvider: MagicFormatProvider,
        settings: LLMSettings,
        appleAvailability: AppleFoundationModelsAvailability,
        localGemmaAvailability: LocalGemmaAvailability
    ) -> Task<Void, Never>? {
        let resolved = Self.resolvedProvider(
            requestedProvider: requestedProvider,
            appleAvailability: appleAvailability,
            localGemmaAvailability: localGemmaAvailability
        )
        guard case .localGemma = resolved else {
            return nil
        }
        let config = Self.makeLocalGemmaConfig(settings: settings)
        prewarmTask?.cancel()
        let task = Task { [localGemmaPostProcessor] in
            await localGemmaPostProcessor.prewarm(config: config)
        }
        prewarmTask = task
        return task
    }

    func polish(input: String, rawText: String, request: PolishRequest) async -> String {
        // Real work takes priority: free the generation slot if the probe still holds it.
        // (Server startup is a separate shared task; canceling the probe does not cancel it.)
        prewarmTask?.cancel()
        prewarmTask = nil

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
        request.setStage(Stage.polishing)
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
        request.setStage(Stage.polishing)
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
        request.setStage(isRuntimeWarm ? Stage.polishing : Stage.startingLocalModel)
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

    /// Edit Mode: run a freeform instruction + user text through the selected provider.
    /// Unlike `polish`, failures throw instead of falling back to raw text.
    func rewrite(instructions: String, userText: String, request: PolishRequest) async throws -> String {
        guard let provider = Self.resolvedProvider(
            requestedProvider: request.requestedProvider,
            appleAvailability: request.appleAvailability,
            localGemmaAvailability: request.localGemmaAvailability
        ) else {
            AppLogger.shared.log(.warning, "edit mode rewrite blocked reason=local_provider_unavailable")
            throw MagicFormatRewriteError.providerNotConfigured
        }

        let startTime = Date()
        let slowWarningTask = request.startSlowWarning()
        defer {
            slowWarningTask.cancel()
        }

        do {
            let output: String
            switch provider {
            case .appleFoundationModels:
                output = try await applePostProcessor.generate(
                    instructions: instructions,
                    userText: userText,
                    config: Self.makeEditModeAppleConfig(settings: request.settings)
                )
            case .localGemma:
                if await !localGemmaPostProcessor.isRuntimeWarm() {
                    request.setProcessingMessage("Starting local model...")
                }
                output = try await localGemmaPostProcessor.generate(
                    instructions: instructions,
                    userText: userText,
                    config: Self.makeEditModeLocalGemmaConfig(settings: request.settings)
                )
            case .openAICompatible:
                guard let endpointURL = request.settings.validatedEndpointURL,
                      let modelId = request.settings.validatedModelId,
                      request.hasAPIKey else {
                    AppLogger.shared.log(.warning, "edit mode rewrite blocked reason=api_not_configured")
                    throw MagicFormatRewriteError.providerNotConfigured
                }
                guard let apiKey = request.readAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !apiKey.isEmpty else {
                    AppLogger.shared.log(.warning, "edit mode rewrite blocked reason=key_read_failed")
                    request.onAPIKeyReadFailed()
                    throw MagicFormatRewriteError.providerNotConfigured
                }
                output = try await apiPostProcessor.generate(
                    instructions: instructions,
                    userText: userText,
                    config: Self.makeAPIConfig(settings: request.settings, apiKey: apiKey, endpointURL: endpointURL, modelId: modelId)
                )
            }

            let normalized = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else {
                throw LLMPostProcessorError.emptyOutput
            }
            let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
            AppLogger.shared.log(.info, "edit mode rewrite success provider=\(provider) latency_ms=\(latencyMs)")
            return normalized
        } catch {
            let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
            let reason = (error as? LLMPostProcessorError)?.logValue ?? "unknown"
            AppLogger.shared.log(.warning, "edit mode rewrite failed provider=\(provider) reason=\(reason) latency_ms=\(latencyMs)")
            throw error
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

    static func makeEditModeAppleConfig(settings: LLMSettings) -> AppleMagicFormatConfig {
        AppleMagicFormatConfig(
            systemPrompt: "",
            keywords: [],
            timeoutSeconds: settings.timeoutSeconds,
            maxTokens: LLMDefaults.editModeMaxTokens
        )
    }

    static func makeEditModeLocalGemmaConfig(settings: LLMSettings) -> LocalGemmaMagicFormatConfig {
        LocalGemmaMagicFormatConfig(
            systemPrompt: "",
            keywords: [],
            startupTimeoutSeconds: LocalGemmaDefaults.startupTimeoutSeconds,
            generationTimeoutSeconds: LocalGemmaDefaults.editModeGenerationTimeoutSeconds,
            idleTimeoutSeconds: settings.localModelKeepAlive.seconds,
            maxTokens: LLMDefaults.editModeMaxTokens
        )
    }

}
