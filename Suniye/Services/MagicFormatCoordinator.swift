import Foundation
import SuniyeAnalytics

enum EffectiveMagicFormatProvider: Equatable {
    case appleFoundationModels
    case localGemma
    case openAICompatible
}

/// The result of a Magic Format polish attempt: the text to insert, plus which
/// provider was involved and why it fell back (closed vocabulary — never a log
/// string). Construct only via the factories, which make the states coherent:
/// not-run (provider nil), polished (reason nil), or fell-back (reason set).
struct MagicFormatPolishOutcome {
    let text: String
    /// The provider that ran or was attempted; nil when no polish was attempted
    /// (Magic Format off, empty input).
    let provider: EffectiveMagicFormatProvider?
    let model: String?
    let fallbackReason: CleanupFallbackReason?

    /// A provider actually ran and produced output. This is the honest "Magic
    /// Format adoption" signal — an idempotent polish counts, a fallback-to-raw
    /// does not (unlike "did the text change").
    var ran: Bool { provider != nil && fallbackReason == nil }

    static func notRun(_ text: String) -> MagicFormatPolishOutcome {
        MagicFormatPolishOutcome(text: text, provider: nil, model: nil, fallbackReason: nil)
    }

    static func polished(_ text: String, provider: EffectiveMagicFormatProvider, model: String?) -> MagicFormatPolishOutcome {
        MagicFormatPolishOutcome(text: text, provider: provider, model: model, fallbackReason: nil)
    }

    static func fellBack(_ text: String, provider: EffectiveMagicFormatProvider?, model: String? = nil, reason: CleanupFallbackReason) -> MagicFormatPolishOutcome {
        MagicFormatPolishOutcome(text: text, provider: provider, model: model, fallbackReason: reason)
    }
}

extension CleanupFallbackReason {
    /// Exhaustive: adding an `LLMPostProcessorError` case won't compile until it
    /// picks an analytics reason — the boundary can't silently degrade.
    init(_ error: LLMPostProcessorError) {
        switch error {
        case .invalidConfiguration: self = .invalidConfig
        case .timeout: self = .timeout
        case .unauthorized: self = .unauthorized
        case .provider: self = .providerError
        case .malformedResponse: self = .malformedResponse
        case .emptyOutput: self = .emptyOutput
        case .network: self = .network
        }
    }
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
        /// Replaces the API model id in outcomes AND logs (e.g. "custom" when the
        /// user's preset carries a free-text model id). Snapshotted at request
        /// build time — settings can change across the polish suspension.
        var analyticsModelOverride: String? = nil
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

    func polish(input: String, rawText: String, request: PolishRequest) async -> MagicFormatPolishOutcome {
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
            // resolvedProvider is nil only when a SPECIFIC local provider was
            // requested but is unavailable (.automatic/.openAICompatible always
            // resolve) — record which one was attempted.
            let attempted: EffectiveMagicFormatProvider? = switch request.requestedProvider {
            case .appleFoundationModels: .appleFoundationModels
            case .localGemma: .localGemma
            case .automatic, .openAICompatible: nil // unreachable: these always resolve
            }
            return .fellBack(rawText, provider: attempted, reason: .providerUnavailable)
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

    private enum APIConfigFailure: String, Error {
        case invalidEndpoint = "invalid_endpoint"
        case invalidModel = "invalid_model"
        case missingKey = "missing_key"
        case keyReadFailed = "key_read_failed"

        var reason: CleanupFallbackReason {
            switch self {
            case .invalidEndpoint: .invalidEndpoint
            case .invalidModel: .invalidModel
            case .missingKey: .missingKey
            case .keyReadFailed: .keyReadFailed
            }
        }
    }

    /// Shared endpoint/model/key resolution for the API provider. The
    /// fallback-vs-throw policy stays at the call sites (polish vs rewrite).
    private func resolveAPIConfig(request: PolishRequest) -> Result<LLMConfig, APIConfigFailure> {
        guard let endpointURL = request.settings.validatedEndpointURL else {
            return .failure(.invalidEndpoint)
        }
        guard let modelId = request.settings.validatedModelId else {
            return .failure(.invalidModel)
        }
        guard request.hasAPIKey else {
            return .failure(.missingKey)
        }
        guard let apiKey = request.readAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            request.onAPIKeyReadFailed()
            return .failure(.keyReadFailed)
        }
        return .success(Self.makeAPIConfig(settings: request.settings, apiKey: apiKey, endpointURL: endpointURL, modelId: modelId))
    }

    private func polishWithAPI(input: String, rawText: String, request: PolishRequest) async -> MagicFormatPolishOutcome {
        let config: LLMConfig
        switch resolveAPIConfig(request: request) {
        case let .success(resolved):
            config = resolved
        case let .failure(failure):
            AppLogger.shared.log(.warning, "llm fallback raw reason=\(failure.rawValue)")
            return .fellBack(rawText, provider: .openAICompatible, reason: failure.reason)
        }

        let slowWarningTask = request.startSlowWarning()
        request.setStage(Stage.polishing)
        defer { slowWarningTask.cancel() }

        // Masked BEFORE it can reach the outcome or app.log (which ships in
        // diagnostic reports) — a custom preset's model id is user free text.
        let reportedModel = request.analyticsModelOverride ?? config.modelId
        return await runPolish(provider: .openAICompatible, model: reportedModel, logName: "api", rawText: rawText) {
            try await self.apiPostProcessor.polish(text: input, config: config)
        }
    }

    private func polishWithApple(input: String, rawText: String, request: PolishRequest) async -> MagicFormatPolishOutcome {
        let config = Self.makeAppleConfig(settings: request.settings)
        let slowWarningTask = request.startSlowWarning()
        request.setStage(Stage.polishing)
        defer { slowWarningTask.cancel() }

        return await runPolish(provider: .appleFoundationModels, model: nil, logName: "apple_foundation_models", rawText: rawText) {
            try await self.applePostProcessor.polish(text: input, config: config)
        }
    }

    private func polishWithLocalGemma(input: String, rawText: String, request: PolishRequest) async -> MagicFormatPolishOutcome {
        let config = Self.makeLocalGemmaConfig(settings: request.settings)
        let slowWarningTask = request.startSlowWarning()
        let isRuntimeWarm = await localGemmaPostProcessor.isRuntimeWarm()
        request.setStage(isRuntimeWarm ? Stage.polishing : Stage.startingLocalModel)
        defer { slowWarningTask.cancel() }

        return await runPolish(
            provider: .localGemma,
            model: LocalGemmaDefaults.modelDisplayName,
            logName: LocalGemmaDefaults.providerLogName,
            rawText: rawText
        ) {
            try await self.localGemmaPostProcessor.polish(text: input, config: config)
        }
    }

    /// The shared polish epilogue: run the provider, trim, guard empty output,
    /// log, and shape the outcome. One drift point instead of three.
    private func runPolish(
        provider: EffectiveMagicFormatProvider,
        model: String?,
        logName: String,
        rawText: String,
        body: () async throws -> String
    ) async -> MagicFormatPolishOutcome {
        let startTime = Date()
        let modelSuffix = model.map { " model=\($0)" } ?? ""
        do {
            let polished = try await body()
            let normalized = polished.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else {
                AppLogger.shared.log(.warning, "llm fallback raw provider=\(logName) reason=empty_output\(modelSuffix)")
                return .fellBack(rawText, provider: provider, model: model, reason: .emptyOutput)
            }
            let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
            AppLogger.shared.log(.info, "llm polish success provider=\(logName)\(modelSuffix) latency_ms=\(latencyMs)")
            return .polished(normalized, provider: provider, model: model)
        } catch {
            let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
            let llmError = error as? LLMPostProcessorError
            AppLogger.shared.log(.warning, "llm fallback raw provider=\(logName) reason=\(llmError?.logValue ?? "unknown")\(modelSuffix) latency_ms=\(latencyMs)")
            return .fellBack(rawText, provider: provider, model: model, reason: llmError.map(CleanupFallbackReason.init) ?? .unknown)
        }
    }

    /// Edit Mode: run a freeform instruction + user text through the selected provider.
    /// Unlike `polish`, failures throw instead of falling back to raw text.
    func rewrite(instructions: String, userText: String, request: PolishRequest) async throws -> String {
        // Real work takes priority over the speculative warm-up probe, same as polish.
        prewarmTask?.cancel()
        prewarmTask = nil

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
                    request.setStage(Stage.startingLocalModel)
                }
                output = try await localGemmaPostProcessor.generate(
                    instructions: instructions,
                    userText: userText,
                    config: Self.makeEditModeLocalGemmaConfig(settings: request.settings)
                )
            case .openAICompatible:
                switch resolveAPIConfig(request: request) {
                case let .success(config):
                    output = try await apiPostProcessor.generate(
                        instructions: instructions,
                        userText: userText,
                        config: config
                    )
                case let .failure(reason):
                    AppLogger.shared.log(.warning, "edit mode rewrite blocked reason=\(reason.rawValue)")
                    throw MagicFormatRewriteError.providerNotConfigured
                }
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

    /// Dedicated Command Mode inference: the agent's instruction+task → text (its
    /// next tool call as JSON). Parallel to `rewrite`, but Command Mode is NOT Edit
    /// Mode — it has its own logging and configs and no dictation side-effects.
    /// (A later change can request grammar-constrained JSON output on this path.)
    func commandInference(instructions: String, userText: String, request: PolishRequest) async throws -> String {
        prewarmTask?.cancel()
        prewarmTask = nil

        guard let provider = Self.resolvedProvider(
            requestedProvider: request.requestedProvider,
            appleAvailability: request.appleAvailability,
            localGemmaAvailability: request.localGemmaAvailability
        ) else {
            AppLogger.shared.log(.warning, "command inference blocked reason=local_provider_unavailable")
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
                    config: Self.makeCommandModeAppleConfig(settings: request.settings)
                )
            case .localGemma:
                if await !localGemmaPostProcessor.isRuntimeWarm() {
                    request.setStage(Stage.startingLocalModel)
                }
                output = try await localGemmaPostProcessor.generate(
                    instructions: instructions,
                    userText: userText,
                    config: Self.makeCommandModeLocalGemmaConfig(settings: request.settings)
                )
            case .openAICompatible:
                switch resolveAPIConfig(request: request) {
                case let .success(config):
                    output = try await apiPostProcessor.generate(
                        instructions: instructions,
                        userText: userText,
                        config: config
                    )
                case let .failure(reason):
                    AppLogger.shared.log(.warning, "command inference blocked reason=\(reason.rawValue)")
                    throw MagicFormatRewriteError.providerNotConfigured
                }
            }

            let normalized = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else {
                throw LLMPostProcessorError.emptyOutput
            }
            let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
            AppLogger.shared.log(.info, "command inference success provider=\(provider) latency_ms=\(latencyMs)")
            return normalized
        } catch {
            let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
            let reason = (error as? LLMPostProcessorError)?.logValue ?? "unknown"
            AppLogger.shared.log(.warning, "command inference failed provider=\(provider) reason=\(reason) latency_ms=\(latencyMs)")
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

    // Command Mode inference configs: empty system prompt (the agent supplies the
    // full instruction), short generation timeout, and a small token budget (one
    // JSON tool call). Kept separate from Edit Mode so the two can diverge.
    static func makeCommandModeAppleConfig(settings: LLMSettings) -> AppleMagicFormatConfig {
        AppleMagicFormatConfig(
            systemPrompt: "",
            keywords: [],
            timeoutSeconds: settings.timeoutSeconds,
            maxTokens: LLMDefaults.editModeMaxTokens
        )
    }

    static func makeCommandModeLocalGemmaConfig(settings: LLMSettings) -> LocalGemmaMagicFormatConfig {
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
