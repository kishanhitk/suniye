import Foundation

/// Routes `TranscriptionServiceProtocol` calls to the appropriate engine based on the
/// loaded model's family: sherpa-onnx for the downloaded ONNX families, Apple's
/// `SpeechAnalyzer` for the system-managed `appleSpeech` family.
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
    }

    private let sherpaService: TranscriptionServiceProtocol
    private let appleService: TranscriptionServiceProtocol?
    private var activeEngine: Engine?

    init(
        sherpaService: TranscriptionServiceProtocol = TranscriptionService(),
        appleService: TranscriptionServiceProtocol? = RoutingTranscriptionService.makeAppleServiceIfSupported()
    ) {
        self.sherpaService = sherpaService
        self.appleService = appleService
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

        // Switching engines: release the previously loaded one so only one holds a model.
        if let activeEngine, activeEngine != engine, let previous = service(for: activeEngine) {
            await previous.unloadModel()
        }

        try await target.loadModel(config: config)
        activeEngine = engine
    }

    func transcribe(samples: [Float], sampleRate: Int) async throws -> String {
        guard let activeEngine, let service = service(for: activeEngine) else {
            throw TranscriptionService.ServiceError.recognizerNotLoaded
        }
        return try await service.transcribe(samples: samples, sampleRate: sampleRate)
    }

    func unloadModel() async {
        if let activeEngine, let service = service(for: activeEngine) {
            await service.unloadModel()
        }
        activeEngine = nil
    }

    private static func engine(for family: ASRModelFamily) -> Engine {
        family == .appleSpeech ? .apple : .sherpa
    }

    private func service(for engine: Engine) -> TranscriptionServiceProtocol? {
        switch engine {
        case .sherpa:
            return sherpaService
        case .apple:
            return appleService
        }
    }
}
