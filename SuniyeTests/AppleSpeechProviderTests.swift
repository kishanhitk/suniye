import Speech
import XCTest
@testable import Suniye

final class AppleSpeechProviderTests: XCTestCase {
    // MARK: - Catalog

    func testAppleEntryIsSystemManaged() {
        let entry = ASRModelCatalog.entry(for: .appleSpeech)
        XCTAssertTrue(entry.isSystemManaged)
        XCTAssertEqual(entry.family, .appleSpeech)
        XCTAssertEqual(entry.sizeDisplayText, "Built into macOS")
        XCTAssertEqual(entry.estimatedSizeBytes, 0)
    }

    func testSherpaEntriesAreNotSystemManaged() {
        for entry in ASRModelCatalog.entries where entry.id != .appleSpeech {
            XCTAssertFalse(entry.isSystemManaged, "\(entry.id) should not be system-managed")
            XCTAssertTrue(entry.isAvailableOnThisDevice, "sherpa models are always available")
            XCTAssertNotEqual(entry.sizeDisplayText, "Built into macOS")
        }
    }

    func testAvailableEntriesFollowsSupportGate() {
        let available = ASRModelCatalog.availableEntries
        let containsApple = available.contains { $0.id == .appleSpeech }
        // The Apple entry is present exactly when the OS supports it — this is what
        // hides it entirely on macOS < 26.
        XCTAssertEqual(containsApple, AppleSpeechSupport.isAvailable)
        // Every sherpa model remains available regardless of OS.
        XCTAssertTrue(available.contains { $0.id == .parakeetV3 })
    }

    // MARK: - ModelManager system-managed branch

    func testMakeRecognizerConfigForAppleUsesEngineFamilyWithoutFilePaths() throws {
        let manager = ModelManager()
        let config = try manager.makeRecognizerConfig(for: .appleSpeech)

        XCTAssertEqual(config.family, .appleSpeech)
        XCTAssertEqual(config.modelID, .appleSpeech)
        XCTAssertEqual(config.tokensPath, "")
        XCTAssertNil(config.encoderPath)
        XCTAssertNil(config.decoderPath)
        XCTAssertNil(config.modelPath)
    }

    func testIsInstalledForAppleMatchesSupport() {
        let manager = ModelManager()
        XCTAssertEqual(manager.isInstalled(.appleSpeech), AppleSpeechSupport.isAvailable)
    }

    func testAppleIsExcludedFromInstalledModels() {
        // Opt-in: even when available, Apple Speech must not count as installed for
        // onboarding/auto-fallback purposes (keeps Parakeet the default).
        let manager = ModelManager()
        XCTAssertFalse(manager.installedModels().contains(.appleSpeech))
    }

    func testInstalledByteCountForAppleIsZero() {
        let manager = ModelManager()
        XCTAssertEqual(manager.installedByteCount(for: .appleSpeech), 0)
    }

    func testModelDirectoryForAppleThrows() {
        let manager = ModelManager()
        XCTAssertThrowsError(try manager.modelDirectoryURL(for: .appleSpeech))
    }

    func testDeleteAppleModelIsNoOp() {
        let manager = ModelManager()
        XCTAssertNoThrow(try manager.deleteModel(.appleSpeech))
    }

    func testDownloadAppleModelReportsComplete() async throws {
        let manager = ModelManager()
        let progress = ProgressBox()
        try await manager.downloadAndExtractModel(.appleSpeech) { value in
            progress.record(value)
        }
        XCTAssertEqual(progress.last, 1)
    }

    // MARK: - Apple engine (macOS 26+)

    @available(macOS 26, *)
    func testTranscribeBeforeLoadThrowsNotLoaded() async throws {
        try XCTSkipUnless(AppleSpeechSupport.isAvailable, "Apple Speech unavailable")

        let service = AppleSpeechTranscriptionService()
        do {
            _ = try await service.transcribe(samples: [0.1, 0.2], sampleRate: 16_000)
            XCTFail("Expected transcribe to throw before loadModel")
        } catch let error as AppleSpeechTranscriptionService.ServiceError {
            guard case .notLoaded = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @available(macOS 26, *)
    func testTranscribeSilenceReturnsTrimmedStringWhenAssetInstalled() async throws {
        try XCTSkipUnless(AppleSpeechSupport.isAvailable, "Apple Speech unavailable on this OS")

        let current = Locale.current
        let installed = await SpeechTranscriber.installedLocales
        let hasAsset = installed.contains { $0.identifier(.bcp47) == current.identifier(.bcp47) }
        try XCTSkipUnless(hasAsset, "Locale model asset not installed; skipping to avoid a network download")

        let service = AppleSpeechTranscriptionService()
        try await service.loadModel(
            config: RecognizerConfig(modelID: .appleSpeech, family: .appleSpeech, tokensPath: "", numThreads: 1)
        )
        let samples = [Float](repeating: 0, count: 8_000) // 0.5s of silence @ 16 kHz
        let text = try await service.transcribe(samples: samples, sampleRate: 16_000)

        // Silence yields an empty result, but the call must complete and return a
        // whitespace-trimmed string (our contract) rather than throwing.
        XCTAssertEqual(text, text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// Thread-safe progress recorder for the async download callback.
private final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Double?

    func record(_ newValue: Double) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    var last: Double? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
