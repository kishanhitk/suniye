import XCTest
@testable import Suniye

/// Catalog, install-layout, and routing behaviour for the Qwen3-ASR provider. The
/// engine is covered against a fake helper in `Qwen3ASRTranscriptionServiceTests`
/// and against the real model in `Qwen3ASRTranscriptionServiceRealModelTests`.
@MainActor
final class Qwen3ASRProviderTests: XCTestCase {
    private var entry: ASRModelCatalogEntry {
        ASRModelCatalog.entry(for: .qwen3ASR17B)
    }

    func testEntryIsAPinnedRemoteFileDownload() throws {
        XCTAssertEqual(entry.family, .qwen3ASR)
        XCTAssertFalse(entry.isSystemManaged)
        XCTAssertFalse(entry.family.supportsLivePreview)
        XCTAssertEqual(entry.isAvailableOnThisDevice, LocalLLMHardware.isAppleSilicon, "the bundled helper is Apple Silicon only")

        guard case let .remoteFiles(files) = entry.downloadSource else {
            return XCTFail("expected remote files")
        }
        XCTAssertEqual(files.map(\.destinationRelativePath), ["Qwen3-ASR-1.7B-Q8_0.gguf", "mmproj-Qwen3-ASR-1.7B-Q8_0.gguf"])
        for file in files {
            XCTAssertEqual(file.sha256?.count, 64, file.destinationRelativePath)
            XCTAssertTrue(file.remoteURL.path.contains("/ggml-org/Qwen3-ASR-1.7B-GGUF/resolve/36a678687ba7d07a74ca70ccb0e36902e005fb80/"), "pinned to a commit")
        }
        XCTAssertEqual(files.compactMap(\.expectedSizeBytes).reduce(0, +), entry.estimatedSizeBytes)
        XCTAssertEqual(Set(files.map(\.destinationRelativePath)), Set(entry.manifest.requiredRelativePaths))
    }

    func testFallbackPrefersItOverTheHeavierCohereModelOnly() {
        let order = ASRModelCatalog.fallbackOrder
        XCTAssertEqual(order.suffix(2), [.qwen3ASR17B, .cohereTranscribe])
    }

    func testRecognizerConfigCarriesTheModelAndItsAudioProjector() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("qwen3-config-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = ModelManager(applicationSupportDirectory: root)

        let config = try manager.makeRecognizerConfig(for: .qwen3ASR17B)

        XCTAssertEqual(config.family, .qwen3ASR)
        XCTAssertTrue(config.modelPath?.hasSuffix("qwen3-asr-1.7b-q8_0-gguf/Qwen3-ASR-1.7B-Q8_0.gguf") ?? false)
        XCTAssertTrue(config.encoderPath?.hasSuffix("qwen3-asr-1.7b-q8_0-gguf/mmproj-Qwen3-ASR-1.7B-Q8_0.gguf") ?? false)
        XCTAssertEqual(config.tokensPath, config.modelPath, "the vocabulary lives inside the GGUF")
    }

    func testRouterSendsQwen3FamilyToItsEngine() async throws {
        let sherpa = StubTranscriptionService()
        let qwen3 = StubTranscriptionService()
        qwen3.transcribeResult = .success("qwen3-text")
        let router = RoutingTranscriptionService(
            sherpaService: sherpa,
            appleService: nil,
            cohereService: StubTranscriptionService(),
            qwen3Service: qwen3
        )

        try await router.loadModel(config: RecognizerConfig(modelID: .qwen3ASR17B, family: .qwen3ASR, tokensPath: "", numThreads: 1))
        let text = try await router.transcribe(samples: [0.1], sampleRate: 16_000)

        XCTAssertEqual(text, "qwen3-text")
        XCTAssertEqual(qwen3.loadCallCount, 1)
        XCTAssertEqual(sherpa.loadCallCount, 0)

        try await router.loadModel(config: RecognizerConfig(modelID: .parakeetV3, family: .nemoTransducer, tokensPath: "", numThreads: 1))
        XCTAssertEqual(qwen3.unloadCallCount, 1, "switching away stops the helper and frees its memory")
    }

    func testSherpaEngineRejectsQwen3Config() async {
        let service = TranscriptionService()
        let config = RecognizerConfig(modelID: .qwen3ASR17B, family: .qwen3ASR, tokensPath: "/nope/model.gguf", numThreads: 1)

        do {
            try await service.loadModel(config: config)
            XCTFail("Expected the sherpa engine to reject a Qwen3-ASR config")
        } catch TranscriptionService.ServiceError.invalidRecognizerConfiguration {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
