import Foundation

/// Everything measured about one completed dictation, folded into a SINGLE
/// analytics event (one Analytics Engine data point) to keep event volume
/// within free-tier headroom at scale. Counts, durations, enums, and per-stage
/// latencies only — never the transcript.
public struct DictationMetrics: Sendable, Equatable {
    // Volume (counts, never content)
    public var wordCount: Int
    public var charCount: Int
    public var audioDurationMs: Int

    // What ran
    public var source: DictationSource
    public var destination: DictationDestination
    public var asrModel: SafeLabel
    public var asrFamily: SafeLabel
    public var language: SafeLabel
    public var wasLLMPolished: Bool
    public var cleanupProvider: CleanupProvider?
    public var cleanupModel: SafeLabel?
    public var cleanupFallbackReason: CleanupFallbackReason?
    public var insertionMethod: InsertionMethod
    public var targetCategory: TargetCategory

    /// Per-stage latency breakdown (milliseconds). All optional — a stage that
    /// didn't run (e.g. no Magic Format) is omitted rather than zeroed.
    public var latency: Latency

    /// Coarse audio-capture characteristics (no audio, just settings/quality).
    public var audio: AudioQuality

    public struct AudioQuality: Sendable, Equatable {
        public var backend: SafeLabel?
        public var fallbackReason: SafeLabel?
        public var inputTransport: SafeLabel?
        public var inputSampleRate: Int?
        public var inputChannels: Int?
        public var echoCancellationRequested: Bool?
        public var echoCancellationEffective: Bool?

        public init(
            backend: SafeLabel? = nil, fallbackReason: SafeLabel? = nil,
            inputTransport: SafeLabel? = nil, inputSampleRate: Int? = nil,
            inputChannels: Int? = nil, echoCancellationRequested: Bool? = nil,
            echoCancellationEffective: Bool? = nil
        ) {
            self.backend = backend
            self.fallbackReason = fallbackReason
            self.inputTransport = inputTransport
            self.inputSampleRate = inputSampleRate
            self.inputChannels = inputChannels
            self.echoCancellationRequested = echoCancellationRequested
            self.echoCancellationEffective = echoCancellationEffective
        }

        var props: [String: AnalyticsValue] {
            var out: [String: AnalyticsValue] = [:]
            if let backend { out["audio_backend"] = .label(backend) }
            if let fallbackReason { out["audio_fallback_reason"] = .label(fallbackReason) }
            if let inputTransport { out["input_transport"] = .label(inputTransport) }
            if let inputSampleRate { out["input_sample_rate"] = .int(inputSampleRate) }
            if let inputChannels { out["input_channels"] = .int(inputChannels) }
            if let echoCancellationRequested { out["aec_requested"] = .bool(echoCancellationRequested) }
            if let echoCancellationEffective { out["aec_effective"] = .bool(echoCancellationEffective) }
            return out
        }
    }

    public struct Latency: Sendable, Equatable {
        public var triggerToCaptureMs: Int?
        public var stopToAsrStartMs: Int?
        public var asrFirstTokenMs: Int?
        public var asrProcessingMs: Int?
        public var asrToLlmMs: Int?
        public var llmFirstTokenMs: Int?
        public var llmTotalMs: Int?
        public var insertMs: Int?
        /// stop → text visible in target app — the number the user feels.
        public var endToEndMs: Int?

        public init(
            triggerToCaptureMs: Int? = nil, stopToAsrStartMs: Int? = nil,
            asrFirstTokenMs: Int? = nil, asrProcessingMs: Int? = nil,
            asrToLlmMs: Int? = nil, llmFirstTokenMs: Int? = nil,
            llmTotalMs: Int? = nil, insertMs: Int? = nil, endToEndMs: Int? = nil
        ) {
            self.triggerToCaptureMs = triggerToCaptureMs
            self.stopToAsrStartMs = stopToAsrStartMs
            self.asrFirstTokenMs = asrFirstTokenMs
            self.asrProcessingMs = asrProcessingMs
            self.asrToLlmMs = asrToLlmMs
            self.llmFirstTokenMs = llmFirstTokenMs
            self.llmTotalMs = llmTotalMs
            self.insertMs = insertMs
            self.endToEndMs = endToEndMs
        }

        var props: [String: AnalyticsValue] {
            var out: [String: AnalyticsValue] = [:]
            func put(_ key: String, _ value: Int?) { if let value { out[key] = .int(value) } }
            put("lat_trigger_to_capture", triggerToCaptureMs)
            put("lat_stop_to_asr_start", stopToAsrStartMs)
            put("lat_asr_first_token", asrFirstTokenMs)
            put("lat_asr_processing", asrProcessingMs)
            put("lat_asr_to_llm", asrToLlmMs)
            put("lat_llm_first_token", llmFirstTokenMs)
            put("lat_llm_total", llmTotalMs)
            put("lat_insert", insertMs)
            put("lat_end_to_end", endToEndMs)
            return out
        }
    }

    public init(
        wordCount: Int, charCount: Int, audioDurationMs: Int,
        source: DictationSource, destination: DictationDestination,
        asrModel: SafeLabel, asrFamily: SafeLabel, language: SafeLabel,
        wasLLMPolished: Bool,
        cleanupProvider: CleanupProvider? = nil, cleanupModel: SafeLabel? = nil,
        cleanupFallbackReason: CleanupFallbackReason? = nil,
        insertionMethod: InsertionMethod, targetCategory: TargetCategory,
        latency: Latency, audio: AudioQuality = AudioQuality()
    ) {
        self.wordCount = wordCount
        self.charCount = charCount
        self.audioDurationMs = audioDurationMs
        self.source = source
        self.destination = destination
        self.asrModel = asrModel
        self.asrFamily = asrFamily
        self.language = language
        self.wasLLMPolished = wasLLMPolished
        self.cleanupProvider = cleanupProvider
        self.cleanupModel = cleanupModel
        self.cleanupFallbackReason = cleanupFallbackReason
        self.insertionMethod = insertionMethod
        self.targetCategory = targetCategory
        self.latency = latency
        self.audio = audio
    }

    var props: [String: AnalyticsValue] {
        var out: [String: AnalyticsValue] = [
            "word_count": .int(wordCount),
            "char_count": .int(charCount),
            "audio_duration_ms": .int(audioDurationMs),
            "source": .label(source),
            "destination": .label(destination),
            "asr_model": .label(asrModel),
            "asr_family": .label(asrFamily),
            "language": .label(language),
            "was_llm_polished": .bool(wasLLMPolished),
            "insertion_method": .label(insertionMethod),
            "target_category": .label(targetCategory)
        ]
        if let cleanupProvider { out["cleanup_provider"] = .label(cleanupProvider) }
        if let cleanupModel { out["cleanup_model"] = .label(cleanupModel) }
        if let cleanupFallbackReason { out["cleanup_fallback_reason"] = .label(cleanupFallbackReason) }
        out.merge(latency.props) { current, _ in current }
        out.merge(audio.props) { current, _ in current }
        return out
    }
}
