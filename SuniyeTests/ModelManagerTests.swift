import XCTest
@testable import Suniye

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Double] = []

    func record(_ value: Double) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(value)
    }

    var values: [Double] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

final class ModelManagerTests: XCTestCase {

    private let fileManager = FileManager.default
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("suniye-model-manager-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        StubURLProtocol.handler = nil
        if let tempDirectory {
            try? fileManager.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        try super.tearDownWithError()
    }

    private func makeSandboxedManager() -> ModelManager {
        ModelManager(
            applicationSupportDirectory: tempDirectory,
            urlSessionConfiguration: StubURLProtocol.sessionConfiguration()
        )
    }

    private func writeFile(at url: URL, contents: String) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
    }

    private func archiveURLForEntry(_ entry: ASRModelCatalogEntry) throws -> URL {
        guard case let .archive(url) = entry.downloadSource else {
            throw XCTSkip("Catalog entry \(entry.id.rawValue) is not archive-based")
        }
        return url
    }

    /// Builds a real tar.bz2 archive containing `directoryName/<manifest files>` and returns its bytes.
    private func makeArchiveData(for entry: ASRModelCatalogEntry, marker: String) throws -> Data {
        let stagingDirectory = tempDirectory
            .appendingPathComponent("archive-staging-\(UUID().uuidString)", isDirectory: true)
        let modelDirectory = stagingDirectory.appendingPathComponent(entry.directoryName, isDirectory: true)
        for relativePath in entry.manifest.requiredRelativePaths {
            try writeFile(at: modelDirectory.appendingPathComponent(relativePath), contents: marker)
        }

        let archiveURL = stagingDirectory.appendingPathComponent("model.tar.bz2")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-cjf", archiveURL.path, "-C", stagingDirectory.path, entry.directoryName]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "failed to build test archive")
        return try Data(contentsOf: archiveURL)
    }

    private func installFakeModel(_ entry: ASRModelCatalogEntry, using manager: ModelManager, marker: String) throws {
        let modelDirectory = try manager.modelDirectoryURL(for: entry.id)
        for relativePath in entry.manifest.requiredRelativePaths {
            try writeFile(at: modelDirectory.appendingPathComponent(relativePath), contents: marker)
        }
    }

    func testProgressEstimatorUsesReportedTotalWhenAvailable() {
        let progress = ModelDownloadProgressEstimator.estimate(
            totalBytesWritten: 340,
            totalBytesExpectedToWrite: 680,
            responseExpectedLength: nil,
            fallbackExpectedSize: 1_000
        )

        XCTAssertEqual(progress, 0.5)
    }

    func testProgressEstimatorFallsBackToResponseLengthWhenTaskTotalUnknown() {
        let progress = ModelDownloadProgressEstimator.estimate(
            totalBytesWritten: 250,
            totalBytesExpectedToWrite: NSURLSessionTransferSizeUnknown,
            responseExpectedLength: 1_000,
            fallbackExpectedSize: 2_000
        )

        XCTAssertEqual(progress, 0.25)
    }

    func testProgressEstimatorFallsBackToConfiguredExpectedSize() {
        let progress = ModelDownloadProgressEstimator.estimate(
            totalBytesWritten: 340_000_000,
            totalBytesExpectedToWrite: NSURLSessionTransferSizeUnknown,
            responseExpectedLength: NSURLSessionTransferSizeUnknown,
            fallbackExpectedSize: 680_000_000
        )

        XCTAssertEqual(progress, 0.5)
    }

    func testProgressEstimatorReturnsNilWhenNoExpectedSizeIsKnown() {
        XCTAssertNil(
            ModelDownloadProgressEstimator.estimate(
                totalBytesWritten: 10,
                totalBytesExpectedToWrite: 0,
                responseExpectedLength: nil,
                fallbackExpectedSize: 0
            )
        )
        XCTAssertNil(
            ModelDownloadProgressEstimator.estimate(
                totalBytesWritten: 10,
                totalBytesExpectedToWrite: -1,
                responseExpectedLength: -1,
                fallbackExpectedSize: -5
            )
        )
    }

    func testProgressEstimatorReturnsNilForNegativeBytesWritten() {
        XCTAssertNil(
            ModelDownloadProgressEstimator.estimate(
                totalBytesWritten: -1,
                totalBytesExpectedToWrite: 100,
                responseExpectedLength: nil,
                fallbackExpectedSize: 0
            )
        )
    }

    func testProgressEstimatorClampsToUnitRange() {
        XCTAssertEqual(
            ModelDownloadProgressEstimator.estimate(
                totalBytesWritten: 500,
                totalBytesExpectedToWrite: 100,
                responseExpectedLength: nil,
                fallbackExpectedSize: 0
            ),
            1
        )
    }

    func testModelsRootDirectoryThrowsWhenAppSupportUnavailable() {
        let manager = ModelManager(
            applicationSupportDirectory: nil,
            urlSessionConfiguration: StubURLProtocol.sessionConfiguration()
        )

        XCTAssertThrowsError(try manager.modelsRootDirectoryURL()) { error in
            guard case ModelManager.ModelError.appSupportUnavailable = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertFalse(manager.isInstalled(.parakeetV3))
        XCTAssertTrue(manager.installedModels().isEmpty)
        XCTAssertEqual(manager.installedByteCount(for: .parakeetV3), 0)
        XCTAssertThrowsError(try manager.deleteModel(.parakeetV3))
        XCTAssertThrowsError(try manager.makeRecognizerConfig(for: .parakeetV3))
    }

    func testModelDirectoryResolvesUnderSuniyeModelsFolder() throws {
        let manager = makeSandboxedManager()

        let modelDirectory = try manager.modelDirectoryURL(for: .parakeetV3)

        XCTAssertEqual(
            modelDirectory.path,
            tempDirectory.appendingPathComponent("Suniye/models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8").path
        )
        XCTAssertTrue(fileManager.fileExists(atPath: modelDirectory.deletingLastPathComponent().path))
    }

    func testRecognizerConfigUsesExpectedFileNames() throws {
        let manager = makeSandboxedManager()
        let config = try manager.makeRecognizerConfig(for: .parakeetV3)

        XCTAssertTrue(config.encoderPath?.hasSuffix("encoder.int8.onnx") == true)
        XCTAssertTrue(config.decoderPath?.hasSuffix("decoder.int8.onnx") == true)
        XCTAssertTrue(config.joinerPath?.hasSuffix("joiner.int8.onnx") == true)
        XCTAssertTrue(config.tokensPath.hasSuffix("tokens.txt"))
        XCTAssertEqual(config.numThreads, 4)
    }

    func testParakeetV2RecognizerConfigUsesExpectedFiles() throws {
        let manager = makeSandboxedManager()
        let config = try manager.makeRecognizerConfig(for: .parakeetV2English)

        XCTAssertEqual(config.family, .nemoTransducer)
        XCTAssertTrue(config.encoderPath?.hasSuffix("encoder.int8.onnx") == true)
        XCTAssertTrue(config.decoderPath?.hasSuffix("decoder.int8.onnx") == true)
        XCTAssertTrue(config.joinerPath?.hasSuffix("joiner.int8.onnx") == true)
        XCTAssertTrue(config.tokensPath.hasSuffix("tokens.txt"))
    }

    func testMoonshineRecognizerConfigUsesExpectedFiles() throws {
        let manager = makeSandboxedManager()
        let config = try manager.makeRecognizerConfig(for: .moonshineBase)

        XCTAssertEqual(config.family, .moonshine)
        XCTAssertTrue(config.preprocessorPath?.hasSuffix("preprocess.onnx") == true)
        XCTAssertTrue(config.encoderPath?.hasSuffix("encode.int8.onnx") == true)
        XCTAssertTrue(config.uncachedDecoderPath?.hasSuffix("uncached_decode.int8.onnx") == true)
        XCTAssertTrue(config.cachedDecoderPath?.hasSuffix("cached_decode.int8.onnx") == true)
    }

    func testSenseVoiceRecognizerConfigUsesExpectedFiles() throws {
        let manager = makeSandboxedManager()
        let config = try manager.makeRecognizerConfig(for: .senseVoice)

        XCTAssertEqual(config.family, .senseVoice)
        XCTAssertTrue(config.modelPath?.hasSuffix("model.int8.onnx") == true)
        XCTAssertTrue(config.tokensPath.hasSuffix("tokens.txt"))
    }

    func testWhisperTurboRecognizerConfigUsesExpectedFiles() throws {
        let manager = makeSandboxedManager()
        let config = try manager.makeRecognizerConfig(for: .whisperLargeV3Turbo)

        XCTAssertEqual(config.family, .whisper)
        XCTAssertTrue(config.encoderPath?.hasSuffix("turbo-encoder.int8.onnx") == true)
        XCTAssertTrue(config.decoderPath?.hasSuffix("turbo-decoder.int8.onnx") == true)
        XCTAssertTrue(config.tokensPath.hasSuffix("turbo-tokens.txt"))
    }

    func testWhisperDistilLargeV3RecognizerConfigUsesExpectedFiles() throws {
        let manager = makeSandboxedManager()
        let config = try manager.makeRecognizerConfig(for: .whisperDistilLargeV3)

        XCTAssertEqual(config.family, .whisper)
        XCTAssertTrue(config.encoderPath?.hasSuffix("distil-large-v3-encoder.int8.onnx") == true)
        XCTAssertTrue(config.decoderPath?.hasSuffix("distil-large-v3-decoder.int8.onnx") == true)
        XCTAssertTrue(config.tokensPath.hasSuffix("distil-large-v3-tokens.txt"))
    }

    func testInstalledModelsReflectsFakeInstall() throws {
        let manager = makeSandboxedManager()
        XCTAssertTrue(manager.installedModels().isEmpty)

        try installFakeModel(ASRModelCatalog.entry(for: .parakeetV3), using: manager, marker: "fake")

        XCTAssertTrue(manager.isInstalled(.parakeetV3))
        XCTAssertEqual(manager.installedModels(), [.parakeetV3])
        XCTAssertFalse(manager.isInstalled(.moonshineBase))
    }

    func testInstalledByteCountSumsRegularFiles() throws {
        let manager = makeSandboxedManager()
        let entry = ASRModelCatalog.entry(for: .senseVoice)
        let modelDirectory = try manager.modelDirectoryURL(for: .senseVoice)

        XCTAssertEqual(manager.installedByteCount(for: .senseVoice), 0)

        try writeFile(at: modelDirectory.appendingPathComponent(entry.manifest.tokens), contents: "abc")
        try writeFile(at: modelDirectory.appendingPathComponent("model.int8.onnx"), contents: "12345")
        try writeFile(at: modelDirectory.appendingPathComponent("nested/extra.bin"), contents: "12")

        XCTAssertEqual(manager.installedByteCount(for: .senseVoice), 10)
    }

    func testDeleteModelRemovesInstalledDirectoryAndIgnoresMissingOne() throws {
        let manager = makeSandboxedManager()
        let entry = ASRModelCatalog.entry(for: .parakeetV3)
        try installFakeModel(entry, using: manager, marker: "fake")
        let modelDirectory = try manager.modelDirectoryURL(for: .parakeetV3)
        XCTAssertTrue(fileManager.fileExists(atPath: modelDirectory.path))

        try manager.deleteModel(.parakeetV3)
        XCTAssertFalse(fileManager.fileExists(atPath: modelDirectory.path))

        // Second delete: directory no longer exists, should be a no-op.
        XCTAssertNoThrow(try manager.deleteModel(.parakeetV3))
    }

    func testDownloadAndExtractModelInstallsArchiveEndToEnd() async throws {
        let entry = ASRModelCatalog.entry(for: .senseVoice)
        let archiveData = try makeArchiveData(for: entry, marker: "downloaded")
        try StubURLProtocol.serve([
            archiveURLForEntry(entry): .init(statusCode: 200, body: archiveData)
        ])

        let manager = makeSandboxedManager()
        let recorder = ProgressRecorder()
        try await manager.downloadAndExtractModel(.senseVoice) { recorder.record($0) }

        XCTAssertTrue(manager.isInstalled(.senseVoice))
        XCTAssertEqual(recorder.values.last, 1)
        XCTAssertTrue(recorder.values.allSatisfy { $0 >= 0 && $0 <= 1 })

        let tokensURL = try manager.modelDirectoryURL(for: .senseVoice)
            .appendingPathComponent(entry.manifest.tokens)
        XCTAssertEqual(try String(contentsOf: tokensURL), "downloaded")

        // No staging or backup litter left behind in the models root.
        let rootContents = try fileManager.contentsOfDirectory(atPath: manager.modelsRootDirectoryURL().path)
        XCTAssertEqual(rootContents.filter { $0.hasPrefix(".") }, [])
    }

    func testDownloadAndExtractModelReplacesExistingInstall() async throws {
        let entry = ASRModelCatalog.entry(for: .senseVoice)
        let manager = makeSandboxedManager()
        try installFakeModel(entry, using: manager, marker: "old")

        let archiveData = try makeArchiveData(for: entry, marker: "new")
        try StubURLProtocol.serve([
            archiveURLForEntry(entry): .init(statusCode: 200, body: archiveData)
        ])

        try await manager.downloadAndExtractModel(.senseVoice) { _ in }

        let tokensURL = try manager.modelDirectoryURL(for: .senseVoice)
            .appendingPathComponent(entry.manifest.tokens)
        XCTAssertEqual(try String(contentsOf: tokensURL), "new")
    }

    func testDownloadAndExtractModelThrowsForNon2xxResponse() async throws {
        let entry = ASRModelCatalog.entry(for: .parakeetV3)
        try StubURLProtocol.serve([
            archiveURLForEntry(entry): .init(statusCode: 404, body: Data("not found".utf8))
        ])

        let manager = makeSandboxedManager()
        do {
            try await manager.downloadAndExtractModel(.parakeetV3) { _ in }
            XCTFail("Expected invalidResponse")
        } catch let error as ModelManager.ModelError {
            guard case .invalidResponse = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertFalse(manager.isInstalled(.parakeetV3))
    }

    func testDownloadAndExtractModelThrowsWhenArchiveIsCorrupt() async throws {
        let entry = ASRModelCatalog.entry(for: .parakeetV3)
        try StubURLProtocol.serve([
            archiveURLForEntry(entry): .init(statusCode: 200, body: Data("this is definitely not a bzip2 archive".utf8))
        ])

        let manager = makeSandboxedManager()
        do {
            try await manager.downloadAndExtractModel(.parakeetV3) { _ in }
            XCTFail("Expected extractFailed")
        } catch let error as ModelManager.ModelError {
            guard case .extractFailed = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertFalse(manager.isInstalled(.parakeetV3))
    }

    func testDownloadAndExtractModelPropagatesTransportErrors() async throws {
        let entry = ASRModelCatalog.entry(for: .parakeetV3)
        try StubURLProtocol.serve([
            archiveURLForEntry(entry): .init(error: URLError(.notConnectedToInternet))
        ])

        let manager = makeSandboxedManager()
        do {
            try await manager.downloadAndExtractModel(.parakeetV3) { _ in }
            XCTFail("Expected a transport error")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .notConnectedToInternet)
        }
    }

    func testDownloadAndExtractModelThrowsWhenValidationFindsMissingFiles() async throws {
        // Archive extracts fine but is missing required manifest files.
        let entry = ASRModelCatalog.entry(for: .parakeetV3)
        // Build an archive that only contains the parakeet directory with a lone tokens file.
        let stagingDirectory = tempDirectory
            .appendingPathComponent("incomplete-archive-\(UUID().uuidString)", isDirectory: true)
        let modelDirectory = stagingDirectory.appendingPathComponent(entry.directoryName, isDirectory: true)
        try writeFile(at: modelDirectory.appendingPathComponent(entry.manifest.tokens), contents: "only-tokens")
        let archiveURL = stagingDirectory.appendingPathComponent("incomplete.tar.bz2")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-cjf", archiveURL.path, "-C", stagingDirectory.path, entry.directoryName]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        try StubURLProtocol.serve([
            archiveURLForEntry(entry): .init(statusCode: 200, body: Data(contentsOf: archiveURL))
        ])

        let manager = makeSandboxedManager()
        do {
            try await manager.downloadAndExtractModel(.parakeetV3) { _ in }
            XCTFail("Expected extractFailed for missing manifest files")
        } catch let error as ModelManager.ModelError {
            guard case let .extractFailed(reason) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(reason.contains("missing required files"))
        }
        XCTAssertFalse(manager.isInstalled(.parakeetV3))
    }

    func testDownloadRemoteFilesWritesFilesAndReportsAggregateProgress() async throws {
        let fileURL1 = URL(string: "https://stub.suniye.test/remote/file1.bin")!
        let fileURL2 = URL(string: "https://stub.suniye.test/remote/dir/file2.bin")!
        let body1 = Data(repeating: 0x41, count: 64)
        let body2 = Data(repeating: 0x42, count: 128)
        StubURLProtocol.serve([
            fileURL1: .init(statusCode: 200, body: body1),
            fileURL2: .init(statusCode: 200, body: body2)
        ])

        let files = [
            ASRModelRemoteFile(remoteURL: fileURL1, destinationRelativePath: "file1.bin", expectedSizeBytes: 64),
            ASRModelRemoteFile(remoteURL: fileURL2, destinationRelativePath: "dir/file2.bin", expectedSizeBytes: 128)
        ]

        let manager = makeSandboxedManager()
        let destination = tempDirectory.appendingPathComponent("remote-model", isDirectory: true)
        let recorder = ProgressRecorder()
        try await manager.downloadRemoteFiles(files, into: destination) { recorder.record($0) }

        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("file1.bin")), body1)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("dir/file2.bin")), body2)
        XCTAssertTrue(recorder.values.allSatisfy { $0 >= 0 && $0 <= 1 })
        XCTAssertEqual(recorder.values.last, 1)
    }

    func testDownloadRemoteFilesUsesIndexBasedProgressWhenSizesUnknown() async throws {
        let fileURL = URL(string: "https://stub.suniye.test/remote/unknown-size.bin")!
        StubURLProtocol.serve([
            fileURL: .init(statusCode: 200, body: Data(repeating: 0x43, count: 32))
        ])

        let files = [
            ASRModelRemoteFile(remoteURL: fileURL, destinationRelativePath: "unknown-size.bin", expectedSizeBytes: nil)
        ]

        let manager = makeSandboxedManager()
        let destination = tempDirectory.appendingPathComponent("remote-model-unknown", isDirectory: true)
        let recorder = ProgressRecorder()
        try await manager.downloadRemoteFiles(files, into: destination) { recorder.record($0) }

        XCTAssertTrue(fileManager.fileExists(atPath: destination.appendingPathComponent("unknown-size.bin").path))
        XCTAssertTrue(recorder.values.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    func testDownloadRemoteFilesOverwritesExistingDestination() async throws {
        let fileURL = URL(string: "https://stub.suniye.test/remote/overwrite.bin")!
        StubURLProtocol.serve([
            fileURL: .init(statusCode: 200, body: Data("fresh".utf8))
        ])

        let manager = makeSandboxedManager()
        let destination = tempDirectory.appendingPathComponent("remote-model-overwrite", isDirectory: true)
        try writeFile(at: destination.appendingPathComponent("overwrite.bin"), contents: "stale")

        let files = [
            ASRModelRemoteFile(remoteURL: fileURL, destinationRelativePath: "overwrite.bin", expectedSizeBytes: 5)
        ]
        try await manager.downloadRemoteFiles(files, into: destination) { _ in }

        XCTAssertEqual(
            try String(contentsOf: destination.appendingPathComponent("overwrite.bin")),
            "fresh"
        )
    }

    func testDownloadRemoteFilesThrowsForNon2xxResponse() async throws {
        let fileURL = URL(string: "https://stub.suniye.test/remote/missing.bin")!
        StubURLProtocol.serve([
            fileURL: .init(statusCode: 500, body: Data())
        ])

        let manager = makeSandboxedManager()
        let destination = tempDirectory.appendingPathComponent("remote-model-error", isDirectory: true)
        let files = [
            ASRModelRemoteFile(remoteURL: fileURL, destinationRelativePath: "missing.bin", expectedSizeBytes: 10)
        ]

        do {
            try await manager.downloadRemoteFiles(files, into: destination) { _ in }
            XCTFail("Expected invalidResponse")
        } catch let error as ModelManager.ModelError {
            guard case .invalidResponse = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testDownloadRemoteFilesVerifiesPinnedSHA256() async throws {
        let fileURL = URL(string: "https://stub.suniye.test/remote/pinned.bin")!
        StubURLProtocol.serve([fileURL: .init(statusCode: 200, body: Data("abc".utf8))])
        let manager = makeSandboxedManager()
        let destination = tempDirectory.appendingPathComponent("remote-model-pinned", isDirectory: true)

        let matching = [
            ASRModelRemoteFile(
                remoteURL: fileURL,
                destinationRelativePath: "pinned.bin",
                expectedSizeBytes: 3,
                sha256: "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD"
            )
        ]
        try await manager.downloadRemoteFiles(matching, into: destination) { _ in }
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("pinned.bin")), "abc")

        let tampered = [
            ASRModelRemoteFile(remoteURL: fileURL, destinationRelativePath: "tampered.bin", expectedSizeBytes: 3, sha256: String(repeating: "0", count: 64))
        ]
        do {
            try await manager.downloadRemoteFiles(tampered, into: destination) { _ in }
            XCTFail("Expected checksumMismatch")
        } catch ModelManager.ModelError.checksumMismatch("tampered.bin") {
            XCTAssertFalse(fileManager.fileExists(atPath: destination.appendingPathComponent("tampered.bin").path), "a bad file must never land in the model directory")
        }
    }

    func testReplaceInstalledModelRestoresBackupWhenSwapFails() throws {
        let liveDirectory = tempDirectory.appendingPathComponent("live-model", isDirectory: true)
        try writeFile(at: liveDirectory.appendingPathComponent("tokens.txt"), contents: "live")

        let missingStagedDirectory = tempDirectory
            .appendingPathComponent("does-not-exist", isDirectory: true)
            .appendingPathComponent("live-model", isDirectory: true)

        XCTAssertThrowsError(
            try ModelManager.replaceInstalledModel(at: liveDirectory, with: missingStagedDirectory)
        )

        // Live install must be rolled back intact and the backup removed.
        XCTAssertEqual(try String(contentsOf: liveDirectory.appendingPathComponent("tokens.txt")), "live")
        let siblings = try fileManager.contentsOfDirectory(atPath: tempDirectory.path)
        XCTAssertTrue(siblings.filter { $0.contains("-backup-") }.isEmpty)
    }
}
