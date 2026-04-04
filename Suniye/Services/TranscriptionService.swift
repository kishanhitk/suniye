import Foundation

struct RecognizerConfig {
    let modelID: ASRModelID
    let family: ASRModelFamily
    let tokensPath: String
    let numThreads: Int
    let encoderPath: String?
    let decoderPath: String?
    let joinerPath: String?
    let preprocessorPath: String?
    let uncachedDecoderPath: String?
    let cachedDecoderPath: String?
    let modelPath: String?
    let language: String
    let task: String
    let modelType: String
    let useInverseTextNormalization: Bool

    init(
        modelID: ASRModelID = .parakeetV3,
        family: ASRModelFamily = .nemoTransducer,
        tokensPath: String,
        numThreads: Int,
        encoderPath: String? = nil,
        decoderPath: String? = nil,
        joinerPath: String? = nil,
        preprocessorPath: String? = nil,
        uncachedDecoderPath: String? = nil,
        cachedDecoderPath: String? = nil,
        modelPath: String? = nil,
        language: String = "",
        task: String = "transcribe",
        modelType: String = "",
        useInverseTextNormalization: Bool = false
    ) {
        self.modelID = modelID
        self.family = family
        self.tokensPath = tokensPath
        self.numThreads = numThreads
        self.encoderPath = encoderPath
        self.decoderPath = decoderPath
        self.joinerPath = joinerPath
        self.preprocessorPath = preprocessorPath
        self.uncachedDecoderPath = uncachedDecoderPath
        self.cachedDecoderPath = cachedDecoderPath
        self.modelPath = modelPath
        self.language = language
        self.task = task
        self.modelType = modelType
        self.useInverseTextNormalization = useInverseTextNormalization
    }
}

protocol TranscriptionServiceProtocol {
    func loadModel(config: RecognizerConfig) async throws
    func transcribe(samples: [Float], sampleRate: Int) async throws -> String
    func unloadModel() async
}

actor TranscriptionService: TranscriptionServiceProtocol {
    enum ServiceError: LocalizedError {
        case recognizerNotLoaded
        case emptyAudio
        case missingModelFile(String)
        case invalidRecognizerConfiguration
        case recognizerCreationFailed(String?)
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
            case .invalidRecognizerConfiguration:
                return "The selected model files are incomplete"
            case let .recognizerCreationFailed(message):
                if let message, !message.isEmpty {
                    return "Failed to create sherpa-onnx offline recognizer: \(message)"
                }
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

        let recognizerConfig = try makeRecognizerConfig(for: config)
        var configCopy = recognizerConfig
        var nativeError: UnsafeMutablePointer<CChar>?

        guard let created = SuniyeCreateOfflineRecognizerSafe(&configCopy, &nativeError) else {
            let message = nativeError.map { pointer in
                let value = String(cString: pointer)
                SuniyeFreeCString(pointer)
                return value
            }
            throw ServiceError.recognizerCreationFailed(message)
        }

        if let recognizer {
            SherpaOnnxDestroyOfflineRecognizer(recognizer)
        }
        recognizer = created
        loadedConfig = config
    }

    func transcribe(samples: [Float], sampleRate: Int = 16_000) async throws -> String {
        guard let recognizer else {
            throw ServiceError.recognizerNotLoaded
        }

        guard !samples.isEmpty else {
            throw ServiceError.emptyAudio
        }

        let effectiveSampleRate = max(8_000, sampleRate)
        let inputDuration = Double(samples.count) / Double(effectiveSampleRate)
        AppLogger.shared.log(
            .info,
            String(
                format: "transcribe start samples=%d sr=%d duration=%.2fs",
                samples.count,
                effectiveSampleRate,
                inputDuration
            )
        )

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
            SherpaOnnxAcceptWaveformOffline(stream, Int32(effectiveSampleRate), baseAddress, Int32(buffer.count))
        }

        SherpaOnnxDecodeOfflineStream(recognizer, stream)

        guard let result = SherpaOnnxGetOfflineStreamResult(stream) else {
            throw ServiceError.decodeResultUnavailable
        }
        defer {
            SherpaOnnxDestroyOfflineRecognizerResult(result)
        }

        guard let cText = result.pointee.text else {
            AppLogger.shared.log(.warning, "transcribe result text pointer was nil")
            return ""
        }
        let text = String(cString: cText).trimmingCharacters(in: .whitespacesAndNewlines)
        AppLogger.shared.log(.info, "transcribe done chars=\(text.count)")
        return text
    }

    func unloadModel() async {
        if let recognizer {
            SherpaOnnxDestroyOfflineRecognizer(recognizer)
        }
        recognizer = nil
        loadedConfig = nil
    }

    private func makeRecognizerConfig(for config: RecognizerConfig) throws -> SherpaOnnxOfflineRecognizerConfig {
        let modelConfig: SherpaOnnxOfflineModelConfig

        switch config.family {
        case .nemoTransducer:
            guard let encoderPath = config.encoderPath,
                  let decoderPath = config.decoderPath,
                  let joinerPath = config.joinerPath else {
                throw ServiceError.invalidRecognizerConfiguration
            }

            let transducer = sherpaOnnxOfflineTransducerModelConfig(
                encoder: encoderPath,
                decoder: decoderPath,
                joiner: joinerPath
            )

            modelConfig = sherpaOnnxOfflineModelConfig(
                tokens: config.tokensPath,
                transducer: transducer,
                numThreads: max(1, config.numThreads),
                provider: "cpu",
                debug: 0,
                modelType: config.modelType
            )
        case .moonshine:
            guard let preprocessorPath = config.preprocessorPath,
                  let encoderPath = config.encoderPath,
                  let uncachedDecoderPath = config.uncachedDecoderPath,
                  let cachedDecoderPath = config.cachedDecoderPath else {
                throw ServiceError.invalidRecognizerConfiguration
            }

            let moonshine = sherpaOnnxOfflineMoonshineModelConfig(
                preprocessor: preprocessorPath,
                encoder: encoderPath,
                uncachedDecoder: uncachedDecoderPath,
                cachedDecoder: cachedDecoderPath
            )

            modelConfig = sherpaOnnxOfflineModelConfig(
                tokens: config.tokensPath,
                numThreads: max(1, config.numThreads),
                provider: "cpu",
                debug: 0,
                moonshine: moonshine
            )
        case .senseVoice:
            guard let modelPath = config.modelPath else {
                throw ServiceError.invalidRecognizerConfiguration
            }

            let senseVoice = sherpaOnnxOfflineSenseVoiceModelConfig(
                model: modelPath,
                language: config.language,
                useInverseTextNormalization: config.useInverseTextNormalization
            )

            modelConfig = sherpaOnnxOfflineModelConfig(
                tokens: config.tokensPath,
                numThreads: max(1, config.numThreads),
                provider: "cpu",
                debug: 0,
                senseVoice: senseVoice
            )
        case .whisper:
            guard let encoderPath = config.encoderPath,
                  let decoderPath = config.decoderPath else {
                throw ServiceError.invalidRecognizerConfiguration
            }

            let whisper = sherpaOnnxOfflineWhisperModelConfig(
                encoder: encoderPath,
                decoder: decoderPath,
                language: config.language,
                task: config.task
            )

            modelConfig = sherpaOnnxOfflineModelConfig(
                tokens: config.tokensPath,
                whisper: whisper,
                numThreads: max(1, config.numThreads),
                provider: "cpu",
                debug: 0
            )
        }

        return sherpaOnnxOfflineRecognizerConfig(
            featConfig: sherpaOnnxFeatureConfig(sampleRate: 16_000, featureDim: 80),
            modelConfig: modelConfig,
            decodingMethod: "greedy_search",
            maxActivePaths: 4
        )
    }

    private func validateModelPaths(_ config: RecognizerConfig) throws {
        var paths = [config.tokensPath]

        switch config.family {
        case .nemoTransducer:
            paths.append(contentsOf: [config.encoderPath, config.decoderPath, config.joinerPath].compactMap { $0 })
        case .moonshine:
            paths.append(contentsOf: [
                config.preprocessorPath,
                config.encoderPath,
                config.uncachedDecoderPath,
                config.cachedDecoderPath
            ].compactMap { $0 })
        case .senseVoice:
            paths.append(contentsOf: [config.modelPath].compactMap { $0 })
        case .whisper:
            paths.append(contentsOf: [config.encoderPath, config.decoderPath].compactMap { $0 })
        }

        for path in paths where !FileManager.default.fileExists(atPath: path) {
            throw ServiceError.missingModelFile(path)
        }
    }
}
