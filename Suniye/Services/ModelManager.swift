import Foundation

final class ModelManager {
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
        let tempArchive = FileManager.default.temporaryDirectory.appendingPathComponent("parakeet-model.tar.bz2")
        let destinationDir = try modelDirectoryURL().deletingLastPathComponent()

        let downloader = DownloadDelegate(progress: progress)
        let session = URLSession(configuration: .default, delegate: downloader, delegateQueue: nil)

        let (url, response) = try await session.download(from: modelDownloadURL)

        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw ModelError.invalidResponse
        }

        if FileManager.default.fileExists(atPath: tempArchive.path) {
            try FileManager.default.removeItem(at: tempArchive)
        }
        try FileManager.default.moveItem(at: url, to: tempArchive)

        try extract(archive: tempArchive, into: destinationDir)

        if FileManager.default.fileExists(atPath: tempArchive.path) {
            try? FileManager.default.removeItem(at: tempArchive)
        }

        progress(1)
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

    init(progress: @escaping @Sendable (Double) -> Void) {
        self.progressBlock = progress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else {
            return
        }
        let value = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressBlock(value)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // No-op: async `session.download(from:)` returns the temp file URL directly.
    }
}
