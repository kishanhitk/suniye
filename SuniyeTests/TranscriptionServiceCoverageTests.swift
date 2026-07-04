import XCTest
@testable import Suniye

final class TranscriptionServiceCoverageTests: XCTestCase {
    private let fileManager = FileManager.default
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("suniye-transcription-coverage-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? fileManager.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        try super.tearDownWithError()
    }

    private func path(_ name: String) -> String {
        tempDirectory.appendingPathComponent(name).path
    }

    private func writeDummyFile(_ name: String, contents: String = "garbage-bytes") throws -> String {
        let url = tempDirectory.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url.path
    }

    // MARK: - AudioRecognitionPreprocessor

    func testStatsOfEmptyInputIsZero() {
        let stats = AudioRecognitionPreprocessor.stats(of: [])
        XCTAssertEqual(stats.rms, 0)
        XCTAssertEqual(stats.peak, 0)
    }

    // MARK: - ServiceError descriptions

    func testServiceErrorDescriptions() {
        XCTAssertEqual(
            TranscriptionService.ServiceError.recognizerNotLoaded.errorDescription,
            "Recognizer is not loaded"
        )
        XCTAssertEqual(
            TranscriptionService.ServiceError.emptyAudio.errorDescription,
            "No audio captured"
        )
        XCTAssertEqual(
            TranscriptionService.ServiceError.missingModelFile("/x/tokens.txt").errorDescription,
            "Required model file is missing: /x/tokens.txt"
        )
        XCTAssertEqual(
            TranscriptionService.ServiceError.invalidRecognizerConfiguration.errorDescription,
            "The selected model files are incomplete"
        )
        XCTAssertEqual(
            TranscriptionService.ServiceError.recognizerCreationFailed("boom").errorDescription,
            "Failed to create sherpa-onnx offline recognizer: boom"
        )
        XCTAssertEqual(
            TranscriptionService.ServiceError.recognizerCreationFailed("").errorDescription,
            "Failed to create sherpa-onnx offline recognizer"
        )
        XCTAssertEqual(
            TranscriptionService.ServiceError.recognizerCreationFailed(nil).errorDescription,
            "Failed to create sherpa-onnx offline recognizer"
        )
        XCTAssertEqual(
            TranscriptionService.ServiceError.streamCreationFailed.errorDescription,
            "Failed to create sherpa-onnx offline stream"
        )
        XCTAssertEqual(
            TranscriptionService.ServiceError.decodeResultUnavailable.errorDescription,
            "Failed to read recognition result from sherpa-onnx"
        )
    }

    // MARK: - Guard paths without a loaded model

    func testTranscribeWithoutLoadedModelThrowsRecognizerNotLoaded() async {
        let service = TranscriptionService()
        do {
            _ = try await service.transcribe(samples: [0.1, 0.2], sampleRate: 16_000)
            XCTFail("Expected recognizerNotLoaded")
        } catch let error as TranscriptionService.ServiceError {
            guard case .recognizerNotLoaded = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testUnloadModelWithoutLoadedRecognizerIsANoOp() async {
        let service = TranscriptionService()
        await service.unloadModel()
        // Still not loaded afterwards.
        do {
            _ = try await service.transcribe(samples: [0.1], sampleRate: 16_000)
            XCTFail("Expected recognizerNotLoaded")
        } catch {
            // expected
        }
    }

    // MARK: - validateModelPaths per family

    func testLoadSenseVoiceFailsFastForMissingModelFile() async throws {
        let service = TranscriptionService()
        let tokensPath = try writeDummyFile("tokens.txt")
        let missingModelPath = path("model.int8.onnx")

        let config = RecognizerConfig(
            modelID: .senseVoice,
            family: .senseVoice,
            tokensPath: tokensPath,
            numThreads: 4,
            modelPath: missingModelPath,
            language: "auto",
            useInverseTextNormalization: true
        )

        do {
            try await service.loadModel(config: config)
            XCTFail("Expected missingModelFile")
        } catch let error as TranscriptionService.ServiceError {
            guard case let .missingModelFile(missing) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(missing, missingModelPath)
        }
    }

    func testLoadWhisperFailsFastForMissingDecoder() async throws {
        let service = TranscriptionService()
        let tokensPath = try writeDummyFile("turbo-tokens.txt")
        let encoderPath = try writeDummyFile("turbo-encoder.int8.onnx")
        let missingDecoderPath = path("turbo-decoder.int8.onnx")

        let config = RecognizerConfig(
            modelID: .whisperLargeV3Turbo,
            family: .whisper,
            tokensPath: tokensPath,
            numThreads: 4,
            encoderPath: encoderPath,
            decoderPath: missingDecoderPath,
            language: "en",
            task: "transcribe"
        )

        do {
            try await service.loadModel(config: config)
            XCTFail("Expected missingModelFile")
        } catch let error as TranscriptionService.ServiceError {
            guard case let .missingModelFile(missing) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(missing, missingDecoderPath)
        }
    }

    // MARK: - loadModel with unparseable model files

    func testLoadModelWithGarbageFilesThrowsRecognizerCreationFailed() async throws {
        let service = TranscriptionService()
        let tokensPath = try writeDummyFile("tokens.txt", contents: "<blk> 0\na 1\n")
        let encoderPath = try writeDummyFile("encoder.int8.onnx")
        let decoderPath = try writeDummyFile("decoder.int8.onnx")
        let joinerPath = try writeDummyFile("joiner.int8.onnx")

        let config = RecognizerConfig(
            modelID: .parakeetV3,
            family: .nemoTransducer,
            tokensPath: tokensPath,
            numThreads: 1,
            encoderPath: encoderPath,
            decoderPath: decoderPath,
            joinerPath: joinerPath,
            modelType: "nemo_transducer"
        )

        do {
            try await service.loadModel(config: config)
            XCTFail("Expected recognizerCreationFailed for unparseable model files")
        } catch let error as TranscriptionService.ServiceError {
            guard case .recognizerCreationFailed = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertNotNil(error.errorDescription)
        }
    }

    // MARK: - makeRecognizerConfig happy paths

    func testMakeRecognizerConfigForNemoTransducer() async throws {
        let service = TranscriptionService()
        let config = RecognizerConfig(
            modelID: .parakeetV3,
            family: .nemoTransducer,
            tokensPath: "/models/tokens.txt",
            numThreads: 4,
            encoderPath: "/models/encoder.onnx",
            decoderPath: "/models/decoder.onnx",
            joinerPath: "/models/joiner.onnx",
            modelType: "nemo_transducer"
        )

        let native = try await service.makeRecognizerConfig(for: config)

        XCTAssertEqual(native.max_active_paths, 4)
        XCTAssertEqual(native.feat_config.sample_rate, 16_000)
        XCTAssertEqual(native.feat_config.feature_dim, 80)
        XCTAssertEqual(native.model_config.num_threads, 4)
        XCTAssertEqual(String(cString: native.decoding_method), "greedy_search")
        XCTAssertEqual(String(cString: native.model_config.tokens), "/models/tokens.txt")
        XCTAssertEqual(String(cString: native.model_config.model_type), "nemo_transducer")
        XCTAssertEqual(String(cString: native.model_config.transducer.encoder), "/models/encoder.onnx")
        XCTAssertEqual(String(cString: native.model_config.transducer.decoder), "/models/decoder.onnx")
        XCTAssertEqual(String(cString: native.model_config.transducer.joiner), "/models/joiner.onnx")
    }

    func testMakeRecognizerConfigForMoonshine() async throws {
        let service = TranscriptionService()
        let config = RecognizerConfig(
            modelID: .moonshineBase,
            family: .moonshine,
            tokensPath: "/models/tokens.txt",
            numThreads: 0, // clamped up to 1
            encoderPath: "/models/encode.onnx",
            preprocessorPath: "/models/preprocess.onnx",
            uncachedDecoderPath: "/models/uncached.onnx",
            cachedDecoderPath: "/models/cached.onnx"
        )

        let native = try await service.makeRecognizerConfig(for: config)

        XCTAssertEqual(native.model_config.num_threads, 1)
        XCTAssertEqual(String(cString: native.model_config.moonshine.preprocessor), "/models/preprocess.onnx")
        XCTAssertEqual(String(cString: native.model_config.moonshine.encoder), "/models/encode.onnx")
        XCTAssertEqual(String(cString: native.model_config.moonshine.uncached_decoder), "/models/uncached.onnx")
        XCTAssertEqual(String(cString: native.model_config.moonshine.cached_decoder), "/models/cached.onnx")
    }

    func testMakeRecognizerConfigForSenseVoice() async throws {
        let service = TranscriptionService()
        let config = RecognizerConfig(
            modelID: .senseVoice,
            family: .senseVoice,
            tokensPath: "/models/tokens.txt",
            numThreads: 2,
            modelPath: "/models/model.onnx",
            language: "auto",
            useInverseTextNormalization: true
        )

        let native = try await service.makeRecognizerConfig(for: config)

        XCTAssertEqual(native.model_config.num_threads, 2)
        XCTAssertEqual(String(cString: native.model_config.sense_voice.model), "/models/model.onnx")
        XCTAssertEqual(String(cString: native.model_config.sense_voice.language), "auto")
        XCTAssertEqual(native.model_config.sense_voice.use_itn, 1)
    }

    func testMakeRecognizerConfigForWhisper() async throws {
        let service = TranscriptionService()
        let config = RecognizerConfig(
            modelID: .whisperLargeV3Turbo,
            family: .whisper,
            tokensPath: "/models/turbo-tokens.txt",
            numThreads: 4,
            encoderPath: "/models/turbo-encoder.onnx",
            decoderPath: "/models/turbo-decoder.onnx",
            language: "en",
            task: "transcribe"
        )

        let native = try await service.makeRecognizerConfig(for: config)

        XCTAssertEqual(String(cString: native.model_config.whisper.encoder), "/models/turbo-encoder.onnx")
        XCTAssertEqual(String(cString: native.model_config.whisper.decoder), "/models/turbo-decoder.onnx")
        XCTAssertEqual(String(cString: native.model_config.whisper.language), "en")
        XCTAssertEqual(String(cString: native.model_config.whisper.task), "transcribe")
    }

    // MARK: - makeRecognizerConfig invalid configurations

    func testMakeRecognizerConfigThrowsWhenTransducerPathsMissing() async {
        let service = TranscriptionService()
        let config = RecognizerConfig(
            modelID: .parakeetV3,
            family: .nemoTransducer,
            tokensPath: "/models/tokens.txt",
            numThreads: 4,
            modelType: "nemo_transducer"
        )

        await assertInvalidConfiguration(service, config)
    }

    func testMakeRecognizerConfigThrowsWhenMoonshinePathsMissing() async {
        let service = TranscriptionService()
        let config = RecognizerConfig(
            modelID: .moonshineBase,
            family: .moonshine,
            tokensPath: "/models/tokens.txt",
            numThreads: 4,
            encoderPath: "/models/encode.onnx" // preprocessor and decoders missing
        )

        await assertInvalidConfiguration(service, config)
    }

    func testMakeRecognizerConfigThrowsWhenSenseVoiceModelMissing() async {
        let service = TranscriptionService()
        let config = RecognizerConfig(
            modelID: .senseVoice,
            family: .senseVoice,
            tokensPath: "/models/tokens.txt",
            numThreads: 4
        )

        await assertInvalidConfiguration(service, config)
    }

    func testMakeRecognizerConfigThrowsWhenWhisperPathsMissing() async {
        let service = TranscriptionService()
        let config = RecognizerConfig(
            modelID: .whisperLargeV3Turbo,
            family: .whisper,
            tokensPath: "/models/tokens.txt",
            numThreads: 4,
            encoderPath: "/models/encoder.onnx" // decoder missing
        )

        await assertInvalidConfiguration(service, config)
    }

    private func assertInvalidConfiguration(
        _ service: TranscriptionService,
        _ config: RecognizerConfig,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await service.makeRecognizerConfig(for: config)
            XCTFail("Expected invalidRecognizerConfiguration", file: file, line: line)
        } catch let error as TranscriptionService.ServiceError {
            guard case .invalidRecognizerConfiguration = error else {
                return XCTFail("Unexpected error: \(error)", file: file, line: line)
            }
        } catch {
            XCTFail("Unexpected error type: \(error)", file: file, line: line)
        }
    }
}
