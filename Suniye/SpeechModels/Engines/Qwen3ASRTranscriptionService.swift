import Foundation

/// Qwen3-ASR served by the bundled llama.cpp helper. The helper keeps the GGUF
/// weights in memory while the model is loaded, and restarts on the next
/// request if it dies. Each chunk of a dictation is one chat completion whose
/// user turn holds only the audio, as a WAV.
///
/// Batch only: long dictations are chunked (`Qwen3ASR.chunker`) and decoded in
/// order. Chunks without speech never reach the model (`SpeechDetecting`).
actor Qwen3ASRTranscriptionService: TranscriptionServiceProtocol {
    enum ServiceError: LocalizedError, Equatable {
        case notLoaded
        case emptyAudio
        case invalidConfiguration
        case missingModelFile(String)
        case runtimeUnavailable
        case serverFailed(String)
        case requestFailed(String)

        var errorDescription: String? {
            switch self {
            case .notLoaded:
                return "Qwen3-ASR is not loaded"
            case .emptyAudio:
                return "No audio captured"
            case .invalidConfiguration:
                return "The selected model files are incomplete"
            case let .missingModelFile(path):
                return "Required model file is missing: \(path)"
            case .runtimeUnavailable:
                return "The bundled llama-server helper is missing"
            case let .serverFailed(reason):
                return "The Qwen3-ASR helper failed to start: \(reason)"
            case let .requestFailed(reason):
                return "The Qwen3-ASR helper failed to transcribe: \(reason)"
            }
        }
    }

    /// Everything a decode needs, built in full before it is published as loaded.
    private struct LoadedModel {
        let launch: LlamaServerLaunch
        let speechDetector: SpeechDetecting
    }

    private let server: LlamaServer
    private let makeSpeechDetector: () throws -> SpeechDetecting
    private var model: LoadedModel?

    init(
        server: LlamaServer = LlamaServer(),
        makeSpeechDetector: @escaping () throws -> SpeechDetecting = { try SpeechDetector.bundled() }
    ) {
        self.server = server
        self.makeSpeechDetector = makeSpeechDetector
    }

    func loadModel(config: RecognizerConfig) async throws {
        guard let modelPath = config.modelPath, let projectorPath = config.encoderPath else {
            throw ServiceError.invalidConfiguration
        }
        for path in [modelPath, projectorPath] where !FileManager.default.fileExists(atPath: path) {
            throw ServiceError.missingModelFile(path)
        }
        guard let executableURL = LlamaServer.locateExecutable() else {
            throw ServiceError.runtimeUnavailable
        }

        let model = LoadedModel(
            launch: LlamaServerLaunch(
                executableURL: executableURL,
                arguments: Qwen3ASR.serverArguments(modelPath: modelPath, projectorPath: projectorPath),
                modelName: ASRModelCatalog.entry(for: config.modelID).displayName
            ),
            speechDetector: try makeSpeechDetector()
        )

        // Starting the helper loads the weights; the first request also compiles
        // the audio encoder's kernels. Pay both here, behind the load spinner,
        // instead of on the user's first sentence.
        let started = DispatchTime.now()
        do {
            _ = try await decode(Qwen3ASR.warmupAudio, model: model)
        } catch {
            await server.stop()
            throw error
        }
        self.model = model
        AppLogger.shared.log(
            .info,
            String(format: "qwen3-asr loaded in %.2fs", Self.seconds(since: started))
        )
    }

    // `purpose` is `.final` or `.meeting`: this family opts out of the live preview.
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

        // Capture runs at the device's native rate (typically 48 kHz).
        let audio = try AudioResampler.resample(samples, from: max(8_000, sampleRate), to: Qwen3ASR.sampleRate)
        let duration = Double(audio.count) / Double(Qwen3ASR.sampleRate)
        let allChunks = Qwen3ASR.chunker.split(audio)
        let chunks = allChunks.filter { model.speechDetector.containsSpeech(Array(audio[$0])) }
        if purpose.writesDecodeLog {
            AppLogger.shared.log(
                .info,
                String(
                    format: "qwen3-asr transcribe start duration=%.2fs chunks=%d skipped=%d",
                    duration,
                    chunks.count,
                    allChunks.count - chunks.count
                )
            )
        }
        var replies: [Qwen3ASR.Reply] = []
        for (index, chunk) in chunks.enumerated() {
            onProgress(TranscriptionProgress(chunk: index + 1, totalChunks: chunks.count))
            replies.append(try await decode(Array(audio[chunk]), model: model))
        }

        let text = Qwen3ASR.joinReplies(replies)
        if purpose.writesDecodeLog {
            AppLogger.shared.log(.info, "qwen3-asr transcribe done chars=\(text.count)")
        }
        return text
    }

    func unloadModel() async {
        model = nil
        await server.stop()
    }

    private func decode(_ audio: [Float], model: LoadedModel) async throws -> Qwen3ASR.Reply {
        let started = DispatchTime.now()
        let result: ChatCompletionResult
        do {
            result = try await server.complete(
                Qwen3ASR.makePayload(samples: audio, modelName: model.launch.modelName),
                launch: model.launch,
                startupTimeoutSeconds: Qwen3ASR.startupTimeoutSeconds,
                idleTimeoutSeconds: 0,
                timeoutSeconds: Qwen3ASR.timeoutSeconds(sampleCount: audio.count)
            )
        } catch let error as LlamaServerError {
            throw ServiceError.serverFailed(error.logValue)
        } catch let error as ChatCompletionError {
            throw ServiceError.requestFailed(error.logValue)
        }

        let reply = Qwen3ASR.parseReply(result.text)
        AppLogger.shared.log(
            .info,
            String(
                format: "qwen3-asr chunk done seconds=%.2f language=%@ prompt_tokens=%d predicted_tokens=%d finish=%@ in %.2fs",
                Double(audio.count) / Double(Qwen3ASR.sampleRate),
                reply.language ?? "none",
                result.timings?.promptTokens ?? -1,
                result.timings?.predictedTokens ?? -1,
                result.finishReason ?? "unknown",
                Self.seconds(since: started)
            )
        )
        if result.finishReason == ChatCompletionResult.lengthStop {
            AppLogger.shared.log(.warning, "qwen3-asr reply stopped at the token cap; the chunk transcript may be cut short")
        }
        return reply
    }

    private static func seconds(since start: DispatchTime) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e9
    }
}
