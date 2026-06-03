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
