import Foundation

/// Cohere Transcribe (Fast-Conformer encoder + autoregressive decoder) run
/// directly on ONNX Runtime. sherpa-onnx has no support for this architecture,
/// so this engine owns its sessions and decode loop.
///
/// Batch only: the encoder takes up to 35 s of raw 16 kHz audio per call, so
/// longer dictations are chunked (`CohereAudioChunker`) and decoded in order.
actor CohereTranscriptionService: TranscriptionServiceProtocol {
    enum ServiceError: LocalizedError {
        case notLoaded
        case emptyAudio
        case invalidConfiguration
        case missingModelFile(String)
        case unexpectedTensorShape(String)

        var errorDescription: String? {
            switch self {
            case .notLoaded:
                return "Cohere Transcribe is not loaded"
            case .emptyAudio:
                return "No audio captured"
            case .invalidConfiguration:
                return "The selected model files are incomplete"
            case let .missingModelFile(path):
                return "Required model file is missing: \(path)"
            case let .unexpectedTensorShape(detail):
                return "Cohere Transcribe returned an unexpected tensor: \(detail)"
            }
        }
    }

    /// Decoder geometry fixed by the export (8 layers × 8 heads × 128 dims,
    /// 1024-position self-attention cache).
    private static let selfCacheShape: [Int64] = [8, 1, 8, 1024, 128]
    private static let maxContextTokens = 1024
    private static let maxNewTokens = 512

    private var model: LoadedModel?

    func loadModel(config: RecognizerConfig) async throws {
        guard let encoderPath = config.encoderPath, let decoderPath = config.decoderPath else {
            throw ServiceError.invalidConfiguration
        }
        for path in [config.tokensPath, encoderPath, decoderPath] where !FileManager.default.fileExists(atPath: path) {
            throw ServiceError.missingModelFile(path)
        }

        let vocabulary = try CohereVocabulary(contentsOf: config.tokensPath)
        let language = CohereTranscribe.resolveLanguage(hint: config.language)
        let promptIDs = try vocabulary.promptIDs(language: language)

        let started = DispatchTime.now()
        let model = LoadedModel(
            encoder: try OrtSession(modelPath: encoderPath, intraOpThreads: config.numThreads),
            decoder: try OrtSession(modelPath: decoderPath, intraOpThreads: config.numThreads),
            vocabulary: vocabulary,
            promptIDs: promptIDs,
            language: language
        )
        let sessionsReady = DispatchTime.now()

        // ONNX Runtime defers ~1 s of one-time work (arena growth, first touch of the
        // memory-mapped encoder weights) to the first Run; pay it here, behind the
        // load spinner, instead of on the user's first sentence.
        _ = try await Self.decode(Self.warmupAudio, model: model)

        self.model = model
        AppLogger.shared.log(
            .info,
            String(
                format: "cohere loaded language=%@ threads=%d in %.2fs (warmup %.2fs)",
                language,
                config.numThreads,
                Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1e9,
                Double(DispatchTime.now().uptimeNanoseconds - sessionsReady.uptimeNanoseconds) / 1e9
            )
        )
    }

    // `purpose` is always `.final`: this family opts out of the live preview.
    func transcribe(
        samples: [Float],
        sampleRate: Int,
        purpose: TranscriptionPurpose,
        onProgress: @escaping @Sendable (TranscriptionProgress) -> Void
    ) async throws -> String {
        guard let model else {
            throw ServiceError.notLoaded
        }
        guard !samples.isEmpty else {
            throw ServiceError.emptyAudio
        }

        // Capture runs at the device's native rate (typically 48 kHz); the encoder's
        // baked-in frontend assumes 16 kHz.
        let audio = try AudioResampler.resample(samples, from: max(8_000, sampleRate), to: CohereTranscribe.sampleRate)
        let chunks = CohereAudioChunker.split(audio)
        AppLogger.shared.log(
            .info,
            String(
                format: "cohere transcribe start duration=%.2fs chunks=%d",
                Double(audio.count) / Double(CohereTranscribe.sampleRate),
                chunks.count
            )
        )

        // A chunk can block for seconds on slower Macs; a dedicated queue keeps
        // that off the cooperative pool. `model` is captured strongly, so an
        // unload racing a decode only drops the actor's reference.
        var texts: [String] = []
        for (index, chunk) in chunks.enumerated() {
            onProgress(TranscriptionProgress(chunk: index + 1, totalChunks: chunks.count))
            let started = DispatchTime.now()
            let tokens = try await Self.decode(Array(audio[chunk]), model: model)
            texts.append(model.vocabulary.text(for: tokens))
            AppLogger.shared.log(
                .info,
                String(
                    format: "cohere chunk done seconds=%.2f tokens=%d in %.2fs",
                    Double(chunk.count) / Double(CohereTranscribe.sampleRate),
                    tokens.count,
                    Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1e9
                )
            )
        }

        let text = CohereTranscribe.joinChunkTexts(texts, language: model.language)
        AppLogger.shared.log(.info, "cohere transcribe done chars=\(text.count)")
        return text
    }

    func unloadModel() async {
        model = nil
    }

    // MARK: - Inference

    /// Everything a decode needs, built in full before it is published as loaded.
    private struct LoadedModel {
        let encoder: OrtSession
        let decoder: OrtSession
        let vocabulary: CohereVocabulary
        let promptIDs: [Int64]
        let language: String
    }

    private static let inferenceQueue = DispatchQueue(label: "dev.suniye.cohere-inference", qos: .userInitiated)
    private static let warmupAudio = [Float](repeating: 0, count: CohereTranscribe.sampleRate)

    /// Runs one chunk on the inference queue and hands back its token ids.
    private static func decode(_ audio: [Float], model: LoadedModel) async throws -> [Int64] {
        try await withCheckedThrowingContinuation { continuation in
            inferenceQueue.async {
                continuation.resume(with: Result { try decodeChunk(audio, model: model) })
            }
        }
    }

    private static func decodeChunk(_ audio: [Float], model: LoadedModel) throws -> [Int64] {
        let encoded = try model.encoder.run(
            inputs: [("audio", try OrtTensor.float(shape: [1, Int64(audio.count)], values: audio))],
            outputNames: ["n_layer_cross_k", "n_layer_cross_v"]
        )
        let crossK = encoded[0]
        let crossV = encoded[1]

        var selfK = try OrtTensor.zeros(shape: selfCacheShape)
        var selfV = try OrtTensor.zeros(shape: selfCacheShape)
        var picker = CohereGreedyDecoder(endOfTextID: model.vocabulary.endOfTextID)
        var generated: [Int64] = []
        var step = model.promptIDs
        var offset: Int64 = 0
        let tokenBudget = min(maxNewTokens, maxContextTokens - model.promptIDs.count)

        while generated.count < tokenBudget {
            let outputs = try model.decoder.run(
                inputs: [
                    ("tokens", try OrtTensor.int64(shape: [1, Int64(step.count)], values: step)),
                    ("in_n_layer_self_k_cache", selfK),
                    ("in_n_layer_self_v_cache", selfV),
                    ("n_layer_cross_k", crossK),
                    ("n_layer_cross_v", crossV),
                    ("offset", try OrtTensor.int64(shape: [], values: [offset]))
                ],
                outputNames: ["logits", "out_n_layer_self_k_cache", "out_n_layer_self_v_cache"]
            )
            let logits = outputs[0]
            // The returned caches become next step's inputs: no copy, ORT owns both.
            selfK = outputs[1]
            selfV = outputs[2]

            let shape = try logits.shape
            guard shape.count == 3, shape[0] == 1, shape[1] == Int64(step.count), shape[2] > 0 else {
                throw ServiceError.unexpectedTensorShape("logits \(shape)")
            }
            let vocabularySize = Int(shape[2])
            let lastPosition = (step.count - 1) * vocabularySize ..< step.count * vocabularySize
            let next = try logits.withData(as: Float.self) { all in
                picker.next(logits: UnsafeBufferPointer(rebasing: all[lastPosition]))
            }
            guard let next else {
                break
            }
            generated.append(next)
            offset += Int64(step.count)
            step = [next]
        }
        return generated
    }
}
