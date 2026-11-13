import Foundation

/// Routes `TranscriptionServiceProtocol` calls to the appropriate engine based on the
/// loaded model's family: sherpa-onnx for the downloaded ONNX families, Apple's
/// `SpeechAnalyzer` for the system-managed `appleSpeech` family, our own ONNX
/// Runtime engine for `cohereTranscribe`, and the bundled llama.cpp helper for
/// `qwen3ASR`.
///
/// `AppState` talks to this as a single service, so OS-gating and engine selection stay
/// localized here rather than spreading through the app. Injectable children keep the
/// service mockable in tests.
///
/// A clip without speech never reaches an engine: engines write text for noise.
/// A final clip then throws `NoSpeechDetected`; a partial or meeting one gives
/// no text.
/// Only a `.probe` skips that check.
actor RoutingTranscriptionService: TranscriptionServiceProtocol {
    enum RoutingError: LocalizedError {
        case appleSpeechUnavailable

        var errorDescription: String? {
            switch self {
            case .appleSpeechUnavailable:
                return "Apple Speech requires macOS 26 or later"
            }
        }
    }

    private enum Engine: Equatable {
        case sherpa
        case apple
        case cohere
        case qwen3
    }

    private let sherpaService: TranscriptionServiceProtocol
    private let appleService: TranscriptionServiceProtocol?
    private let cohereService: TranscriptionServiceProtocol
    private let qwen3Service: TranscriptionServiceProtocol
    private let makeSpeechDetector: () throws -> SpeechDetecting
    private var active: (engine: Engine, speechDetector: SpeechDetecting)?

    init(
        sherpaService: TranscriptionServiceProtocol = TranscriptionService(),
        appleService: TranscriptionServiceProtocol? = RoutingTranscriptionService.makeAppleServiceIfSupported(),
        cohereService: TranscriptionServiceProtocol = CohereTranscriptionService(),
        qwen3Service: TranscriptionServiceProtocol = Qwen3ASRTranscriptionService(),
        makeSpeechDetector: @escaping () throws -> SpeechDetecting = { try SpeechDetector.bundled() }
    ) {
        self.sherpaService = sherpaService
        self.appleService = appleService
        self.cohereService = cohereService
        self.qwen3Service = qwen3Service
        self.makeSpeechDetector = makeSpeechDetector
    }

    static func makeAppleServiceIfSupported() -> TranscriptionServiceProtocol? {
        if #available(macOS 26, *), AppleSpeechSupport.isAvailable {
            return AppleSpeechTranscriptionService()
        }
        return nil
    }

    func loadModel(config: RecognizerConfig) async throws {
        let engine = Self.engine(for: config.family)
        guard let target = service(for: engine) else {
            throw RoutingError.appleSpeechUnavailable
        }
        let speechDetector = try active?.speechDetector ?? makeSpeechDetector()

        // Load the target first; only after it succeeds do we release the previously
        // active engine. Unloading first would destroy a working recognizer even when
        // the new engine fails to load (e.g. unsupported locale / no network for the
        // Apple asset), leaving the app "Ready" with no usable model.
        try await target.loadModel(config: config)

        if let previousEngine = active?.engine, previousEngine != engine, let previous = service(for: previousEngine) {
            await previous.unloadModel()
        }
        active = (engine, speechDetector)
    }

    func transcribe(
        samples: [Float],
        sampleRate: Int,
        purpose: TranscriptionPurpose,
        onProgress: @escaping @Sendable (TranscriptionProgress) -> Void
    ) async throws -> String {
        guard let active, let service = service(for: active.engine) else {
            throw TranscriptionService.ServiceError.recognizerNotLoaded
        }
        if purpose != .probe {
            let rate = max(8_000, sampleRate)
            let audio = try AudioResampler.resample(samples, from: rate, to: SpeechDetector.sampleRate)
            guard active.speechDetector.containsSpeech(audio) else {
                guard purpose == .final else {
                    return ""
                }
                AppLogger.shared.log(
                    .info,
                    String(format: "transcribe skipped: no speech in %.2fs", Double(samples.count) / Double(rate))
                )
                throw NoSpeechDetected()
            }
        }
        return try await service.transcribe(samples: samples, sampleRate: sampleRate, purpose: purpose, onProgress: onProgress)
    }

    func unloadModel() async {
        if let engine = active?.engine, let service = service(for: engine) {
            await service.unloadModel()
        }
        active = nil
    }

    private static func engine(for family: ASRModelFamily) -> Engine {
        switch family {
        case .appleSpeech:
            return .apple
        case .cohereTranscribe:
            return .cohere
        case .qwen3ASR:
            return .qwen3
        case .nemoTransducer, .moonshine, .senseVoice, .whisper:
            return .sherpa
        }
    }

    private func service(for engine: Engine) -> TranscriptionServiceProtocol? {
        switch engine {
        case .sherpa:
            return sherpaService
        case .apple:
            return appleService
        case .cohere:
            return cohereService
        case .qwen3:
            return qwen3Service
        }
    }
}
