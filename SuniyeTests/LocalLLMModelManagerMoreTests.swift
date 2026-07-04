import CryptoKit
import XCTest
@testable import Suniye

final class LocalLLMModelManagerMoreTests: XCTestCase {
    // MARK: - Catalog / value types

    func testModelIDUsesRawValueAsIdentifier() {
        XCTAssertEqual(LocalLLMModelID.gemma4E2BQ4KM.id, LocalLLMModelID.gemma4E2BQ4KM.rawValue)
    }

    func testDownloadProgressFormatsSizesAndPercentage() {
        let progress = LocalLLMDownloadProgress(
            fractionCompleted: 0.5,
            downloadedBytes: 1_000_000,
            expectedBytes: 2_000_000
        )

        XCTAssertEqual(progress.downloadedSizeText, ByteCountFormatter.string(fromByteCount: 1_000_000, countStyle: .file))
        XCTAssertEqual(progress.expectedSizeText, ByteCountFormatter.string(fromByteCount: 2_000_000, countStyle: .file))
        XCTAssertEqual(progress.percentageText, "50%")
    }

    func testModelErrorDescriptionsCoverEveryCase() {
        XCTAssertEqual(
            LocalLLMModelManager.ModelError.appSupportUnavailable.errorDescription,
            "Unable to resolve Application Support directory."
        )
        XCTAssertEqual(
            LocalLLMModelManager.ModelError.unsupportedHardware.errorDescription,
            "Local model requires Apple Silicon."
        )
        XCTAssertEqual(
            LocalLLMModelManager.ModelError.invalidResponse(503).errorDescription,
            "Model download returned HTTP 503."
        )
        XCTAssertEqual(
            LocalLLMModelManager.ModelError.invalidResponse(nil).errorDescription,
            "Model download response was invalid."
        )
        XCTAssertEqual(
            LocalLLMModelManager.ModelError.invalidSize(expected: 9, actual: 4).errorDescription,
            "Model size mismatch. Expected 9 bytes, got 4 bytes."
        )
        XCTAssertEqual(
            LocalLLMModelManager.ModelError.checksumMismatch(expected: "aa", actual: "bb").errorDescription,
            "Model checksum mismatch. Expected aa, got bb."
        )
        XCTAssertEqual(
            LocalLLMModelManager.ModelError.unknownModel.errorDescription,
            "The selected local LLM model is not supported by this build."
        )
    }

    func testCatalogAndPreferredModelExposeConfiguredValues() throws {
        let root = try makeTemporaryDirectory()
        let entry = makeTinyEntry(expectedSHA256: sha256Hex(Data("x".utf8)))
        let manager = LocalLLMModelManager(
            catalog: [entry],
            preferredModelID: .gemma4E2BQ4KM,
            isHardwareSupported: true,
            rootDirectoryProvider: { root },
            downloader: RecordingFileDownloader(data: Data())
        )

        XCTAssertEqual(manager.catalog, [entry])
        XCTAssertEqual(manager.preferredModelID, .gemma4E2BQ4KM)
    }

    // MARK: - Root directory resolution

    func testMissingApplicationSupportDirectoryThrows() {
        let manager = LocalLLMModelManager(
            fileManager: NoApplicationSupportFileManager(),
            isHardwareSupported: true,
            downloader: RecordingFileDownloader(data: Data())
        )

        XCTAssertThrowsError(try manager.modelsRootDirectoryURL()) { error in
            XCTAssertEqual(error as? LocalLLMModelManager.ModelError, .appSupportUnavailable)
        }
    }

    func testDefaultRootDirectoryLivesUnderApplicationSupport() throws {
        let base = try makeTemporaryDirectory()
        let manager = LocalLLMModelManager(
            fileManager: FixedApplicationSupportFileManager(applicationSupportURL: base),
            isHardwareSupported: true,
            downloader: RecordingFileDownloader(data: Data())
        )

        let root = try manager.modelsRootDirectoryURL()

        XCTAssertEqual(
            root.path,
            base.appendingPathComponent("Suniye", isDirectory: true)
                .appendingPathComponent("llm", isDirectory: true).path
        )
    }

    // MARK: - Install state

    func testInstalledByteCountIsZeroForMissingFile() throws {
        let root = try makeTemporaryDirectory()
        let manager = LocalLLMModelManager(
            isHardwareSupported: true,
            rootDirectoryProvider: { root },
            downloader: RecordingFileDownloader(data: Data())
        )

        XCTAssertEqual(manager.installedByteCount(for: .gemma4E2BQ4KM), 0)
    }

    // MARK: - Download validation

    func testDownloadOnUnsupportedHardwareThrows() async throws {
        let root = try makeTemporaryDirectory()
        let manager = LocalLLMModelManager(
            isHardwareSupported: false,
            rootDirectoryProvider: { root },
            downloader: RecordingFileDownloader(data: Data())
        )

        do {
            try await manager.downloadModel(.gemma4E2BQ4KM) { _ in }
            XCTFail("Expected unsupported hardware error")
        } catch let error as LocalLLMModelManager.ModelError {
            XCTAssertEqual(error, .unsupportedHardware)
        }
    }

    func testDownloadRejectsMissingDownloadedFileAsSizeMismatch() async throws {
        let root = try makeTemporaryDirectory()
        let entry = makeTinyEntry(expectedSizeBytes: 10, expectedSHA256: String(repeating: "0", count: 64))
        let manager = LocalLLMModelManager(
            catalog: [entry],
            isHardwareSupported: true,
            rootDirectoryProvider: { root },
            downloader: MissingFileDownloader()
        )

        do {
            try await manager.downloadModel(entry.id) { _ in }
            XCTFail("Expected size mismatch for missing file")
        } catch let error as LocalLLMModelManager.ModelError {
            XCTAssertEqual(error, .invalidSize(expected: 10, actual: 0))
        }
    }

    func testDownloadClearsPreexistingStagingFile() async throws {
        let root = try makeTemporaryDirectory()
        let data = Data("tiny model".utf8)
        let entry = makeTinyEntry(expectedSHA256: sha256Hex(data))
        let manager = LocalLLMModelManager(
            catalog: [entry],
            fileManager: PreexistingStagingFileManager(),
            isHardwareSupported: true,
            rootDirectoryProvider: { root },
            downloader: RecordingFileDownloader(data: data)
        )

        try await manager.downloadModel(entry.id) { _ in }

        let installedURL = try manager.modelFileURL(for: entry.id)
        XCTAssertEqual(try Data(contentsOf: installedURL), data)
    }

    func testRedownloadReplacesExistingInstallAndRemovesBackup() async throws {
        let root = try makeTemporaryDirectory()
        let data = Data("tiny model".utf8)
        let entry = makeTinyEntry(expectedSHA256: sha256Hex(data))
        let manager = LocalLLMModelManager(
            catalog: [entry],
            isHardwareSupported: true,
            rootDirectoryProvider: { root },
            downloader: RecordingFileDownloader(data: data)
        )

        try await manager.downloadModel(entry.id) { _ in }
        try await manager.downloadModel(entry.id) { _ in }

        let installedURL = try manager.modelFileURL(for: entry.id)
        XCTAssertEqual(try Data(contentsOf: installedURL), data)
        XCTAssertTrue(manager.isInstalled(entry.id))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { $0.contains("backup") }
        XCTAssertEqual(leftovers, [])
    }

    func testReplaceInstalledModelRestoresBackupWhenStagedMoveFails() throws {
        let root = try makeTemporaryDirectory()
        let liveURL = root.appendingPathComponent("model.gguf")
        let originalData = Data("original install".utf8)
        try originalData.write(to: liveURL)
        let missingStagedURL = root.appendingPathComponent("missing-staged.gguf")

        XCTAssertThrowsError(
            try LocalLLMModelManager.replaceInstalledModel(at: liveURL, with: missingStagedURL)
        )

        // The failed swap must restore the previous install from its backup.
        XCTAssertEqual(try Data(contentsOf: liveURL), originalData)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { $0.contains("backup") }
        XCTAssertEqual(leftovers, [])
    }

    // MARK: - URLSessionLocalLLMDownloader

    func testURLSessionDownloaderDownloadsLocalFile() async throws {
        let root = try makeTemporaryDirectory()
        let payload = Data("downloaded payload".utf8)
        let sourceURL = root.appendingPathComponent("source.bin")
        try payload.write(to: sourceURL)
        let downloader = URLSessionLocalLLMDownloader()
        let recorder = ProgressRecorder()

        let (downloadedURL, response) = try await downloader.download(
            from: sourceURL,
            fallbackExpectedSizeBytes: Int64(payload.count),
            temporaryFileBasename: "more-tests-model",
            progress: { recorder.record($0) }
        )
        defer {
            try? FileManager.default.removeItem(at: downloadedURL)
        }

        XCTAssertEqual(try Data(contentsOf: downloadedURL), payload)
        XCTAssertNotNil(response)
    }

    func testURLSessionDownloaderPropagatesFailure() async throws {
        let root = try makeTemporaryDirectory()
        let downloader = URLSessionLocalLLMDownloader()

        do {
            _ = try await downloader.download(
                from: root.appendingPathComponent("does-not-exist.bin"),
                fallbackExpectedSizeBytes: 10,
                temporaryFileBasename: "more-tests-missing",
                progress: { _ in }
            )
            XCTFail("Expected download failure for missing file")
        } catch {
            // Expected: URLSession fails to read the missing file.
        }
    }

    func testCancelWithoutActiveTaskIsSafe() {
        let downloader = URLSessionLocalLLMDownloader()
        downloader.cancel()
    }

    func testDidWriteDataReportsProgressForKnownExpectedBytes() async throws {
        let (downloader, recorder) = try await makeSeededDownloader(fallbackExpectedSizeBytes: 500)
        let task = URLSession.shared.downloadTask(with: URL(string: "http://127.0.0.1:9/never")!)

        downloader.urlSession(
            URLSession.shared,
            downloadTask: task,
            didWriteData: 50,
            totalBytesWritten: 50,
            totalBytesExpectedToWrite: 100
        )

        let progress = recorder.all.last
        XCTAssertEqual(progress?.downloadedBytes, 50)
        XCTAssertEqual(progress?.expectedBytes, 100)
        XCTAssertEqual(progress?.fractionCompleted, 0.5)
    }

    func testDidWriteDataFallsBackToCatalogSizeWhenTotalUnknown() async throws {
        let (downloader, recorder) = try await makeSeededDownloader(fallbackExpectedSizeBytes: 500)
        let task = URLSession.shared.downloadTask(with: URL(string: "http://127.0.0.1:9/never")!)

        downloader.urlSession(
            URLSession.shared,
            downloadTask: task,
            didWriteData: 25,
            totalBytesWritten: 25,
            totalBytesExpectedToWrite: 0
        )

        let progress = recorder.all.last
        XCTAssertEqual(progress?.downloadedBytes, 25)
        XCTAssertEqual(progress?.expectedBytes, 500)
    }

    func testDidWriteDataUsesResponseContentLengthWhenTotalUnknown() async throws {
        let (downloader, recorder) = try await makeSeededDownloader(fallbackExpectedSizeBytes: 500)
        let task = try await makeCompletedStubDownloadTask(contentLength: 100)

        downloader.urlSession(
            URLSession.shared,
            downloadTask: task,
            didWriteData: 10,
            totalBytesWritten: 10,
            totalBytesExpectedToWrite: 0
        )

        let progress = recorder.all.last
        XCTAssertEqual(progress?.downloadedBytes, 10)
        XCTAssertEqual(progress?.expectedBytes, 100)
    }

    func testDidWriteDataSkipsProgressWhenNoSizeIsKnown() async throws {
        let (downloader, recorder) = try await makeSeededDownloader(fallbackExpectedSizeBytes: 0)
        let task = URLSession.shared.downloadTask(with: URL(string: "http://127.0.0.1:9/never")!)

        downloader.urlSession(
            URLSession.shared,
            downloadTask: task,
            didWriteData: 5,
            totalBytesWritten: 5,
            totalBytesExpectedToWrite: 0
        )

        XCTAssertFalse(recorder.all.contains { $0.downloadedBytes == 5 })
    }

    func testDidFinishDownloadingToUnreadableLocationFailsGracefully() {
        let downloader = URLSessionLocalLLMDownloader()
        let task = URLSession.shared.downloadTask(with: URL(string: "http://127.0.0.1:9/never")!)

        downloader.urlSession(
            URLSession.shared,
            downloadTask: task,
            didFinishDownloadingTo: URL(fileURLWithPath: "/nonexistent/location-\(UUID().uuidString)")
        )
        // A later completion callback must not double-resume.
        downloader.urlSession(URLSession.shared, task: task, didCompleteWithError: nil)
    }

    func testDidCompleteWithoutDownloadedFileReportsInvalidResponse() {
        let downloader = URLSessionLocalLLMDownloader()
        let task = URLSession.shared.downloadTask(with: URL(string: "http://127.0.0.1:9/never")!)

        downloader.urlSession(URLSession.shared, task: task, didCompleteWithError: nil)
        // Second completion exercises the single-resume guard.
        downloader.urlSession(URLSession.shared, task: task, didCompleteWithError: URLError(.cancelled))
    }

    // MARK: - Helpers

    private func makeSeededDownloader(
        fallbackExpectedSizeBytes: Int64
    ) async throws -> (URLSessionLocalLLMDownloader, ProgressRecorder) {
        // Runs one real (local file) download so the downloader retains the
        // progress block and fallback size used by the delegate callbacks.
        let root = try makeTemporaryDirectory()
        let payload = Data("seed".utf8)
        let sourceURL = root.appendingPathComponent("seed.bin")
        try payload.write(to: sourceURL)
        let downloader = URLSessionLocalLLMDownloader()
        let recorder = ProgressRecorder()
        let (downloadedURL, _) = try await downloader.download(
            from: sourceURL,
            fallbackExpectedSizeBytes: fallbackExpectedSizeBytes,
            temporaryFileBasename: "seed-model",
            progress: { recorder.record($0) }
        )
        try? FileManager.default.removeItem(at: downloadedURL)
        return (downloader, recorder)
    }

    private func makeCompletedStubDownloadTask(contentLength: Int) async throws -> URLSessionDownloadTask {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FixedLengthURLProtocol.self]
        let session = URLSession(configuration: config)
        let task = session.downloadTask(with: URL(string: "https://stub.invalid/model.bin")!)
        task.resume()
        let deadline = Date().addingTimeInterval(5)
        while task.response == nil, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let response = try XCTUnwrap(task.response, "stubbed download task never produced a response")
        XCTAssertEqual(response.expectedContentLength, Int64(contentLength))
        return task
    }

    private func makeTinyEntry(expectedSizeBytes: Int64 = 10, expectedSHA256: String) -> LocalLLMModelCatalogEntry {
        LocalLLMModelCatalogEntry(
            id: .gemma4E2BQ4KM,
            displayName: "Tiny Gemma",
            repository: "example/tiny",
            filename: "tiny.gguf",
            revision: "abc123",
            expectedSizeBytes: expectedSizeBytes,
            expectedSHA256: expectedSHA256
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("suniye-local-llm-more-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Doubles

private final class RecordingFileDownloader: LocalLLMDownloading {
    private let data: Data
    private let statusCode: Int

    init(data: Data, statusCode: Int = 200) {
        self.data = data
        self.statusCode = statusCode
    }

    func download(
        from url: URL,
        fallbackExpectedSizeBytes: Int64,
        temporaryFileBasename: String,
        progress: @escaping @Sendable (LocalLLMDownloadProgress) -> Void
    ) async throws -> (URL, URLResponse) {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(temporaryFileBasename)-\(UUID().uuidString)", isDirectory: false)
        try data.write(to: fileURL)
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Length": "\(data.count)"]
        )!
        return (fileURL, response)
    }

    func cancel() {}
}

/// Returns a downloaded file URL that does not exist, so size validation sees 0 bytes.
private final class MissingFileDownloader: LocalLLMDownloading {
    func download(
        from url: URL,
        fallbackExpectedSizeBytes: Int64,
        temporaryFileBasename: String,
        progress: @escaping @Sendable (LocalLLMDownloadProgress) -> Void
    ) async throws -> (URL, URLResponse) {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString)", isDirectory: false)
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (fileURL, response)
    }

    func cancel() {}
}

private final class NoApplicationSupportFileManager: FileManager {
    override func urls(for directory: FileManager.SearchPathDirectory, in domainMask: FileManager.SearchPathDomainMask) -> [URL] {
        []
    }
}

private final class FixedApplicationSupportFileManager: FileManager {
    private let applicationSupportURL: URL

    init(applicationSupportURL: URL) {
        self.applicationSupportURL = applicationSupportURL
        super.init()
    }

    override func urls(for directory: FileManager.SearchPathDirectory, in domainMask: FileManager.SearchPathDomainMask) -> [URL] {
        [applicationSupportURL]
    }
}

/// Pretends dot-prefixed staging files already exist so downloadModel exercises
/// its stale-staging cleanup; removal of a genuinely missing file is a no-op.
private final class PreexistingStagingFileManager: FileManager {
    override func fileExists(atPath path: String) -> Bool {
        if (path as NSString).lastPathComponent.hasPrefix(".tiny.gguf-") {
            return true
        }
        return super.fileExists(atPath: path)
    }

    override func removeItem(at URL: URL) throws {
        if super.fileExists(atPath: URL.path) {
            try super.removeItem(at: URL)
        }
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [LocalLLMDownloadProgress] = []

    func record(_ progress: LocalLLMDownloadProgress) {
        lock.lock()
        values.append(progress)
        lock.unlock()
    }

    var all: [LocalLLMDownloadProgress] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

private final class FixedLengthURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Length": "100"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(repeating: 0, count: 100))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
