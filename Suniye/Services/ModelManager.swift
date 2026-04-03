import Foundation

enum ModelDownloadProgressEstimator {
    static func estimate(
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64,
        responseExpectedLength: Int64?,
        fallbackExpectedSize: Int64
    ) -> Double? {
        let expectedBytes: Int64
        if totalBytesExpectedToWrite > 0 {
            expectedBytes = totalBytesExpectedToWrite
        } else if let responseExpectedLength, responseExpectedLength > 0 {
            expectedBytes = responseExpectedLength
        } else if fallbackExpectedSize > 0 {
            expectedBytes = fallbackExpectedSize
        } else {
            return nil
        }

        guard totalBytesWritten >= 0 else {
            return nil
        }

        return min(max(Double(totalBytesWritten) / Double(expectedBytes), 0), 1)
    }
}

protocol ModelManagerProtocol {
    var expectedDownloadSizeBytes: Int64 { get }
    func modelDirectoryURL() throws -> URL
    func isModelReady() -> Bool
    func makeRecognizerConfig() throws -> RecognizerConfig
    func downloadAndExtractModel(progress: @escaping @Sendable (Double) -> Void) async throws
    func installedByteCount() -> Int64
    func deleteModel() throws
}

final class ModelManager: ModelManagerProtocol {
    enum ModelError: LocalizedError {
        case appSupportUnavailable
        case invalidResponse
        case extractFailed(String)

        var errorDescription: String? {
            switch self {
            case .appSupportUnavailable:
                return "Unable to resolve Application Support directory"
            case .invalidResponse:
                return "Model download response was invalid"
            case let .extractFailed(reason):
                return "Model extraction failed: \(reason)"
            }
        }
    }

    private let modelDownloadURL = URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8.tar.bz2")!
    private let requiredFiles = ["encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx", "tokens.txt"]
    let expectedDownloadSizeBytes: Int64 = 680_000_000

    func modelDirectoryURL() throws -> URL {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw ModelError.appSupportUnavailable
        }

        let dir = appSupport
            .appendingPathComponent("Suniye", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8", isDirectory: true)

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func isModelReady() -> Bool {
        do {
            let dir = try modelDirectoryURL()
            return requiredFiles.allSatisfy { FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path) }
        } catch {
            return false
        }
    }

    func makeRecognizerConfig() throws -> RecognizerConfig {
        let dir = try modelDirectoryURL()

        return RecognizerConfig(
            encoderPath: dir.appendingPathComponent("encoder.int8.onnx").path,
            decoderPath: dir.appendingPathComponent("decoder.int8.onnx").path,
            joinerPath: dir.appendingPathComponent("joiner.int8.onnx").path,
            tokensPath: dir.appendingPathComponent("tokens.txt").path,
            numThreads: 4
        )
    }

    func downloadAndExtractModel(progress: @escaping @Sendable (Double) -> Void) async throws {
        let destinationDir = try modelDirectoryURL().deletingLastPathComponent()

        let downloader = DownloadDelegate(progress: progress, fallbackExpectedSizeBytes: expectedDownloadSizeBytes)
        let session = URLSession(configuration: .default, delegate: downloader, delegateQueue: nil)
        defer {
            session.finishTasksAndInvalidate()
        }

        let (url, response) = try await downloader.download(from: modelDownloadURL, using: session)
        defer {
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
        }

        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw ModelError.invalidResponse
        }

        try extract(archive: url, into: destinationDir)

        progress(1)
    }

    func installedByteCount() -> Int64 {
        guard let directoryURL = try? modelDirectoryURL(),
              let enumerator = FileManager.default.enumerator(at: directoryURL, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]) else {
            return 0
        }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set([.isRegularFileKey, .fileSizeKey]))
            if values?.isRegularFile == true {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }

    func deleteModel() throws {
        let modelDirectory = try modelDirectoryURL()
        if FileManager.default.fileExists(atPath: modelDirectory.path) {
            try FileManager.default.removeItem(at: modelDirectory)
        }
    }

    private func extract(archive: URL, into destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xjf", archive.path, "-C", destination.path]

        let stderr = Pipe()
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "unknown tar error"
            throw ModelError.extractFailed(message)
        }
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    private let progressBlock: @Sendable (Double) -> Void
    private let fallbackExpectedSizeBytes: Int64
    private let fileManager = FileManager.default
    private var continuation: CheckedContinuation<(URL, URLResponse), Error>?
    private var downloadedFileURL: URL?
    private var downloadResponse: URLResponse?
    private var hasResumed = false

    init(progress: @escaping @Sendable (Double) -> Void, fallbackExpectedSizeBytes: Int64) {
        self.progressBlock = progress
        self.fallbackExpectedSizeBytes = fallbackExpectedSizeBytes
    }

    func download(from url: URL, using session: URLSession) async throws -> (URL, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let task = session.downloadTask(with: url)
            task.resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let value = ModelDownloadProgressEstimator.estimate(
            totalBytesWritten: totalBytesWritten,
            totalBytesExpectedToWrite: totalBytesExpectedToWrite,
            responseExpectedLength: downloadTask.response?.expectedContentLength,
            fallbackExpectedSize: fallbackExpectedSizeBytes
        ) else {
            return
        }
        progressBlock(value)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            let persistedURL = fileManager.temporaryDirectory
                .appendingPathComponent("parakeet-model-\(UUID().uuidString)", isDirectory: false)
                .appendingPathExtension("tar.bz2")
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
            resume(with: .failure(ModelManager.ModelError.invalidResponse))
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
