import XCTest
@testable import Suniye

/// The Qwen3-ASR engine against a fake llama-server (`FakeLlamaServer`), so the
/// whole load → request → parse path runs without the 2.5 GB model.
final class Qwen3ASRTranscriptionServiceTests: XCTestCase {
    private static let reply = "language English<asr_text>Hello from Qwen."

    func testLoadWarmsTheHelperThenTranscribesCapturedAudio() async throws {
        let fixture = try makeFixture()
        let service = Qwen3ASRTranscriptionService(makeSpeechDetector: { StubSpeechDetector(result: true) })

        try await service.loadModel(config: fixture.config)

        XCTAssertEqual(FakeLlamaServer.count(of: "start", at: fixture.logURL), 1)
        XCTAssertEqual(FakeLlamaServer.count(of: "request", at: fixture.logURL), 1, "load sends one warm-up request")

        let recorder = LockedRecorder<TranscriptionProgress>()
        let samples = [Float](repeating: 0.1, count: 2 * 48_000)
        let text = try await service.transcribe(samples: samples, sampleRate: 48_000) { recorder.record($0) }

        XCTAssertEqual(text, "Hello from Qwen.")
        XCTAssertEqual(recorder.values, [TranscriptionProgress(chunk: 1, totalChunks: 1)])
        XCTAssertEqual(FakeLlamaServer.count(of: "start", at: fixture.logURL), 1, "the helper stays up between requests")
        let body = try FakeLlamaServer.requestBody(2, in: fixture.directory)
        let wav = try XCTUnwrap(Self.wav(in: body))
        let resampled = try AudioResampler.resample(samples, from: 48_000, to: 16_000)
        XCTAssertEqual(wav, Qwen3ASR.wavData(samples: resampled), "the helper gets the clip resampled to 16 kHz")

        await service.unloadModel()
        XCTAssertTrue(FakeLlamaServer.logContents(at: fixture.logURL).contains("term"), "unload stops the helper")
    }

    func testClipsWithoutSpeechNeverReachTheHelper() async throws {
        let fixture = try makeFixture()
        let detector = StubSpeechDetector(result: false)
        let service = Qwen3ASRTranscriptionService(makeSpeechDetector: { detector })
        try await service.loadModel(config: fixture.config)

        let samples = [Float](repeating: 0, count: 48_000)
        let text = try await service.transcribe(samples: samples, sampleRate: 48_000)

        XCTAssertEqual(text, "")
        XCTAssertEqual(detector.clipLengths, [try AudioResampler.resample(samples, from: 48_000, to: 16_000).count], "the detector sees the 16 kHz clip")
        XCTAssertEqual(FakeLlamaServer.count(of: "request", at: fixture.logURL), 1, "only the warm-up request")
        await service.unloadModel()
    }

    func testLongDictationIsDecodedInChunks() async throws {
        let fixture = try makeFixture()
        let service = Qwen3ASRTranscriptionService(makeSpeechDetector: { StubSpeechDetector(result: true) })
        try await service.loadModel(config: fixture.config)

        let recorder = LockedRecorder<TranscriptionProgress>()
        let samples = [Float](repeating: 0.1, count: 100 * 16_000)
        let text = try await service.transcribe(samples: samples, sampleRate: 16_000) { recorder.record($0) }

        XCTAssertEqual(text, "Hello from Qwen. Hello from Qwen.")
        XCTAssertEqual(recorder.values, [TranscriptionProgress(chunk: 1, totalChunks: 2), TranscriptionProgress(chunk: 2, totalChunks: 2)])
        XCTAssertEqual(FakeLlamaServer.count(of: "request", at: fixture.logURL), 3)
        await service.unloadModel()
    }

    func testHelperThatDiesIsRestartedForTheNextDictation() async throws {
        let fixture = try makeFixture()
        let service = Qwen3ASRTranscriptionService(makeSpeechDetector: { StubSpeechDetector(result: true) })
        try await service.loadModel(config: fixture.config)

        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-f", fixture.helperURL.path]
        let output = Pipe()
        pgrep.standardOutput = output
        try pgrep.run()
        let printed = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        pgrep.waitUntilExit()
        let helperPID = try XCTUnwrap(pid_t(printed.trimmingCharacters(in: .whitespacesAndNewlines)))
        XCTAssertEqual(Darwin.kill(helperPID, SIGKILL), 0)
        let reaped = await waitUntil { Darwin.kill(helperPID, 0) != 0 }
        XCTAssertTrue(reaped, "the dead helper should be reaped")

        let text = try await service.transcribe(samples: [Float](repeating: 0.1, count: 16_000), sampleRate: 16_000)

        XCTAssertEqual(text, "Hello from Qwen.")
        XCTAssertEqual(FakeLlamaServer.count(of: "start", at: fixture.logURL), 2)
        await service.unloadModel()
    }

    func testLengthStopStillReturnsTheTranscript() async throws {
        let fixture = try makeFixture(finishReason: "length")
        let service = Qwen3ASRTranscriptionService(makeSpeechDetector: { StubSpeechDetector(result: true) })
        try await service.loadModel(config: fixture.config)

        let text = try await service.transcribe(samples: [Float](repeating: 0.1, count: 16_000), sampleRate: 16_000)

        XCTAssertEqual(text, "Hello from Qwen.")
        await service.unloadModel()
    }

    func testHelperThatCannotStartFailsTheLoad() async throws {
        let fixture = try makeFixture()
        let helperURL = fixture.directory.appendingPathComponent("exiting-helper")
        try "#!/bin/sh\nexit 3\n".write(to: helperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperURL.path)
        overrideHelperPath(helperURL)
        let service = Qwen3ASRTranscriptionService(makeSpeechDetector: { StubSpeechDetector(result: true) })

        do {
            try await service.loadModel(config: fixture.config)
            XCTFail("Expected serverFailed")
        } catch let error as Qwen3ASRTranscriptionService.ServiceError {
            XCTAssertEqual(error, .serverFailed("server_exited_3"))
        }
        do {
            _ = try await service.transcribe(samples: [0.1], sampleRate: 16_000)
            XCTFail("Expected notLoaded after a failed load")
        } catch let error as Qwen3ASRTranscriptionService.ServiceError {
            XCTAssertEqual(error, .notLoaded)
        }
    }

    func testFailedWarmUpStopsTheHelper() async throws {
        let fixture = try makeFixture(completionStatus: 500)
        let service = Qwen3ASRTranscriptionService(makeSpeechDetector: { StubSpeechDetector(result: true) })

        do {
            try await service.loadModel(config: fixture.config)
            XCTFail("Expected requestFailed")
        } catch let error as Qwen3ASRTranscriptionService.ServiceError {
            XCTAssertEqual(error, .requestFailed("provider_error"))
        }
        XCTAssertTrue(FakeLlamaServer.logContents(at: fixture.logURL).contains("term"), "a helper with no loaded model must not keep its memory")
    }

    func testDetectorFailureFailsTheLoadBeforeStartingTheHelper() async throws {
        let fixture = try makeFixture()
        let service = Qwen3ASRTranscriptionService(makeSpeechDetector: { throw SpeechDetector.DetectorError.modelMissing("silero_vad_v5.onnx") })

        do {
            try await service.loadModel(config: fixture.config)
            XCTFail("Expected the detector error")
        } catch let error as SpeechDetector.DetectorError {
            XCTAssertEqual(error, .modelMissing("silero_vad_v5.onnx"))
        }
        XCTAssertEqual(FakeLlamaServer.count(of: "start", at: fixture.logURL), 0)
    }

    func testDefaultDetectorIsTheBundledModel() async throws {
        let fixture = try makeFixture()
        let service = Qwen3ASRTranscriptionService()
        try await service.loadModel(config: fixture.config)

        let text = try await service.transcribe(samples: [Float](repeating: 0, count: 16_000), sampleRate: 16_000)

        XCTAssertEqual(text, "", "the real detector rejects silence")
        XCTAssertEqual(FakeLlamaServer.count(of: "request", at: fixture.logURL), 1)
        await service.unloadModel()
    }

    func testGuards() async throws {
        let fixture = try makeFixture()
        let service = Qwen3ASRTranscriptionService(makeSpeechDetector: { StubSpeechDetector(result: true) })

        await assertThrows(.notLoaded) { _ = try await service.transcribe(samples: [0.1], sampleRate: 16_000) }
        await assertThrows(.invalidConfiguration) {
            try await service.loadModel(config: RecognizerConfig(modelID: .qwen3ASR17B, family: .qwen3ASR, tokensPath: "", numThreads: 1))
        }
        await assertThrows(.missingModelFile("/nope/model.gguf")) {
            try await service.loadModel(config: RecognizerConfig(
                modelID: .qwen3ASR17B,
                family: .qwen3ASR,
                tokensPath: "/nope/model.gguf",
                numThreads: 1,
                encoderPath: fixture.config.encoderPath,
                modelPath: "/nope/model.gguf"
            ))
        }

        try await service.loadModel(config: fixture.config)
        await assertThrows(.emptyAudio) { _ = try await service.transcribe(samples: [], sampleRate: 16_000) }
        await service.unloadModel()
        await assertThrows(.notLoaded) { _ = try await service.transcribe(samples: [0.1], sampleRate: 16_000) }
    }

    func testErrorDescriptions() {
        typealias E = Qwen3ASRTranscriptionService.ServiceError
        XCTAssertEqual(E.notLoaded.errorDescription, "Qwen3-ASR is not loaded")
        XCTAssertEqual(E.emptyAudio.errorDescription, "No audio captured")
        XCTAssertEqual(E.invalidConfiguration.errorDescription, "The selected model files are incomplete")
        XCTAssertEqual(E.missingModelFile("/m.gguf").errorDescription, "Required model file is missing: /m.gguf")
        XCTAssertEqual(E.runtimeUnavailable.errorDescription, "The bundled llama-server helper is missing")
        XCTAssertEqual(E.serverFailed("startup_timeout").errorDescription, "The Qwen3-ASR helper failed to start: startup_timeout")
        XCTAssertEqual(E.requestFailed("timeout").errorDescription, "The Qwen3-ASR helper failed to transcribe: timeout")
    }

    // MARK: - Helpers

    private struct Fixture {
        let directory: URL
        let logURL: URL
        let helperURL: URL
        let config: RecognizerConfig
    }

    private func makeFixture(finishReason: String = "stop", completionStatus: Int = 200) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("suniye-qwen3-asr-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let logURL = directory.appendingPathComponent("helper.log")
        let helperURL = try FakeLlamaServer.make(
            in: directory,
            logURL: logURL,
            reply: Self.reply,
            finishReason: finishReason,
            completionStatus: completionStatus
        )
        overrideHelperPath(helperURL)

        let modelURL = directory.appendingPathComponent("model.gguf")
        let projectorURL = directory.appendingPathComponent("mmproj.gguf")
        for url in [modelURL, projectorURL] {
            try Data("gguf".utf8).write(to: url)
        }
        let config = RecognizerConfig(
            modelID: .qwen3ASR17B,
            family: .qwen3ASR,
            tokensPath: modelURL.path,
            numThreads: 4,
            encoderPath: projectorURL.path,
            modelPath: modelURL.path
        )
        return Fixture(directory: directory, logURL: logURL, helperURL: helperURL, config: config)
    }

    private func overrideHelperPath(_ helperURL: URL) {
        let previousHelperPath = getenv("SUNIYE_LLAMA_SERVER_PATH").map { String(cString: $0) }
        setenv("SUNIYE_LLAMA_SERVER_PATH", helperURL.path, 1)
        addTeardownBlock {
            if let previousHelperPath {
                setenv("SUNIYE_LLAMA_SERVER_PATH", previousHelperPath, 1)
            } else {
                unsetenv("SUNIYE_LLAMA_SERVER_PATH")
            }
        }
    }

    private func assertThrows(
        _ expected: Qwen3ASRTranscriptionService.ServiceError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as Qwen3ASRTranscriptionService.ServiceError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    private func waitUntil(timeout: TimeInterval = 10, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    private static func wav(in body: [String: Any]) -> Data? {
        guard let messages = body["messages"] as? [[String: Any]],
              let parts = messages.last?["content"] as? [[String: Any]],
              let audio = parts.first?["input_audio"] as? [String: String],
              let base64 = audio["data"] else {
            return nil
        }
        return Data(base64Encoded: base64)
    }
}

private final class StubSpeechDetector: SpeechDetecting {
    let result: Bool
    private(set) var clipLengths: [Int] = []

    init(result: Bool) {
        self.result = result
    }

    func containsSpeech(_ samples: [Float]) -> Bool {
        clipLengths.append(samples.count)
        return result
    }
}
