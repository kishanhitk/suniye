import Foundation

struct RecognizerConfig {
    let encoderPath: String
    let decoderPath: String
    let joinerPath: String
    let tokensPath: String
    let numThreads: Int
}

actor TranscriptionService {
    enum ServiceError: LocalizedError {
        case recognizerNotLoaded
        case emptyAudio
        case missingModelFile(String)
        case recognizerCreationFailed
        case streamCreationFailed
        case decodeResultUnavailable

        var errorDescription: String? {
            switch self {
            case .recognizerNotLoaded:
                return "Recognizer is not loaded"
            case .emptyAudio:
                return "No audio captured"
            case let .missingModelFile(path):
                return "Required model file is missing: \(path)"
            case .recognizerCreationFailed:
                return "Failed to create sherpa-onnx offline recognizer"
            case .streamCreationFailed:
                return "Failed to create sherpa-onnx offline stream"
            case .decodeResultUnavailable:
                return "Failed to read recognition result from sherpa-onnx"
            }
        }
    }

    private var recognizer: OpaquePointer?
    private var loadedConfig: RecognizerConfig?

    deinit {
        if let recognizer {
            SherpaOnnxDestroyOfflineRecognizer(recognizer)
        }
    }

    func loadModel(config: RecognizerConfig) async throws {
        try validateModelPaths(config)

        let transducer = sherpaOnnxOfflineTransducerModelConfig(
            encoder: config.encoderPath,
            decoder: config.decoderPath,
            joiner: config.joinerPath
        )

        let modelConfig = sherpaOnnxOfflineModelConfig(
            tokens: config.tokensPath,
            transducer: transducer,
            numThreads: max(1, config.numThreads),
            provider: "cpu",
            debug: 0,
            modelType: "nemo_transducer"
        )

        let recognizerConfig = sherpaOnnxOfflineRecognizerConfig(
            featConfig: sherpaOnnxFeatureConfig(sampleRate: 16_000, featureDim: 80),
            modelConfig: modelConfig,
            decodingMethod: "greedy_search",
            maxActivePaths: 4
        )
        var configCopy = recognizerConfig

        guard let created = SherpaOnnxCreateOfflineRecognizer(&configCopy) else {
            throw ServiceError.recognizerCreationFailed
        }

        if let recognizer {
            SherpaOnnxDestroyOfflineRecognizer(recognizer)
        }
        recognizer = created
        loadedConfig = config
    }

    func transcribe(samples: [Float]) async throws -> String {
        guard let recognizer else {
            throw ServiceError.recognizerNotLoaded
        }

        guard !samples.isEmpty else {
            throw ServiceError.emptyAudio
        }

        guard let stream = SherpaOnnxCreateOfflineStream(recognizer) else {
            throw ServiceError.streamCreationFailed
        }
        defer {
            SherpaOnnxDestroyOfflineStream(stream)
        }

        samples.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress, !buffer.isEmpty else {
                return
            }
            SherpaOnnxAcceptWaveformOffline(stream, 16_000, baseAddress, Int32(buffer.count))
        }

        SherpaOnnxDecodeOfflineStream(recognizer, stream)

        guard let result = SherpaOnnxGetOfflineStreamResult(stream) else {
            throw ServiceError.decodeResultUnavailable
        }
        defer {
            SherpaOnnxDestroyOfflineRecognizerResult(result)
        }

        guard let cText = result.pointee.text else {
            return ""
        }
        return String(cString: cText).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func validateModelPaths(_ config: RecognizerConfig) throws {
        let paths = [config.encoderPath, config.decoderPath, config.joinerPath, config.tokensPath]
        for path in paths where !FileManager.default.fileExists(atPath: path) {
            throw ServiceError.missingModelFile(path)
        }
    }
}
