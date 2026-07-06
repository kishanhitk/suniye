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
        let router = RoutingTranscriptionService(sherpaService: sherpa, appleService: apple)

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
        let router = RoutingTranscriptionService(sherpaService: sherpa, appleService: apple)

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
        let router = RoutingTranscriptionService(sherpaService: sherpa, appleService: apple)

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
        let router = RoutingTranscriptionService(sherpaService: sherpa, appleService: apple)

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
        let router = RoutingTranscriptionService(sherpaService: sherpa, appleService: nil)

        try await router.loadModel(config: config(family: .nemoTransducer, modelID: .parakeetV3))
        try await router.loadModel(config: config(family: .whisper, modelID: .whisperLargeV3Turbo))

        XCTAssertEqual(sherpa.loadCallCount, 2)
        XCTAssertEqual(sherpa.unloadCallCount, 0, "staying on the sherpa engine should not unload it")
    }

    func testAppleFamilyWithoutAppleServiceThrows() async {
        let sherpa = StubTranscriptionService()
        let router = RoutingTranscriptionService(sherpaService: sherpa, appleService: nil)

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
        let router = RoutingTranscriptionService(sherpaService: StubTranscriptionService(), appleService: nil)

        do {
            _ = try await router.transcribe(samples: [0.1], sampleRate: 16_000)
            XCTFail("Expected transcribe to throw before a model is loaded")
        } catch {
            // Expected: no active engine.
        }
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
        let router = RoutingTranscriptionService(sherpaService: sherpa, appleService: nil)

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
