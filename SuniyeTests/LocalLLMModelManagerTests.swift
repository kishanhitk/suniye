import CryptoKit
import XCTest
@testable import Suniye

final class LocalLLMModelManagerTests: XCTestCase {
    func testPinnedCatalogMetadata() {
        let entry = LocalLLMModelCatalog.entry(for: .gemma4E2BQ4KM)

        XCTAssertEqual(entry.repository, "dahus/gemma-4-e2b-it-Q4_K_M-GGUF")
        XCTAssertEqual(entry.filename, "gemma-4-e2b-Q4_K_M.gguf")
        XCTAssertEqual(entry.revision, "4f3551c3ccd2cb0c06bd09ac57ad0539392a0d5c")
        XCTAssertEqual(entry.expectedSizeBytes, 3_427_873_408)
        XCTAssertEqual(entry.expectedSHA256, "d075ddeea9b056b6488af98e4c3776604c7c3196f1e55155c88a085027ab6d31")
        XCTAssertEqual(
            entry.downloadURL.absoluteString,
            "https://huggingface.co/dahus/gemma-4-e2b-it-Q4_K_M-GGUF/resolve/4f3551c3ccd2cb0c06bd09ac57ad0539392a0d5c/gemma-4-e2b-Q4_K_M.gguf"
        )
    }

    func testUnsupportedHardwareReportsUnavailable() throws {
        let root = try makeTemporaryDirectory()
        let manager = LocalLLMModelManager(
            isHardwareSupported: false,
            rootDirectoryProvider: { root },
            downloader: FakeLocalLLMDownloader(data: Data())
        )

        XCTAssertFalse(manager.isInstalled(.gemma4E2BQ4KM))
        XCTAssertEqual(manager.installState(for: .gemma4E2BQ4KM), .unavailable("Requires Apple Silicon."))
    }

    func testDownloadInstallsValidatedModelAtomically() async throws {
        let root = try makeTemporaryDirectory()
        let data = Data("tiny model".utf8)
        let entry = makeTinyEntry(expectedSHA256: sha256Hex(data))
        let downloader = FakeLocalLLMDownloader(data: data)
        let manager = LocalLLMModelManager(
            catalog: [entry],
            isHardwareSupported: true,
            rootDirectoryProvider: { root },
            downloader: downloader
        )
        var progressValues: [LocalLLMDownloadProgress] = []

        try await manager.downloadModel(entry.id) { progress in
            progressValues.append(progress)
        }

        let installedURL = try manager.modelFileURL(for: entry.id)
        XCTAssertEqual(try Data(contentsOf: installedURL), data)
        XCTAssertTrue(manager.isInstalled(entry.id))
        XCTAssertEqual(manager.installState(for: entry.id), .installed(Int64(data.count)))
        XCTAssertEqual(progressValues.last?.fractionCompleted, 1)
    }

    func testDownloadRejectsFailedHTTPResponse() async throws {
        let root = try makeTemporaryDirectory()
        let entry = makeTinyEntry(expectedSHA256: sha256Hex(Data("tiny model".utf8)))
        let manager = LocalLLMModelManager(
            catalog: [entry],
            isHardwareSupported: true,
            rootDirectoryProvider: { root },
            downloader: FakeLocalLLMDownloader(data: Data("tiny model".utf8), statusCode: 404)
        )

        do {
            try await manager.downloadModel(entry.id) { _ in }
            XCTFail("Expected invalid response")
        } catch let error as LocalLLMModelManager.ModelError {
            XCTAssertEqual(error, .invalidResponse(404))
        }
    }

    func testDownloadRejectsSizeMismatch() async throws {
        let root = try makeTemporaryDirectory()
        let entry = makeTinyEntry(expectedSizeBytes: 99, expectedSHA256: sha256Hex(Data("tiny model".utf8)))
        let manager = LocalLLMModelManager(
            catalog: [entry],
            isHardwareSupported: true,
            rootDirectoryProvider: { root },
            downloader: FakeLocalLLMDownloader(data: Data("tiny model".utf8))
        )

        do {
            try await manager.downloadModel(entry.id) { _ in }
            XCTFail("Expected size mismatch")
        } catch let error as LocalLLMModelManager.ModelError {
            XCTAssertEqual(error, .invalidSize(expected: 99, actual: 10))
        }
    }

    func testDownloadRejectsSHAMismatch() async throws {
        let root = try makeTemporaryDirectory()
        let data = Data("tiny model".utf8)
        let entry = makeTinyEntry(expectedSHA256: String(repeating: "0", count: 64))
        let manager = LocalLLMModelManager(
            catalog: [entry],
            isHardwareSupported: true,
            rootDirectoryProvider: { root },
            downloader: FakeLocalLLMDownloader(data: data)
        )

        do {
            try await manager.downloadModel(entry.id) { _ in }
            XCTFail("Expected checksum mismatch")
        } catch let error as LocalLLMModelManager.ModelError {
            XCTAssertEqual(error, .checksumMismatch(expected: String(repeating: "0", count: 64), actual: sha256Hex(data)))
        }
    }

    func testDeleteModelRemovesInstalledFile() async throws {
        let root = try makeTemporaryDirectory()
        let data = Data("tiny model".utf8)
        let entry = makeTinyEntry(expectedSHA256: sha256Hex(data))
        let manager = LocalLLMModelManager(
            catalog: [entry],
            isHardwareSupported: true,
            rootDirectoryProvider: { root },
            downloader: FakeLocalLLMDownloader(data: data)
        )

        try await manager.downloadModel(entry.id) { _ in }
        try manager.deleteModel(entry.id)

        XCTAssertFalse(manager.isInstalled(entry.id))
        XCTAssertEqual(manager.installState(for: entry.id), .notInstalled)
    }

    func testCancelDownloadForwardsToDownloader() throws {
        let root = try makeTemporaryDirectory()
        let downloader = FakeLocalLLMDownloader(data: Data())
        let manager = LocalLLMModelManager(
            isHardwareSupported: true,
            rootDirectoryProvider: { root },
            downloader: downloader
        )

        manager.cancelDownload()

        XCTAssertEqual(downloader.cancelCallCount, 1)
    }

    func testDownloadProgressPercentageTruncatesFraction() {
        XCTAssertEqual(LocalLLMDownloadProgress(fractionCompleted: 0.5, downloadedBytes: 1, expectedBytes: 2).percentageText, "50%")
        XCTAssertEqual(LocalLLMDownloadProgress(fractionCompleted: 0.999, downloadedBytes: 999, expectedBytes: 1_000).percentageText, "99%")
    }

    func testMissingApplicationSupportDirectoryThrows() {
        let manager = LocalLLMModelManager(
            fileManager: NoApplicationSupportFileManager(),
            isHardwareSupported: true,
            downloader: FakeLocalLLMDownloader(data: Data())
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
            downloader: FakeLocalLLMDownloader(data: Data())
        )

        let root = try manager.modelsRootDirectoryURL()

        XCTAssertEqual(
            root.path,
            base.appendingPathComponent("Suniye", isDirectory: true)
                .appendingPathComponent("llm", isDirectory: true).path
        )
    }

    func testInstalledByteCountIsZeroForMissingFile() throws {
        let root = try makeTemporaryDirectory()
        let manager = LocalLLMModelManager(
            isHardwareSupported: true,
            rootDirectoryProvider: { root },
            downloader: FakeLocalLLMDownloader(data: Data())
        )

        XCTAssertEqual(manager.installedByteCount(for: .gemma4E2BQ4KM), 0)
    }

    func testDownloadOnUnsupportedHardwareThrows() async throws {
        let root = try makeTemporaryDirectory()
        let manager = LocalLLMModelManager(
            isHardwareSupported: false,
            rootDirectoryProvider: { root },
            downloader: FakeLocalLLMDownloader(data: Data())
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

    func testRedownloadReplacesExistingInstallAndRemovesBackup() async throws {
        let root = try makeTemporaryDirectory()
        let data = Data("tiny model".utf8)
        let entry = makeTinyEntry(expectedSHA256: sha256Hex(data))
        let manager = LocalLLMModelManager(
            catalog: [entry],
            isHardwareSupported: true,
            rootDirectoryProvider: { root },
            downloader: FakeLocalLLMDownloader(data: data)
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
            temporaryFileBasename: "tests-model",
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
                temporaryFileBasename: "tests-missing",
                progress: { _ in }
            )
            XCTFail("Expected download failure for missing file")
        } catch {
            // Expected: URLSession fails to read the missing file.
        }
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
        let url = URL(string: "https://stub.invalid/model.bin")!
        StubURLProtocol.serve([url: .init(body: Data(repeating: 0, count: contentLength))])
        let session = URLSession(configuration: StubURLProtocol.sessionConfiguration())
        let task = session.downloadTask(with: url)
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
            .appendingPathComponent("suniye-local-llm-tests-\(UUID().uuidString)", isDirectory: true)
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

private final class FakeLocalLLMDownloader: LocalLLMDownloading {
    let data: Data
    let statusCode: Int
    private(set) var cancelCallCount = 0

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
        progress(LocalLLMDownloadProgress(
            fractionCompleted: fallbackExpectedSizeBytes > 0 ? min(Double(data.count) / Double(fallbackExpectedSizeBytes), 1) : 1,
            downloadedBytes: Int64(data.count),
            expectedBytes: fallbackExpectedSizeBytes
        ))
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Length": "\(data.count)"]
        )!
        return (fileURL, response)
    }

    func cancel() {
        cancelCallCount += 1
    }
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
