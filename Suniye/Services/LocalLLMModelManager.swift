import CryptoKit
import Foundation

enum LocalLLMModelID: String, CaseIterable, Codable, Identifiable {
    case gemma4E2BQ4KM

    var id: String {
        rawValue
    }
}

struct LocalLLMModelCatalogEntry: Identifiable, Equatable {
    let id: LocalLLMModelID
    let displayName: String
    let repository: String
    let filename: String
    let revision: String
    let expectedSizeBytes: Int64
    let expectedSHA256: String

    var downloadURL: URL {
        URL(string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(filename)")!
    }

    var expectedSizeText: String {
        ByteCountFormatter.string(fromByteCount: expectedSizeBytes, countStyle: .file)
    }
}

enum LocalLLMModelCatalog {
    static let gemma4E2BQ4KM = LocalLLMModelCatalogEntry(
        id: .gemma4E2BQ4KM,
        displayName: "Gemma 4 E2B Instruct Q4_K_M",
        repository: "dahus/gemma-4-e2b-it-Q4_K_M-GGUF",
        filename: "gemma-4-e2b-Q4_K_M.gguf",
        revision: "4f3551c3ccd2cb0c06bd09ac57ad0539392a0d5c",
        expectedSizeBytes: 3_427_873_408,
        expectedSHA256: "d075ddeea9b056b6488af98e4c3776604c7c3196f1e55155c88a085027ab6d31"
    )

    static let entries: [LocalLLMModelCatalogEntry] = [
        gemma4E2BQ4KM,
    ]

    static let preferredModelID: LocalLLMModelID = .gemma4E2BQ4KM

    static func entry(for modelID: LocalLLMModelID) -> LocalLLMModelCatalogEntry {
        switch modelID {
        case .gemma4E2BQ4KM:
            return gemma4E2BQ4KM
        }
    }
}

enum LocalLLMHardware {
    static var isAppleSilicon: Bool {
        #if arch(arm64)
            return true
        #else
            return false
        #endif
    }
}

struct LocalLLMDownloadProgress: Equatable {
    let fractionCompleted: Double
    let downloadedBytes: Int64
    let expectedBytes: Int64

    var downloadedSizeText: String {
        ByteCountFormatter.string(fromByteCount: downloadedBytes, countStyle: .file)
    }

    var expectedSizeText: String {
        ByteCountFormatter.string(fromByteCount: expectedBytes, countStyle: .file)
    }

    var percentageText: String {
        "\(Int(fractionCompleted * 100))%"
    }
}

enum LocalLLMInstallState: Equatable {
    case unavailable(String)
    case notInstalled
    case downloading(LocalLLMDownloadProgress)
    case verifying
    case installed(Int64)
    case failed(String)

    var isInstalled: Bool {
        if case .installed = self {
            return true
        }
        return false
    }

    var isActive: Bool {
        switch self {
        case .downloading, .verifying:
            return true
        case .unavailable, .notInstalled, .installed, .failed:
            return false
        }
    }
}

protocol LocalLLMModelManagerProtocol: AnyObject {
    var catalog: [LocalLLMModelCatalogEntry] { get }
    var preferredModelID: LocalLLMModelID { get }
    var isHardwareSupported: Bool { get }
    func modelsRootDirectoryURL() throws -> URL
    func modelFileURL(for modelID: LocalLLMModelID) throws -> URL
    func isInstalled(_ modelID: LocalLLMModelID) -> Bool
    func installedByteCount(for modelID: LocalLLMModelID) -> Int64
    func installState(for modelID: LocalLLMModelID) -> LocalLLMInstallState
    func downloadModel(_ modelID: LocalLLMModelID, progress: @escaping @Sendable (LocalLLMDownloadProgress) -> Void) async throws
    func cancelDownload()
    func deleteModel(_ modelID: LocalLLMModelID) throws
}

protocol LocalLLMDownloading: AnyObject {
    func download(
        from url: URL,
        fallbackExpectedSizeBytes: Int64,
        temporaryFileBasename: String,
        progress: @escaping @Sendable (LocalLLMDownloadProgress) -> Void
    ) async throws -> (URL, URLResponse)
    func cancel()
}

final class LocalLLMModelManager: LocalLLMModelManagerProtocol {
    enum ModelError: LocalizedError, Equatable {
        case appSupportUnavailable
        case unsupportedHardware
        case invalidResponse(Int?)
        case invalidSize(expected: Int64, actual: Int64)
        case checksumMismatch(expected: String, actual: String)
        case unknownModel

        var errorDescription: String? {
            switch self {
            case .appSupportUnavailable:
                return "Unable to resolve Application Support directory."
            case .unsupportedHardware:
                return "Local model requires Apple Silicon."
            case let .invalidResponse(statusCode):
                if let statusCode {
                    return "Model download returned HTTP \(statusCode)."
                }
                return "Model download response was invalid."
            case let .invalidSize(expected, actual):
                return "Model size mismatch. Expected \(expected) bytes, got \(actual) bytes."
            case let .checksumMismatch(expected, actual):
                return "Model checksum mismatch. Expected \(expected), got \(actual)."
            case .unknownModel:
                return "The selected local LLM model is not supported by this build."
            }
        }
    }

    var catalog: [LocalLLMModelCatalogEntry] {
        catalogEntries
    }

    var preferredModelID: LocalLLMModelID {
        preferred
    }

    let isHardwareSupported: Bool

    private let catalogEntries: [LocalLLMModelCatalogEntry]
    private let preferred: LocalLLMModelID
    private let fileManager: FileManager
    private let rootDirectoryProvider: () throws -> URL
    private let downloader: LocalLLMDownloading

    init(
        catalog: [LocalLLMModelCatalogEntry] = LocalLLMModelCatalog.entries,
        preferredModelID: LocalLLMModelID = LocalLLMModelCatalog.preferredModelID,
        fileManager: FileManager = .default,
        isHardwareSupported: Bool = LocalLLMHardware.isAppleSilicon,
        rootDirectoryProvider: (() throws -> URL)? = nil,
        downloader: LocalLLMDownloading = URLSessionLocalLLMDownloader()
    ) {
        catalogEntries = catalog
        preferred = preferredModelID
        self.fileManager = fileManager
        self.isHardwareSupported = isHardwareSupported
        self.downloader = downloader
        self.rootDirectoryProvider = rootDirectoryProvider ?? {
            guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                throw ModelError.appSupportUnavailable
            }
            return appSupport
                .appendingPathComponent("Suniye", isDirectory: true)
                .appendingPathComponent("llm", isDirectory: true)
        }
    }

    func modelsRootDirectoryURL() throws -> URL {
        let dir = try rootDirectoryProvider()
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func modelFileURL(for modelID: LocalLLMModelID) throws -> URL {
        try modelsRootDirectoryURL().appendingPathComponent(catalogEntry(for: modelID).filename)
    }

    func isInstalled(_ modelID: LocalLLMModelID) -> Bool {
        guard isHardwareSupported,
              let modelURL = try? modelFileURL(for: modelID),
              fileManager.fileExists(atPath: modelURL.path) else {
            return false
        }
        let entry = catalogEntry(for: modelID)
        return installedByteCount(for: modelID) == entry.expectedSizeBytes
    }

    func installedByteCount(for modelID: LocalLLMModelID) -> Int64 {
        guard let modelURL = try? modelFileURL(for: modelID),
              let attributes = try? fileManager.attributesOfItem(atPath: modelURL.path),
              let size = attributes[.size] as? NSNumber else {
            return 0
        }
        return size.int64Value
    }

    func installState(for modelID: LocalLLMModelID) -> LocalLLMInstallState {
        guard isHardwareSupported else {
            return .unavailable("Requires Apple Silicon.")
        }
        guard isInstalled(modelID) else {
            return .notInstalled
        }
        return .installed(installedByteCount(for: modelID))
    }

    func downloadModel(
        _ modelID: LocalLLMModelID,
        progress: @escaping @Sendable (LocalLLMDownloadProgress) -> Void
    ) async throws {
        guard isHardwareSupported else {
            throw ModelError.unsupportedHardware
        }

        let entry = catalogEntry(for: modelID)
        let rootDirectory = try modelsRootDirectoryURL()
        let stagingURL = rootDirectory
            .appendingPathComponent(".\(entry.filename)-\(UUID().uuidString)", isDirectory: false)
        defer {
            if fileManager.fileExists(atPath: stagingURL.path) {
                try? fileManager.removeItem(at: stagingURL)
            }
        }

        let (downloadedURL, response) = try await downloader.download(
            from: entry.downloadURL,
            fallbackExpectedSizeBytes: entry.expectedSizeBytes,
            temporaryFileBasename: entry.filename,
            progress: progress
        )
        defer {
            if fileManager.fileExists(atPath: downloadedURL.path) {
                try? fileManager.removeItem(at: downloadedURL)
            }
        }

        let statusCode = (response as? HTTPURLResponse)?.statusCode
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw ModelError.invalidResponse(statusCode)
        }

        let actualSize = fileSize(at: downloadedURL)
        guard actualSize == entry.expectedSizeBytes else {
            throw ModelError.invalidSize(expected: entry.expectedSizeBytes, actual: actualSize)
        }

        let actualSHA = try sha256Hex(for: downloadedURL)
        guard actualSHA == entry.expectedSHA256 else {
            throw ModelError.checksumMismatch(expected: entry.expectedSHA256, actual: actualSHA)
        }

        if fileManager.fileExists(atPath: stagingURL.path) {
            try fileManager.removeItem(at: stagingURL)
        }
        try fileManager.moveItem(at: downloadedURL, to: stagingURL)

        let liveURL = try modelFileURL(for: modelID)
        try Self.replaceInstalledModel(at: liveURL, with: stagingURL, fileManager: fileManager)
        progress(LocalLLMDownloadProgress(
            fractionCompleted: 1,
            downloadedBytes: entry.expectedSizeBytes,
            expectedBytes: entry.expectedSizeBytes
        ))
    }

    func cancelDownload() {
        downloader.cancel()
    }

    func deleteModel(_ modelID: LocalLLMModelID) throws {
        let modelURL = try modelFileURL(for: modelID)
        if fileManager.fileExists(atPath: modelURL.path) {
            try fileManager.removeItem(at: modelURL)
        }
    }

    static func replaceInstalledModel(at liveURL: URL, with stagedURL: URL, fileManager: FileManager = .default) throws {
        let backupURL = liveURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(liveURL.lastPathComponent)-backup-\(UUID().uuidString)", isDirectory: false)
        let hadExistingInstall = fileManager.fileExists(atPath: liveURL.path)

        do {
            if hadExistingInstall {
                try fileManager.moveItem(at: liveURL, to: backupURL)
            }
            try fileManager.moveItem(at: stagedURL, to: liveURL)
            if hadExistingInstall, fileManager.fileExists(atPath: backupURL.path) {
                try? fileManager.removeItem(at: backupURL)
            }
        } catch {
            if hadExistingInstall,
               !fileManager.fileExists(atPath: liveURL.path),
               fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.moveItem(at: backupURL, to: liveURL)
            }
            throw error
        }
    }

    private func catalogEntry(for modelID: LocalLLMModelID) -> LocalLLMModelCatalogEntry {
        catalogEntries.first { $0.id == modelID } ?? LocalLLMModelCatalog.entry(for: modelID)
    }

    private func fileSize(at url: URL) -> Int64 {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return 0
        }
        return size.int64Value
    }

    private func sha256Hex(for url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }

        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let data = handle.readData(ofLength: 1024 * 1024)
            guard !data.isEmpty else {
                return false
            }
            hasher.update(data: data)
            return true
        }) {}

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

final class URLSessionLocalLLMDownloader: NSObject, LocalLLMDownloading, URLSessionDownloadDelegate {
    private let lock = NSLock()
    private var activeTask: URLSessionDownloadTask?
    private var continuation: CheckedContinuation<(URL, URLResponse), Error>?
    private var downloadedFileURL: URL?
    private var downloadResponse: URLResponse?
    private var hasResumed = false
    private var progressBlock: (@Sendable (LocalLLMDownloadProgress) -> Void)?
    private var fallbackExpectedSizeBytes: Int64 = 0
    private var temporaryFileBasename = "local-llm-model"

    func download(
        from url: URL,
        fallbackExpectedSizeBytes: Int64,
        temporaryFileBasename: String,
        progress: @escaping @Sendable (LocalLLMDownloadProgress) -> Void
    ) async throws -> (URL, URLResponse) {
        self.progressBlock = progress
        self.fallbackExpectedSizeBytes = fallbackExpectedSizeBytes
        self.temporaryFileBasename = temporaryFileBasename
        hasResumed = false
        downloadedFileURL = nil
        downloadResponse = nil

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        defer {
            session.finishTasksAndInvalidate()
            lock.withLock {
                activeTask = nil
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let task = session.downloadTask(with: url)
            lock.withLock {
                activeTask = task
            }
            task.resume()
        }
    }

    func cancel() {
        lock.withLock {
            activeTask?.cancel()
            activeTask = nil
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let expectedBytes: Int64
        if totalBytesExpectedToWrite > 0 {
            expectedBytes = totalBytesExpectedToWrite
        } else if downloadTask.response?.expectedContentLength ?? 0 > 0 {
            expectedBytes = downloadTask.response?.expectedContentLength ?? fallbackExpectedSizeBytes
        } else {
            expectedBytes = fallbackExpectedSizeBytes
        }

        guard expectedBytes > 0,
              let fraction = ModelDownloadProgressEstimator.estimate(
                  totalBytesWritten: totalBytesWritten,
                  totalBytesExpectedToWrite: totalBytesExpectedToWrite,
                  responseExpectedLength: downloadTask.response?.expectedContentLength,
                  fallbackExpectedSize: fallbackExpectedSizeBytes
              ) else {
            return
        }

        progressBlock?(LocalLLMDownloadProgress(
            fractionCompleted: fraction,
            downloadedBytes: max(totalBytesWritten, 0),
            expectedBytes: expectedBytes
        ))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            let fileManager = FileManager.default
            let persistedURL = fileManager.temporaryDirectory
                .appendingPathComponent("\(temporaryFileBasename)-\(UUID().uuidString)", isDirectory: false)
            if fileManager.fileExists(atPath: persistedURL.path) {
                try fileManager.removeItem(at: persistedURL)
            }
            try fileManager.moveItem(at: location, to: persistedURL)
            downloadedFileURL = persistedURL
            downloadResponse = downloadTask.response
        } catch {
            resume(with: .failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            resume(with: .failure(error))
            return
        }

        guard let downloadedFileURL, let downloadResponse else {
            resume(with: .failure(LocalLLMModelManager.ModelError.invalidResponse(nil)))
            return
        }

        resume(with: .success((downloadedFileURL, downloadResponse)))
    }

    private func resume(with result: Result<(URL, URLResponse), Error>) {
        guard !hasResumed else {
            return
        }
        hasResumed = true
        continuation?.resume(with: result)
        continuation = nil
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
