import Foundation

/// Routes `TranscriptionServiceProtocol` calls to the appropriate engine based on the
/// loaded model's family: sherpa-onnx for the downloaded ONNX families, Apple's
/// `SpeechAnalyzer` for the system-managed `appleSpeech` family, and our own ONNX
/// Runtime engine for `cohereTranscribe`.
///
/// `AppState` talks to this as a single service, so OS-gating and engine selection stay
/// localized here rather than spreading through the app. Injectable children keep the
/// service mockable in tests.
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
    }

    private let sherpaService: TranscriptionServiceProtocol
    private let appleService: TranscriptionServiceProtocol?
    private let cohereService: TranscriptionServiceProtocol
    private var activeEngine: Engine?

    init(
        sherpaService: TranscriptionServiceProtocol = TranscriptionService(),
        appleService: TranscriptionServiceProtocol? = RoutingTranscriptionService.makeAppleServiceIfSupported(),
        cohereService: TranscriptionServiceProtocol = CohereTranscriptionService()
    ) {
        self.sherpaService = sherpaService
        self.appleService = appleService
        self.cohereService = cohereService
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

        // Load the target first; only after it succeeds do we release the previously
        // active engine. Unloading first would destroy a working recognizer even when
        // the new engine fails to load (e.g. unsupported locale / no network for the
        // Apple asset), leaving the app "Ready" with no usable model.
        try await target.loadModel(config: config)

        if let activeEngine, activeEngine != engine, let previous = service(for: activeEngine) {
            await previous.unloadModel()
        }
        activeEngine = engine
    }

    func transcribe(
        samples: [Float],
        sampleRate: Int,
        purpose: TranscriptionPurpose,
        onProgress: @escaping @Sendable (TranscriptionProgress) -> Void
    ) async throws -> String {
        guard let activeEngine, let service = service(for: activeEngine) else {
            throw TranscriptionService.ServiceError.recognizerNotLoaded
        }
        return try await service.transcribe(samples: samples, sampleRate: sampleRate, purpose: purpose, onProgress: onProgress)
    }

    func unloadModel() async {
        if let activeEngine, let service = service(for: activeEngine) {
            await service.unloadModel()
        }
        activeEngine = nil
    }

    private static func engine(for family: ASRModelFamily) -> Engine {
        switch family {
        case .appleSpeech:
            return .apple
        case .cohereTranscribe:
            return .cohere
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
        }
    }
}
