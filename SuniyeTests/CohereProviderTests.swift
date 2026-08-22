import XCTest
@testable import Suniye

/// Catalog, routing, download-verification, and dictation-UI behaviour for the
/// Cohere Transcribe provider. The engine itself is covered model-free in
/// `CohereTranscribeDecodingTests` and against the real model in
/// `CohereTranscriptionServiceRealModelTests`.
@MainActor
final class CohereProviderTests: XCTestCase {
    private var entry: ASRModelCatalogEntry {
        ASRModelCatalog.entry(for: .cohereTranscribe)
    }

    // MARK: - Catalog

    func testEntryIsAnOptInRemoteFileDownload() throws {
        XCTAssertEqual(entry.family, .cohereTranscribe)
        XCTAssertFalse(entry.isSystemManaged)
        XCTAssertTrue(entry.isAvailableOnThisDevice)
        XCTAssertFalse(entry.family.supportsLivePreview)
        XCTAssertEqual(ASRModelCatalog.fallbackOrder.last, .cohereTranscribe, "never preferred over a lighter installed model")

        guard case let .remoteFiles(files) = entry.downloadSource else {
            return XCTFail("expected remote files")
        }
        XCTAssertEqual(files.count, 4)
        for file in files {
            XCTAssertEqual(file.sha256?.count, 64, file.destinationRelativePath)
            XCTAssertTrue(file.remoteURL.path.contains("/resolve/9ecc3a5e64b132ab094bada232650e49e4340ad2/"), "pinned to a commit")
        }
        XCTAssertEqual(files.compactMap(\.expectedSizeBytes).reduce(0, +), entry.estimatedSizeBytes)
        XCTAssertEqual(
            Set(files.map(\.destinationRelativePath)),
            Set(entry.manifest.requiredRelativePaths),
            "every downloaded file is required for the install to count, including the encoder's .data sidecar"
        )
    }

    func testPickerLabelsAreHonestAboutSpeed() {
        XCTAssertEqual(entry.speedLabel, "Slower")
        XCTAssertEqual(entry.qualityLabel, "Highest")
        XCTAssertTrue(entry.languageSummary.contains("14 languages"))
        XCTAssertTrue(entry.description.contains("slow"), entry.description)
    }

    func testManifestSidecarsCountAsRequired() {
        let manifest = ASRModelFileManifest(tokens: "t", encoder: "e", sidecars: ["e.data"])
        XCTAssertEqual(manifest.requiredRelativePaths, ["t", "e", "e.data"])
        XCTAssertEqual(ASRModelFileManifest(tokens: "t").requiredRelativePaths, ["t"])
    }

    func testRecognizerConfigCarriesEncoderDecoderAndTokens() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cohere-config-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = ModelManager(applicationSupportDirectory: root)

        let config = try manager.makeRecognizerConfig(for: .cohereTranscribe)

        XCTAssertEqual(config.family, .cohereTranscribe)
        XCTAssertTrue(config.tokensPath.hasSuffix("cohere-transcribe-03-2026-onnx-int8/tokens.txt"))
        XCTAssertTrue(config.encoderPath?.hasSuffix("cohere-encoder.int8.onnx") ?? false)
        XCTAssertTrue(config.decoderPath?.hasSuffix("cohere-decoder.int8.onnx") ?? false)
        XCTAssertNil(config.joinerPath)
    }

    // MARK: - Routing

    func testRouterSendsCohereFamilyToCohereEngine() async throws {
        let sherpa = StubTranscriptionService()
        let cohere = StubTranscriptionService()
        cohere.transcribeResult = .success("cohere-text")
        let router = RoutingTranscriptionService(sherpaService: sherpa, appleService: nil, cohereService: cohere)

        try await router.loadModel(config: RecognizerConfig(modelID: .cohereTranscribe, family: .cohereTranscribe, tokensPath: "", numThreads: 1))
        let text = try await router.transcribe(samples: [0.1], sampleRate: 16_000)

        XCTAssertEqual(text, "cohere-text")
        XCTAssertEqual(cohere.loadCallCount, 1)
        XCTAssertEqual(sherpa.loadCallCount, 0)

        try await router.loadModel(config: RecognizerConfig(modelID: .parakeetV3, family: .nemoTransducer, tokensPath: "", numThreads: 1))
        XCTAssertEqual(cohere.unloadCallCount, 1, "switching back to sherpa releases the 4 GB Cohere sessions")
    }

    func testRouterForwardsProgressToActiveEngine() async throws {
        let cohere = StubTranscriptionService()
        cohere.transcribeResult = .success("done")
        cohere.progressToReport = [TranscriptionProgress(chunk: 1, totalChunks: 2), TranscriptionProgress(chunk: 2, totalChunks: 2)]
        let router = RoutingTranscriptionService(sherpaService: StubTranscriptionService(), appleService: nil, cohereService: cohere)
        try await router.loadModel(config: RecognizerConfig(modelID: .cohereTranscribe, family: .cohereTranscribe, tokensPath: "", numThreads: 1))

        let recorder = TranscriptionProgressRecorder<TranscriptionProgress>()
        let text = try await router.transcribe(samples: [0.1], sampleRate: 16_000) { recorder.record($0) }

        XCTAssertEqual(text, "done")
        XCTAssertEqual(recorder.values, cohere.progressToReport)
    }

    func testRouterProgressTranscribeBeforeLoadThrows() async {
        let router = RoutingTranscriptionService(sherpaService: StubTranscriptionService(), appleService: nil, cohereService: StubTranscriptionService())
        do {
            _ = try await router.transcribe(samples: [0.1], sampleRate: 16_000) { _ in }
            XCTFail("Expected recognizerNotLoaded")
        } catch TranscriptionService.ServiceError.recognizerNotLoaded {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testConvenienceOverloadsFillFinalPurposeAndNoOpSink() async throws {
        let plain = PlainTranscriptionService()

        let bare = try await plain.transcribe(samples: [0.1], sampleRate: 16_000)
        let partial = try await plain.transcribe(samples: [0.1], sampleRate: 16_000, purpose: .partial)
        let withSink = try await plain.transcribe(samples: [0.1], sampleRate: 16_000) { _ in }
        XCTAssertEqual([bare, partial, withSink], ["plain", "plain", "plain"])

        let purposes = await plain.purposes
        XCTAssertEqual(purposes, [.final, .partial, .final])
    }

    func testSherpaEngineRejectsCohereConfig() async throws {
        let service = TranscriptionService()
        let config = RecognizerConfig(modelID: .cohereTranscribe, family: .cohereTranscribe, tokensPath: "/nope/tokens.txt", numThreads: 1)

        do {
            try await service.loadModel(config: config)
            XCTFail("Expected the sherpa engine to reject a Cohere config")
        } catch TranscriptionService.ServiceError.invalidRecognizerConfiguration {
            // Expected.
        }
        do {
            _ = try await service.makeRecognizerConfig(for: config)
            XCTFail("Expected invalidRecognizerConfiguration")
        } catch TranscriptionService.ServiceError.invalidRecognizerConfiguration {
            // Expected.
        }
    }

    // MARK: - Engine guards (no model needed)

    func testCohereServiceRejectsIncompleteAndMissingConfigs() async {
        let service = CohereTranscriptionService()

        do {
            try await service.loadModel(config: RecognizerConfig(modelID: .cohereTranscribe, family: .cohereTranscribe, tokensPath: "/nope/tokens.txt", numThreads: 1))
            XCTFail("Expected invalidConfiguration")
        } catch CohereTranscriptionService.ServiceError.invalidConfiguration {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        do {
            try await service.loadModel(config: RecognizerConfig(
                modelID: .cohereTranscribe,
                family: .cohereTranscribe,
                tokensPath: "/nope/tokens.txt",
                numThreads: 1,
                encoderPath: "/nope/encoder.onnx",
                decoderPath: "/nope/decoder.onnx"
            ))
            XCTFail("Expected missingModelFile")
        } catch CohereTranscriptionService.ServiceError.missingModelFile("/nope/tokens.txt") {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCohereServiceTranscribeBeforeLoadThrows() async {
        let service = CohereTranscriptionService()
        do {
            _ = try await service.transcribe(samples: [0.1], sampleRate: 16_000)
            XCTFail("Expected notLoaded")
        } catch CohereTranscriptionService.ServiceError.notLoaded {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        await service.unloadModel()
    }

    func testCohereServiceErrorDescriptions() {
        typealias E = CohereTranscriptionService.ServiceError
        XCTAssertEqual(E.notLoaded.errorDescription, "Cohere Transcribe is not loaded")
        XCTAssertEqual(E.emptyAudio.errorDescription, "No audio captured")
        XCTAssertEqual(E.invalidConfiguration.errorDescription, "The selected model files are incomplete")
        XCTAssertEqual(E.missingModelFile("/x").errorDescription, "Required model file is missing: /x")
        XCTAssertEqual(E.unexpectedTensorShape("logits [1]").errorDescription, "Cohere Transcribe returned an unexpected tensor: logits [1]")
    }

    // MARK: - Resampling

    func testResamplerPassesThroughSameRateAndEmptyInput() throws {
        XCTAssertEqual(try AudioResampler.resample([0.1, 0.2], from: 16_000, to: 16_000), [0.1, 0.2])
        XCTAssertEqual(try AudioResampler.resample([], from: 48_000, to: 16_000), [])
    }

    func testResamplerPreservesDurationAndPitch() throws {
        // 1 s of a 440 Hz tone at 48 kHz → 16 kHz: same length in seconds, same
        // number of zero crossings (±1 for the filter's edge handling).
        let source = (0 ..< 48_000).map { sin(Float($0) * 2 * .pi * 440 / 48_000) }

        let output = try AudioResampler.resample(source, from: 48_000, to: 16_000)

        XCTAssertEqual(output.count, 16_000, accuracy: 16)
        let crossings = zip(output, output.dropFirst()).filter { ($0 < 0) != ($1 < 0) }.count
        XCTAssertEqual(crossings, 880, accuracy: 2)
        XCTAssertGreaterThan(output[4_000 ..< 12_000].map(abs).max() ?? 0, 0.9, "no gain change")
    }

    // MARK: - Download verification

    func testSHA256HexStreamsFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sha-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("abc".utf8).write(to: url)

        XCTAssertEqual(
            try ModelManager.sha256Hex(of: url),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        XCTAssertEqual(ModelManager.ModelError.checksumMismatch("f").errorDescription, "Downloaded model file failed verification: f")
    }

    // MARK: - Dictation pill

    func testChunkProgressAdvancesTheTranscribingPill() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = makeValidCapturedAudio()
        let transcription = StubTranscriptionService()
        transcription.transcribeResult = .success("hello")
        transcription.progressToReport = [TranscriptionProgress(chunk: 2, totalChunks: 3)]
        let appState = makeTestAppState(transcriptionService: transcription, audioCaptureService: audioCapture)
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true

        let observed = expectation(description: "pill observed")
        transcription.onTranscribeAwait = { _ in
            // The progress hop to the main actor lands once the stub suspends here.
            let deadline = Date().addingTimeInterval(2)
            while await MainActor.run(body: { appState.floatingIndicatorState == .processing(message: "Transcribing…") }),
                  Date() < deadline {
                await Task.yield()
            }
            let (indicator, status) = await MainActor.run { (appState.floatingIndicatorState, appState.statusText) }
            XCTAssertEqual(indicator, .processing(message: "Transcribing 2 of 3…"))
            XCTAssertEqual(status, "Transcribing 2 of 3…")
            observed.fulfill()
        }

        let started = expectation(description: "capture started")
        audioCapture.onStartCapture = { _ in started.fulfill() }
        appState.startRecordingFromUI()
        await fulfillment(of: [started], timeout: 1)
        for _ in 0 ..< 8 {
            await Task.yield()
        }
        appState.stopRecordingFromUI()
        await fulfillment(of: [observed], timeout: 2)

        let deadline = Date().addingTimeInterval(2)
        while appState.phase != .ready, Date() < deadline {
            await Task.yield()
        }
        XCTAssertEqual(appState.phase, .ready)
    }

    func testSingleChunkProgressLeavesThePillAlone() async {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = makeValidCapturedAudio()
        let transcription = StubTranscriptionService()
        transcription.transcribeResult = .success("hello")
        transcription.progressToReport = [TranscriptionProgress(chunk: 1, totalChunks: 1)]
        let appState = makeTestAppState(transcriptionService: transcription, audioCaptureService: audioCapture)
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true

        let seen = TranscriptionProgressRecorder<FloatingIndicatorState>()
        transcription.onTranscribeAwait = { _ in
            for _ in 0 ..< 8 {
                await Task.yield()
            }
            seen.record(await MainActor.run { appState.floatingIndicatorState })
        }

        let started = expectation(description: "capture started")
        audioCapture.onStartCapture = { _ in started.fulfill() }
        appState.startRecordingFromUI()
        await fulfillment(of: [started], timeout: 1)
        for _ in 0 ..< 8 {
            await Task.yield()
        }
        appState.stopRecordingFromUI()

        let deadline = Date().addingTimeInterval(2)
        while appState.phase != .ready, Date() < deadline {
            await Task.yield()
        }
        XCTAssertEqual(seen.values, [.processing(message: "Transcribing…")])
    }
}

/// Minimal single-pass conformer: implements the one requirement, ignores the sink.
private actor PlainTranscriptionService: TranscriptionServiceProtocol {
    private(set) var purposes: [TranscriptionPurpose] = []

    func loadModel(config: RecognizerConfig) async throws {}

    func transcribe(
        samples: [Float],
        sampleRate: Int,
        purpose: TranscriptionPurpose,
        onProgress: @escaping @Sendable (TranscriptionProgress) -> Void
    ) async throws -> String {
        purposes.append(purpose)
        return "plain"
    }

    func unloadModel() async {}
}

private final class TranscriptionProgressRecorder<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Value] = []

    var values: [Value] {
        lock.withLock { storage }
    }

    func record(_ value: Value) {
        lock.withLock { storage.append(value) }
    }
}
