import XCTest
@testable import Suniye

/// URLProtocol stub used to exercise ModelManager download paths without network access.
final class ModelManagerCoverageURLProtocol: URLProtocol {
    struct Stub {
        var statusCode: Int = 200
        var body: Data = Data()
        var error: Error?
    }

    private static let lock = NSLock()
    private static var stubs: [URL: Stub] = [:]

    static func setStub(_ stub: Stub, for url: URL) {
        lock.lock()
        defer { lock.unlock() }
        stubs[url] = stub
    }

    static func removeAllStubs() {
        lock.lock()
        defer { lock.unlock() }
        stubs.removeAll()
    }

    private static func stub(for url: URL?) -> Stub? {
        lock.lock()
        defer { lock.unlock() }
        guard let url else {
            return nil
        }
        return stubs[url]
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url, let stub = Self.stub(for: url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }

        if let error = stub.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Length": "\(stub.body.count)"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

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

final class ModelManagerCoverageTests: XCTestCase {
    private let fileManager = FileManager.default
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("suniye-model-manager-coverage-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        ModelManagerCoverageURLProtocol.removeAllStubs()
        if let tempDirectory {
            try? fileManager.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func makeStubbedSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ModelManagerCoverageURLProtocol.self]
        return configuration
    }

    private func makeSandboxedManager() -> ModelManager {
        ModelManager(
            applicationSupportDirectory: tempDirectory,
            urlSessionConfiguration: makeStubbedSessionConfiguration()
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

    // MARK: - Progress estimator edge cases

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

    // MARK: - Error descriptions

    func testModelErrorDescriptions() {
        XCTAssertEqual(
            ModelManager.ModelError.appSupportUnavailable.errorDescription,
            "Unable to resolve Application Support directory"
        )
        XCTAssertEqual(
            ModelManager.ModelError.invalidResponse.errorDescription,
            "Model download response was invalid"
        )
        XCTAssertEqual(
            ModelManager.ModelError.unknownModel.errorDescription,
            "The selected model is not supported by this build"
        )
        XCTAssertEqual(
            ModelManager.ModelError.extractFailed("boom").errorDescription,
            "Model extraction failed: boom"
        )
    }

    // MARK: - Catalog surface

    func testCatalogAndFallbackOrderMirrorSharedCatalog() {
        let manager = makeSandboxedManager()
        // catalog exposes only device-available entries (system-managed models are
        // filtered out where unsupported), so it mirrors availableEntries rather than
        // the raw entries list. This keeps the assertion deterministic across machines.
        XCTAssertEqual(manager.catalog, ASRModelCatalog.availableEntries)
        XCTAssertEqual(manager.fallbackOrder, ASRModelCatalog.fallbackOrder)
    }

    func testExpectedDownloadSizeBytesComesFromCatalog() {
        let manager = makeSandboxedManager()
        XCTAssertEqual(
            manager.expectedDownloadSizeBytes(for: .parakeetV3),
            ASRModelCatalog.entry(for: .parakeetV3).estimatedSizeBytes
        )
    }

    // MARK: - Application Support unavailable

    func testModelsRootDirectoryThrowsWhenAppSupportUnavailable() {
        let manager = ModelManager(
            applicationSupportDirectory: nil,
            urlSessionConfiguration: makeStubbedSessionConfiguration()
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

    // MARK: - Installation inspection

    func testModelsRootDirectoryUsesInjectedAppSupportDirectory() throws {
        let manager = makeSandboxedManager()
        let root = try manager.modelsRootDirectoryURL()

        XCTAssertEqual(root.lastPathComponent, "models")
        XCTAssertTrue(root.path.hasPrefix(tempDirectory.path))
        XCTAssertTrue(fileManager.fileExists(atPath: root.path))
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

    // MARK: - Archive download + extract

    func testDownloadAndExtractModelInstallsArchiveEndToEnd() async throws {
        let entry = ASRModelCatalog.entry(for: .senseVoice)
        let archiveData = try makeArchiveData(for: entry, marker: "downloaded")
        ModelManagerCoverageURLProtocol.setStub(
            .init(statusCode: 200, body: archiveData),
            for: try archiveURLForEntry(entry)
        )

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
        ModelManagerCoverageURLProtocol.setStub(
            .init(statusCode: 200, body: archiveData),
            for: try archiveURLForEntry(entry)
        )

        try await manager.downloadAndExtractModel(.senseVoice) { _ in }

        let tokensURL = try manager.modelDirectoryURL(for: .senseVoice)
            .appendingPathComponent(entry.manifest.tokens)
        XCTAssertEqual(try String(contentsOf: tokensURL), "new")
    }

    func testDownloadAndExtractModelThrowsForNon2xxResponse() async throws {
        let entry = ASRModelCatalog.entry(for: .parakeetV3)
        ModelManagerCoverageURLProtocol.setStub(
            .init(statusCode: 404, body: Data("not found".utf8)),
            for: try archiveURLForEntry(entry)
        )

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
        ModelManagerCoverageURLProtocol.setStub(
            .init(statusCode: 200, body: Data("this is definitely not a bzip2 archive".utf8)),
            for: try archiveURLForEntry(entry)
        )

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
        ModelManagerCoverageURLProtocol.setStub(
            .init(error: URLError(.notConnectedToInternet)),
            for: try archiveURLForEntry(entry)
        )

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

        ModelManagerCoverageURLProtocol.setStub(
            .init(statusCode: 200, body: try Data(contentsOf: archiveURL)),
            for: try archiveURLForEntry(entry)
        )

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

    // MARK: - Remote file downloads

    func testDownloadRemoteFilesWritesFilesAndReportsAggregateProgress() async throws {
        let fileURL1 = URL(string: "https://stub.suniye.test/remote/file1.bin")!
        let fileURL2 = URL(string: "https://stub.suniye.test/remote/dir/file2.bin")!
        let body1 = Data(repeating: 0x41, count: 64)
        let body2 = Data(repeating: 0x42, count: 128)
        ModelManagerCoverageURLProtocol.setStub(.init(statusCode: 200, body: body1), for: fileURL1)
        ModelManagerCoverageURLProtocol.setStub(.init(statusCode: 200, body: body2), for: fileURL2)

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
        ModelManagerCoverageURLProtocol.setStub(
            .init(statusCode: 200, body: Data(repeating: 0x43, count: 32)),
            for: fileURL
        )

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
        ModelManagerCoverageURLProtocol.setStub(
            .init(statusCode: 200, body: Data("fresh".utf8)),
            for: fileURL
        )

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
        ModelManagerCoverageURLProtocol.setStub(
            .init(statusCode: 500, body: Data()),
            for: fileURL
        )

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

    // MARK: - Replace/rollback

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
