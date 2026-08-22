import CryptoKit
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
    var catalog: [ASRModelCatalogEntry] { get }
    var fallbackOrder: [ASRModelID] { get }
    func modelsRootDirectoryURL() throws -> URL
    func modelDirectoryURL(for modelID: ASRModelID) throws -> URL
    func isInstalled(_ modelID: ASRModelID) -> Bool
    /// Whether a system-managed model's actual on-device asset is present (async, since it
    /// queries the OS). For file-based models this mirrors `isInstalled`.
    func isSystemManagedAssetInstalled(_ modelID: ASRModelID) async -> Bool
    func installedModels() -> [ASRModelID]
    func makeRecognizerConfig(for modelID: ASRModelID) throws -> RecognizerConfig
    func downloadAndExtractModel(_ modelID: ASRModelID, progress: @escaping @Sendable (Double) -> Void) async throws
    func expectedDownloadSizeBytes(for modelID: ASRModelID) -> Int64
    func installedByteCount(for modelID: ASRModelID) -> Int64
    func deleteModel(_ modelID: ASRModelID) throws
}

extension ModelManagerProtocol {
    /// Default: file-based conformers have no async asset, so mirror `isInstalled`.
    func isSystemManagedAssetInstalled(_ modelID: ASRModelID) async -> Bool {
        isInstalled(modelID)
    }
}

final class ModelManager: ModelManagerProtocol {
    enum ModelError: LocalizedError {
        case appSupportUnavailable
        case invalidResponse
        case unknownModel
        case extractFailed(String)
        case checksumMismatch(String)

        var errorDescription: String? {
            switch self {
            case .appSupportUnavailable:
                return "Unable to resolve Application Support directory"
            case .invalidResponse:
                return "Model download response was invalid"
            case .unknownModel:
                return "The selected model is not supported by this build"
            case let .extractFailed(reason):
                return "Model extraction failed: \(reason)"
            case let .checksumMismatch(file):
                return "Downloaded model file failed verification: \(file)"
            }
        }
    }

    private let applicationSupportDirectory: URL?
    private let urlSessionConfiguration: URLSessionConfiguration

    init(
        applicationSupportDirectory: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
        urlSessionConfiguration: URLSessionConfiguration = .default
    ) {
        self.applicationSupportDirectory = applicationSupportDirectory
        self.urlSessionConfiguration = urlSessionConfiguration
    }

    var catalog: [ASRModelCatalogEntry] {
        // System-managed entries (Apple SpeechTranscriber) are filtered out on devices
        // that don't support them, which cascades to installed-model discovery, fallback,
        // and the UI — hiding the Apple option entirely on macOS < 26.
        ASRModelCatalog.availableEntries
    }

    var fallbackOrder: [ASRModelID] {
        ASRModelCatalog.fallbackOrder
    }

    func modelsRootDirectoryURL() throws -> URL {
        guard let appSupport = applicationSupportDirectory else {
            throw ModelError.appSupportUnavailable
        }

        let dir = appSupport
            .appendingPathComponent("Suniye", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func modelDirectoryURL(for modelID: ASRModelID) throws -> URL {
        let entry = catalogEntry(for: modelID)
        guard !entry.isSystemManaged else {
            // System-managed models have no on-disk directory we control.
            throw ModelError.unknownModel
        }
        return try modelsRootDirectoryURL()
            .appendingPathComponent(entry.directoryName, isDirectory: true)
    }

    func isInstalled(_ modelID: ASRModelID) -> Bool {
        let entry = catalogEntry(for: modelID)
        if entry.isSystemManaged {
            // "Installed" for a system-managed model means the OS can run it; the
            // per-locale asset is ensured lazily at load time.
            return entry.isAvailableOnThisDevice
        }
        do {
            let dir = try modelDirectoryURL(for: modelID)
            return entry.manifest.requiredRelativePaths.allSatisfy {
                FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path)
            }
        } catch {
            return false
        }
    }

    func isSystemManagedAssetInstalled(_ modelID: ASRModelID) async -> Bool {
        guard catalogEntry(for: modelID).isSystemManaged else {
            return isInstalled(modelID)
        }
        if #available(macOS 26, *) {
            return await AppleSpeechAssetInstaller.isInstalled()
        }
        return false
    }

    func installedModels() -> [ASRModelID] {
        // System-managed models (Apple Speech) are opt-in: they are always "available"
        // on a supported OS, but must not count as installed for onboarding or
        // auto-fallback, or a fresh macOS 26 user would silently bypass the default
        // Parakeet download. They remain selectable via the per-model isInstalled path.
        catalog
            .filter { !$0.isSystemManaged }
            .map(\.id)
            .filter(isInstalled)
    }

    func makeRecognizerConfig(for modelID: ASRModelID) throws -> RecognizerConfig {
        let entry = try installedEntry(for: modelID)

        if entry.isSystemManaged {
            // No file paths: the routing service dispatches this to the Apple engine,
            // which resolves the locale (empty hint → the user's current locale).
            return RecognizerConfig(
                modelID: modelID,
                family: entry.family,
                tokensPath: "",
                numThreads: 4,
                language: entry.languageHint,
                task: entry.taskHint,
                modelType: entry.recognizerModelType,
                useInverseTextNormalization: entry.useInverseTextNormalization
            )
        }

        let dir = try modelDirectoryURL(for: modelID)

        func path(_ relativePath: String?) -> String? {
            relativePath.map { dir.appendingPathComponent($0).path }
        }

        return RecognizerConfig(
            modelID: modelID,
            family: entry.family,
            tokensPath: dir.appendingPathComponent(entry.manifest.tokens).path,
            numThreads: 4,
            encoderPath: path(entry.manifest.encoder),
            decoderPath: path(entry.manifest.decoder),
            joinerPath: path(entry.manifest.joiner),
            preprocessorPath: path(entry.manifest.preprocessor),
            uncachedDecoderPath: path(entry.manifest.uncachedDecoder),
            cachedDecoderPath: path(entry.manifest.cachedDecoder),
            modelPath: path(entry.manifest.model),
            language: entry.languageHint,
            task: entry.taskHint,
            modelType: entry.recognizerModelType,
            useInverseTextNormalization: entry.useInverseTextNormalization
        )
    }

    func downloadAndExtractModel(_ modelID: ASRModelID, progress: @escaping @Sendable (Double) -> Void) async throws {
        let entry = try installedEntry(for: modelID)

        if entry.isSystemManaged {
            // The OS owns the asset, but the first fetch for an uncached locale can be a
            // large download — run it here so it flows through the normal progress UI
            // rather than stalling silently inside loadModel. On an OS/device where the
            // provider isn't available there is nothing to fetch.
            if #available(macOS 26, *), AppleSpeechSupport.isAvailable {
                _ = try await AppleSpeechAssetInstaller.ensureInstalled(progress: progress)
            } else {
                progress(1)
            }
            return
        }

        let modelsRootDirectory = try modelsRootDirectoryURL()
        let stagingContainer = try makeStagingContainer(in: modelsRootDirectory, for: entry)
        defer {
            if FileManager.default.fileExists(atPath: stagingContainer.path) {
                try? FileManager.default.removeItem(at: stagingContainer)
            }
        }

        let stagedModelDirectory = stagingContainer.appendingPathComponent(entry.directoryName, isDirectory: true)

        switch entry.downloadSource {
        case let .archive(url):
            let downloader = DownloadDelegate(
                progress: progress,
                fallbackExpectedSizeBytes: entry.estimatedSizeBytes,
                temporaryFileBasename: entry.directoryName
            )
            let session = URLSession(configuration: urlSessionConfiguration, delegate: downloader, delegateQueue: nil)
            defer {
                session.finishTasksAndInvalidate()
            }

            let (archiveURL, response) = try await downloader.download(from: url, using: session)
            defer {
                if FileManager.default.fileExists(atPath: archiveURL.path) {
                    try? FileManager.default.removeItem(at: archiveURL)
                }
            }

            guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
                throw ModelError.invalidResponse
            }

            try Task.checkCancellation()
            try extract(archive: archiveURL, into: stagingContainer)
            try Task.checkCancellation()
        case let .remoteFiles(files):
            try await downloadRemoteFiles(files, into: stagedModelDirectory, progress: progress)
        case .systemManaged:
            // Unreachable: system-managed entries return early above. Kept for exhaustiveness.
            return
        }

        try Task.checkCancellation()
        try Self.validateInstall(entry, at: stagedModelDirectory)
        let liveModelDirectory = modelsRootDirectory.appendingPathComponent(entry.directoryName, isDirectory: true)
        try Task.checkCancellation()
        try Self.replaceInstalledModel(at: liveModelDirectory, with: stagedModelDirectory)
        progress(1)
    }

    func expectedDownloadSizeBytes(for modelID: ASRModelID) -> Int64 {
        ASRModelCatalog.entry(for: modelID).estimatedSizeBytes
    }

    func installedByteCount(for modelID: ASRModelID) -> Int64 {
        if catalogEntry(for: modelID).isSystemManaged {
            return 0
        }
        guard let directoryURL = try? modelDirectoryURL(for: modelID),
              let enumerator = FileManager.default.enumerator(
                  at: directoryURL,
                  includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                  options: [.skipsHiddenFiles]
              ) else {
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

    func deleteModel(_ modelID: ASRModelID) throws {
        if catalogEntry(for: modelID).isSystemManaged {
            // System-managed models are owned by the OS and cannot be deleted by us.
            // The UI hides the delete action for these; this guard keeps callers safe.
            return
        }
        let modelDirectory = try modelDirectoryURL(for: modelID)
        if FileManager.default.fileExists(atPath: modelDirectory.path) {
            try FileManager.default.removeItem(at: modelDirectory)
        }
    }

    private func installedEntry(for modelID: ASRModelID) throws -> ASRModelCatalogEntry {
        let entry = catalogEntry(for: modelID)
        return entry
    }

    private func catalogEntry(for modelID: ASRModelID) -> ASRModelCatalogEntry {
        ASRModelCatalog.entry(for: modelID)
    }

    private func makeStagingContainer(in modelsRootDirectory: URL, for entry: ASRModelCatalogEntry) throws -> URL {
        let stagingContainer = modelsRootDirectory
            .appendingPathComponent(".\(entry.directoryName)-staging-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingContainer, withIntermediateDirectories: true)
        return stagingContainer
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

    func downloadRemoteFiles(
        _ files: [ASRModelRemoteFile],
        into modelDirectory: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)

        let totalExpectedBytes = files.reduce(Int64(0)) { partial, file in
            partial + (file.expectedSizeBytes ?? 0)
        }
        var completedBytes: Int64 = 0

        for (index, file) in files.enumerated() {
            try Task.checkCancellation()
            let fallbackBytes = file.expectedSizeBytes ?? max(1, totalExpectedBytes / Int64(max(files.count, 1)))
            let completedBytesBeforeFile = completedBytes
            let downloader = DownloadDelegate(
                progress: { value in
                    let expectedBytes = max(fallbackBytes, 1)
                    let aggregateProgress: Double
                    if totalExpectedBytes > 0 {
                        aggregateProgress = min(
                            max(
                                Double(completedBytesBeforeFile) / Double(totalExpectedBytes) +
                                    (value * Double(expectedBytes) / Double(totalExpectedBytes)),
                                0
                            ),
                            1
                        )
                    } else {
                        aggregateProgress = (Double(index) + value) / Double(max(files.count, 1))
                    }
                    progress(aggregateProgress)
                },
                fallbackExpectedSizeBytes: fallbackBytes,
                temporaryFileBasename: "\(modelDirectory.lastPathComponent)-\(index)"
            )
            let session = URLSession(configuration: urlSessionConfiguration, delegate: downloader, delegateQueue: nil)
            defer {
                session.finishTasksAndInvalidate()
            }

            let (downloadedURL, response) = try await downloader.download(from: file.remoteURL, using: session)
            defer {
                if FileManager.default.fileExists(atPath: downloadedURL.path) {
                    try? FileManager.default.removeItem(at: downloadedURL)
                }
            }

            guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
                throw ModelError.invalidResponse
            }
            if let expected = file.sha256 {
                guard try Self.sha256Hex(of: downloadedURL) == expected.lowercased() else {
                    throw ModelError.checksumMismatch(file.destinationRelativePath)
                }
            }
            try Task.checkCancellation()

            let destinationURL = modelDirectory.appendingPathComponent(file.destinationRelativePath)
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: downloadedURL, to: destinationURL)
            completedBytes += fallbackBytes
        }
    }

    /// Streams the file through SHA-256 in 4 MB reads; model files run to gigabytes.
    static func sha256Hex(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func validateInstall(_ entry: ASRModelCatalogEntry, at modelDirectory: URL) throws {
        let missingPaths = entry.manifest.requiredRelativePaths.filter {
            !FileManager.default.fileExists(atPath: modelDirectory.appendingPathComponent($0).path)
        }

        guard missingPaths.isEmpty else {
            throw ModelError.extractFailed("missing required files: \(missingPaths.joined(separator: ", "))")
        }
    }

    static func replaceInstalledModel(at liveModelDirectory: URL, with stagedModelDirectory: URL) throws {
        let fileManager = FileManager.default
        let backupDirectory = liveModelDirectory
            .deletingLastPathComponent()
            .appendingPathComponent(".\(liveModelDirectory.lastPathComponent)-backup-\(UUID().uuidString)", isDirectory: true)
        let hadExistingInstall = fileManager.fileExists(atPath: liveModelDirectory.path)

        do {
            if hadExistingInstall {
                try fileManager.moveItem(at: liveModelDirectory, to: backupDirectory)
            }

            try fileManager.moveItem(at: stagedModelDirectory, to: liveModelDirectory)

            if hadExistingInstall, fileManager.fileExists(atPath: backupDirectory.path) {
                try? fileManager.removeItem(at: backupDirectory)
            }
        } catch {
            if hadExistingInstall,
               !fileManager.fileExists(atPath: liveModelDirectory.path),
               fileManager.fileExists(atPath: backupDirectory.path) {
                try fileManager.moveItem(at: backupDirectory, to: liveModelDirectory)
            }

            throw error
        }
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progressBlock: @Sendable (Double) -> Void
    private let fallbackExpectedSizeBytes: Int64
    private let temporaryFileBasename: String
    private var continuation: CheckedContinuation<(URL, URLResponse), Error>?
    private var downloadedFileURL: URL?
    private var downloadResponse: URLResponse?
    private var hasResumed = false
    /// Guarded by `taskLock`: the cancellation handler runs on an arbitrary
    /// thread while delegate callbacks land on the session's queue.
    private let taskLock = NSLock()
    private var activeTask: URLSessionDownloadTask?

    init(
        progress: @escaping @Sendable (Double) -> Void,
        fallbackExpectedSizeBytes: Int64,
        temporaryFileBasename: String
    ) {
        progressBlock = progress
        self.fallbackExpectedSizeBytes = fallbackExpectedSizeBytes
        self.temporaryFileBasename = temporaryFileBasename
    }

    func download(from url: URL, using session: URLSession) async throws -> (URL, URLResponse) {
        // Cooperative cancellation: cancelling the surrounding Task cancels the
        // URLSession task, which completes with NSURLErrorCancelled and resumes
        // the continuation with that error.
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let task = session.downloadTask(with: url)
                self.taskLock.lock()
                self.activeTask = task
                self.taskLock.unlock()

                if Task.isCancelled {
                    task.cancel()
                } else {
                    task.resume()
                }
            }
        }, onCancel: {
            taskLock.lock()
            let task = activeTask
            taskLock.unlock()
            task?.cancel()
        })
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
            let fileManager = FileManager.default
            let persistedURL = fileManager.temporaryDirectory
                .appendingPathComponent("\(temporaryFileBasename)-\(UUID().uuidString)", isDirectory: false)
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
