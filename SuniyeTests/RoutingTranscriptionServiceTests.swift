import XCTest
@testable import Suniye

// StubTranscriptionService is @MainActor (its consuming tests run on the main
// actor), so this suite must be too, to touch the stub's call-count properties.
@MainActor
final class RoutingTranscriptionServiceTests: XCTestCase {
    private func config(family: ASRModelFamily, modelID: ASRModelID) -> RecognizerConfig {
        RecognizerConfig(modelID: modelID, family: family, tokensPath: "", numThreads: 1)
    }

    func testRoutesSherpaFamilyToSherpaService() async throws {
        let sherpa = StubTranscriptionService()
        sherpa.transcribeResult = .success("sherpa-text")
        let apple = StubTranscriptionService()
        apple.transcribeResult = .success("apple-text")
        let router = RoutingTranscriptionService(sherpaService: sherpa, appleService: apple, makeSpeechDetector: { StubSpeechDetector(result: true) })

        try await router.loadModel(config: config(family: .nemoTransducer, modelID: .parakeetV3))
        let text = try await router.transcribe(samples: [0.1], sampleRate: 16_000)

        XCTAssertEqual(text, "sherpa-text")
        XCTAssertEqual(sherpa.loadCallCount, 1)
        XCTAssertEqual(sherpa.transcribeCallCount, 1)
        XCTAssertEqual(apple.loadCallCount, 0)
        XCTAssertEqual(apple.transcribeCallCount, 0)
    }

    func testRoutesAppleFamilyToAppleService() async throws {
        let sherpa = StubTranscriptionService()
        sherpa.transcribeResult = .success("sherpa-text")
        let apple = StubTranscriptionService()
        apple.transcribeResult = .success("apple-text")
        let router = RoutingTranscriptionService(sherpaService: sherpa, appleService: apple, makeSpeechDetector: { StubSpeechDetector(result: true) })

        try await router.loadModel(config: config(family: .appleSpeech, modelID: .appleSpeech))
        let text = try await router.transcribe(samples: [0.1], sampleRate: 16_000)

        XCTAssertEqual(text, "apple-text")
        XCTAssertEqual(apple.loadCallCount, 1)
        XCTAssertEqual(sherpa.loadCallCount, 0)
        XCTAssertEqual(sherpa.transcribeCallCount, 0)
    }

    func testSwitchingEnginesUnloadsPreviousEngine() async throws {
        let sherpa = StubTranscriptionService()
        let apple = StubTranscriptionService()
        let router = RoutingTranscriptionService(sherpaService: sherpa, appleService: apple, makeSpeechDetector: { StubSpeechDetector(result: true) })

        try await router.loadModel(config: config(family: .nemoTransducer, modelID: .parakeetV3))
        try await router.loadModel(config: config(family: .appleSpeech, modelID: .appleSpeech))

        XCTAssertEqual(sherpa.unloadCallCount, 1, "sherpa engine should be unloaded when switching to Apple")
        XCTAssertEqual(apple.loadCallCount, 1)
    }

    func testFailedCrossEngineLoadPreservesPreviousEngine() async throws {
        let sherpa = StubTranscriptionService()
        sherpa.transcribeResult = .success("sherpa-text")
        let apple = StubTranscriptionService()
        apple.loadModelResult = .failure(FakeError(message: "asset install failed"))
        let router = RoutingTranscriptionService(sherpaService: sherpa, appleService: apple, makeSpeechDetector: { StubSpeechDetector(result: true) })

        try await router.loadModel(config: config(family: .nemoTransducer, modelID: .parakeetV3))

        // Switching to Apple fails to load; the working sherpa engine must survive.
        do {
            try await router.loadModel(config: config(family: .appleSpeech, modelID: .appleSpeech))
            XCTFail("Expected the Apple load to fail")
        } catch {
            // Expected.
        }

        XCTAssertEqual(sherpa.unloadCallCount, 0, "the previously loaded engine must not be unloaded on a failed switch")
        let text = try await router.transcribe(samples: [0.1], sampleRate: 16_000)
        XCTAssertEqual(text, "sherpa-text", "still transcribing via the surviving sherpa engine")
    }

    func testReloadingSameEngineDoesNotUnload() async throws {
        let sherpa = StubTranscriptionService()
        let router = RoutingTranscriptionService(sherpaService: sherpa, appleService: nil, makeSpeechDetector: { StubSpeechDetector(result: true) })

        try await router.loadModel(config: config(family: .nemoTransducer, modelID: .parakeetV3))
        try await router.loadModel(config: config(family: .whisper, modelID: .whisperLargeV3Turbo))

        XCTAssertEqual(sherpa.loadCallCount, 2)
        XCTAssertEqual(sherpa.unloadCallCount, 0, "staying on the sherpa engine should not unload it")
    }

    func testAppleFamilyWithoutAppleServiceThrows() async {
        let sherpa = StubTranscriptionService()
        let router = RoutingTranscriptionService(sherpaService: sherpa, appleService: nil, makeSpeechDetector: { StubSpeechDetector(result: true) })

        do {
            try await router.loadModel(config: config(family: .appleSpeech, modelID: .appleSpeech))
            XCTFail("Expected loadModel to throw when Apple Speech is unavailable")
        } catch let error as RoutingTranscriptionService.RoutingError {
            guard case .appleSpeechUnavailable = error else {
                return XCTFail("Unexpected routing error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(sherpa.loadCallCount, 0)
    }

    func testTranscribeBeforeLoadThrows() async {
        let router = RoutingTranscriptionService(sherpaService: StubTranscriptionService(), appleService: nil, makeSpeechDetector: { StubSpeechDetector(result: true) })

        do {
            _ = try await router.transcribe(samples: [0.1], sampleRate: 16_000)
            XCTFail("Expected transcribe to throw before a model is loaded")
        } catch {
            // Expected: no active engine.
        }
    }

    func testClipWithoutSpeechNeverReachesTheEngine() async throws {
        let sherpa = StubTranscriptionService()
        sherpa.transcribeResult = .success("Thank you.")
        let detector = StubSpeechDetector(result: false)
        let router = RoutingTranscriptionService(sherpaService: sherpa, appleService: nil, makeSpeechDetector: { detector })
        try await router.loadModel(config: config(family: .nemoTransducer, modelID: .parakeetV3))
        let samples = [Float](repeating: 0.01, count: 48_000)

        do {
            _ = try await router.transcribe(samples: samples, sampleRate: 48_000)
            XCTFail("A final clip without speech must throw NoSpeechDetected")
        } catch {
            XCTAssertTrue(error is NoSpeechDetected, "\(error)")
        }
        let partial = try await router.transcribe(samples: samples, sampleRate: 48_000, purpose: .partial)

        XCTAssertEqual(partial, "")
        XCTAssertEqual(sherpa.transcribeCallCount, 0)
        let resampled = try AudioResampler.resample(samples, from: 48_000, to: 16_000).count
        XCTAssertEqual(detector.clipLengths, [resampled, resampled], "the detector hears the clip at 16 kHz")
    }

    func testClipWithSpeechReachesTheEngineAtItsOwnRate() async throws {
        let sherpa = StubTranscriptionService()
        sherpa.transcribeResult = .success("hello")
        let router = RoutingTranscriptionService(sherpaService: sherpa, appleService: nil, makeSpeechDetector: { StubSpeechDetector(result: true) })
        try await router.loadModel(config: config(family: .nemoTransducer, modelID: .parakeetV3))
        let samples = [Float](repeating: 0.01, count: 48_000)

        let text = try await router.transcribe(samples: samples, sampleRate: 48_000)

        XCTAssertEqual(text, "hello")
        XCTAssertEqual(sherpa.lastTranscribeInput?.samples, samples)
        XCTAssertEqual(sherpa.lastTranscribeInput?.sampleRate, 48_000)
    }

    func testProbeReachesTheEngineWithoutASpeechCheck() async throws {
        let apple = StubTranscriptionService()
        let detector = StubSpeechDetector(result: false)
        let router = RoutingTranscriptionService(sherpaService: StubTranscriptionService(), appleService: apple, makeSpeechDetector: { detector })
        try await router.loadModel(config: config(family: .appleSpeech, modelID: .appleSpeech))

        _ = try await router.transcribe(samples: [Float](repeating: 0, count: 16_000), sampleRate: 16_000, purpose: .probe)

        XCTAssertEqual(apple.transcribePurposes, [.probe])
        XCTAssertEqual(detector.clipLengths, [])
    }

    func testFailedDetectorFailsTheLoadAndIsTriedAgain() async throws {
        let sherpa = StubTranscriptionService()
        sherpa.transcribeResult = .success("hello")
        var attempts = 0
        let router = RoutingTranscriptionService(sherpaService: sherpa, appleService: nil, makeSpeechDetector: {
            attempts += 1
            if attempts == 1 {
                throw SpeechDetector.DetectorError.modelMissing("silero_vad_v5.onnx")
            }
            return StubSpeechDetector(result: true)
        })

        do {
            try await router.loadModel(config: config(family: .nemoTransducer, modelID: .parakeetV3))
            XCTFail("Expected the detector error")
        } catch let error as SpeechDetector.DetectorError {
            XCTAssertEqual(error, .modelMissing("silero_vad_v5.onnx"))
        }
        XCTAssertEqual(sherpa.loadCallCount, 0, "no engine loads without a detector")

        try await router.loadModel(config: config(family: .nemoTransducer, modelID: .parakeetV3))
        try await router.loadModel(config: config(family: .whisper, modelID: .whisperLargeV3Turbo))
        let text = try await router.transcribe(samples: [0.1], sampleRate: 16_000)

        XCTAssertEqual(text, "hello")
        XCTAssertEqual(attempts, 2, "a working detector is kept across loads")
    }

    func testDefaultInitDoesNotCrash() {
        // Exercises the default dependency wiring (real sherpa service + OS-gated Apple).
        _ = RoutingTranscriptionService()
    }

    func testMakeAppleServiceReflectsSupport() {
        let service = RoutingTranscriptionService.makeAppleServiceIfSupported()
        XCTAssertEqual(service != nil, AppleSpeechSupport.isAvailable)
    }

    func testAppleUnavailableErrorHasMessage() {
        let message = RoutingTranscriptionService.RoutingError.appleSpeechUnavailable.errorDescription
        XCTAssertEqual(message, "Apple Speech requires macOS 26 or later")
    }

    func testUnloadClearsActiveEngine() async throws {
        let sherpa = StubTranscriptionService()
        let router = RoutingTranscriptionService(sherpaService: sherpa, appleService: nil, makeSpeechDetector: { StubSpeechDetector(result: true) })

        try await router.loadModel(config: config(family: .nemoTransducer, modelID: .parakeetV3))
        await router.unloadModel()

        XCTAssertEqual(sherpa.unloadCallCount, 1)
        do {
            _ = try await router.transcribe(samples: [0.1], sampleRate: 16_000)
            XCTFail("Expected transcribe to throw after unload")
        } catch {
            // Expected: engine cleared.
        }
    }
}
