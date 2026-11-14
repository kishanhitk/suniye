import Foundation
@testable import Suniye

final class StubModelManager: ModelManagerProtocol {
    var catalog: [ASRModelCatalogEntry] = ASRModelCatalog.entries
    var fallbackOrder: [ASRModelID] = ASRModelCatalog.fallbackOrder
    var installedModelIDs: Set<ASRModelID> = [.parakeetV3]
    var installedByteCounts: [ASRModelID: Int64] = [
        .parakeetV3: 631_000_000,
        .parakeetV2English: 482_468_385,
        .moonshineBase: 285_000_000,
        .senseVoice: 240_000_000,
        .whisperTinyEnglish: 118_071_777,
        .whisperBaseEnglish: 208_576_005,
        .whisperSmallEnglish: 635_693_775,
        .whisperLargeV3Turbo: 563_790_207,
        .whisperDistilLargeV3: 529_350_808,
        .whisperLargeV3: 1_700_000_000
    ]
    var deleteCallCount = 0
    var lastDeletedModelID: ASRModelID?
    var lastDownloadedModelID: ASRModelID?
    var downloadResult: Result<Void, Error> = .success(())
    var installsModelAfterDownload = true
    /// When set, a download reports 10% and waits for the gate, then honors task cancellation.
    var downloadGate: AsyncGate?
    var deleteError: Error?
    /// What a fresh install's built-in model check reports.
    var systemDefaultCheck: SystemDefaultModelCheck = .unavailable(reason: .transcriberUnavailable, detail: "stub")
    private(set) var systemDefaultCheckCallCount = 0
    var recognizerConfigs: [ASRModelID: RecognizerConfig] = [
        .parakeetV3: RecognizerConfig(
            modelID: .parakeetV3,
            family: .nemoTransducer,
            tokensPath: "/tmp/parakeet/tokens.txt",
            numThreads: 4,
            encoderPath: "/tmp/parakeet/encoder.int8.onnx",
            decoderPath: "/tmp/parakeet/decoder.int8.onnx",
            joinerPath: "/tmp/parakeet/joiner.int8.onnx",
            modelType: "nemo_transducer"
        ),
        .parakeetV2English: RecognizerConfig(
            modelID: .parakeetV2English,
            family: .nemoTransducer,
            tokensPath: "/tmp/parakeet-v2/tokens.txt",
            numThreads: 4,
            encoderPath: "/tmp/parakeet-v2/encoder.int8.onnx",
            decoderPath: "/tmp/parakeet-v2/decoder.int8.onnx",
            joinerPath: "/tmp/parakeet-v2/joiner.int8.onnx",
            modelType: "nemo_transducer"
        ),
        .moonshineBase: RecognizerConfig(
            modelID: .moonshineBase,
            family: .moonshine,
            tokensPath: "/tmp/moonshine/tokens.txt",
            numThreads: 4,
            encoderPath: "/tmp/moonshine/encode.int8.onnx",
            preprocessorPath: "/tmp/moonshine/preprocess.onnx",
            uncachedDecoderPath: "/tmp/moonshine/uncached_decode.int8.onnx",
            cachedDecoderPath: "/tmp/moonshine/cached_decode.int8.onnx"
        ),
        .senseVoice: RecognizerConfig(
            modelID: .senseVoice,
            family: .senseVoice,
            tokensPath: "/tmp/sensevoice/tokens.txt",
            numThreads: 4,
            modelPath: "/tmp/sensevoice/model.int8.onnx",
            language: "auto",
            useInverseTextNormalization: true
        ),
        .whisperLargeV3: RecognizerConfig(
            modelID: .whisperLargeV3,
            family: .whisper,
            tokensPath: "/tmp/whisper/large-v3-tokens.txt",
            numThreads: 4,
            encoderPath: "/tmp/whisper/large-v3-encoder.int8.onnx",
            decoderPath: "/tmp/whisper/large-v3-decoder.int8.onnx"
        ),
        .whisperTinyEnglish: RecognizerConfig(
            modelID: .whisperTinyEnglish,
            family: .whisper,
            tokensPath: "/tmp/whisper-tiny/tiny.en-tokens.txt",
            numThreads: 4,
            encoderPath: "/tmp/whisper-tiny/tiny.en-encoder.int8.onnx",
            decoderPath: "/tmp/whisper-tiny/tiny.en-decoder.int8.onnx"
        ),
        .whisperBaseEnglish: RecognizerConfig(
            modelID: .whisperBaseEnglish,
            family: .whisper,
            tokensPath: "/tmp/whisper-base/base.en-tokens.txt",
            numThreads: 4,
            encoderPath: "/tmp/whisper-base/base.en-encoder.int8.onnx",
            decoderPath: "/tmp/whisper-base/base.en-decoder.int8.onnx"
        ),
        .whisperSmallEnglish: RecognizerConfig(
            modelID: .whisperSmallEnglish,
            family: .whisper,
            tokensPath: "/tmp/whisper-small/small.en-tokens.txt",
            numThreads: 4,
            encoderPath: "/tmp/whisper-small/small.en-encoder.int8.onnx",
            decoderPath: "/tmp/whisper-small/small.en-decoder.int8.onnx"
        ),
        .whisperLargeV3Turbo: RecognizerConfig(
            modelID: .whisperLargeV3Turbo,
            family: .whisper,
            tokensPath: "/tmp/whisper-turbo/turbo-tokens.txt",
            numThreads: 4,
            encoderPath: "/tmp/whisper-turbo/turbo-encoder.int8.onnx",
            decoderPath: "/tmp/whisper-turbo/turbo-decoder.int8.onnx"
        ),
        .whisperDistilLargeV3: RecognizerConfig(
            modelID: .whisperDistilLargeV3,
            family: .whisper,
            tokensPath: "/tmp/whisper-distil-large-v3/distil-large-v3-tokens.txt",
            numThreads: 4,
            encoderPath: "/tmp/whisper-distil-large-v3/distil-large-v3-encoder.int8.onnx",
            decoderPath: "/tmp/whisper-distil-large-v3/distil-large-v3-decoder.int8.onnx"
        )
    ]

    func modelsRootDirectoryURL() throws -> URL {
        URL(fileURLWithPath: "/tmp/suniye-models", isDirectory: true)
    }

    func modelDirectoryURL(for modelID: ASRModelID) throws -> URL {
        URL(fileURLWithPath: "/tmp/suniye-models/\(modelID.rawValue)", isDirectory: true)
    }

    func isInstalled(_ modelID: ASRModelID) -> Bool {
        installedModelIDs.contains(modelID)
    }

    /// Mirrors the real contract: system-managed models never count as installed files.
    func installedModels() -> [ASRModelID] {
        catalog.filter { !$0.isSystemManaged }.map(\.id).filter { installedModelIDs.contains($0) }
    }

    func systemDefaultModelCheck() async -> SystemDefaultModelCheck {
        systemDefaultCheckCallCount += 1
        return systemDefaultCheck
    }

    func makeRecognizerConfig(for modelID: ASRModelID) throws -> RecognizerConfig {
        recognizerConfigs[modelID] ?? recognizerConfigs[.parakeetV3]!
    }

    func downloadAndExtractModel(_ modelID: ASRModelID, progress: @escaping @Sendable (Double) -> Void) async throws {
        if let downloadGate {
            progress(0.1)
            await downloadGate.wait()
            try Task.checkCancellation()
        }
        progress(1)
        try downloadResult.get()
        if installsModelAfterDownload {
            installedModelIDs.insert(modelID)
        }
        lastDownloadedModelID = modelID
    }

    func expectedDownloadSizeBytes(for modelID: ASRModelID) -> Int64 {
        ASRModelCatalog.entry(for: modelID).estimatedSizeBytes
    }

    func installedByteCount(for modelID: ASRModelID) -> Int64 {
        installedByteCounts[modelID] ?? 0
    }

    func deleteModel(_ modelID: ASRModelID) throws {
        if let deleteError {
            throw deleteError
        }
        deleteCallCount += 1
        lastDeletedModelID = modelID
        installedModelIDs.remove(modelID)
    }
}

final class StubLocalLLMModelManager: LocalLLMModelManagerProtocol {
    var catalog: [LocalLLMModelCatalogEntry] = LocalLLMModelCatalog.entries
    var preferredModelID: LocalLLMModelID = LocalLLMModelCatalog.preferredModelID
    var isHardwareSupported = true
    var installedModelIDs: Set<LocalLLMModelID> = []
    var installedByteCounts: [LocalLLMModelID: Int64] = [
        LocalLLMModelCatalog.preferredModelID: LocalLLMModelCatalog.entry(for: LocalLLMModelCatalog.preferredModelID).expectedSizeBytes
    ]
    var downloadResult: Result<Void, Error> = .success(())
    var deleteCallCount = 0
    var downloadCallCount = 0
    var cancelCallCount = 0
    var lastDeletedModelID: LocalLLMModelID?
    var lastDownloadedModelID: LocalLLMModelID?
    var lastProgressHandler: (@Sendable (LocalLLMDownloadProgress) -> Void)?
    var progressValues: [LocalLLMDownloadProgress] = []
    var rootDirectory = URL(fileURLWithPath: "/tmp/suniye-llm", isDirectory: true)
    var onDownloadFinished: (() -> Void)?
    /// When set, a download reports 50% and waits for the gate before it finishes.
    var downloadGate: AsyncGate?
    var deleteError: Error?

    func modelsRootDirectoryURL() throws -> URL {
        rootDirectory
    }

    func modelFileURL(for modelID: LocalLLMModelID) throws -> URL {
        rootDirectory.appendingPathComponent(catalogEntry(for: modelID).filename)
    }

    func isInstalled(_ modelID: LocalLLMModelID) -> Bool {
        isHardwareSupported && installedModelIDs.contains(modelID)
    }

    func installedByteCount(for modelID: LocalLLMModelID) -> Int64 {
        isInstalled(modelID) ? (installedByteCounts[modelID] ?? 0) : 0
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

    func downloadModel(_ modelID: LocalLLMModelID, progress: @escaping @Sendable (LocalLLMDownloadProgress) -> Void) async throws {
        downloadCallCount += 1
        lastDownloadedModelID = modelID
        lastProgressHandler = progress
        let entry = catalogEntry(for: modelID)
        if let downloadGate {
            progress(LocalLLMDownloadProgress(fractionCompleted: 0.5, downloadedBytes: 500, expectedBytes: 1000))
            await downloadGate.wait()
        }
        let progressValue = LocalLLMDownloadProgress(
            fractionCompleted: 1,
            downloadedBytes: entry.expectedSizeBytes,
            expectedBytes: entry.expectedSizeBytes
        )
        progressValues.append(progressValue)
        progress(progressValue)
        try downloadResult.get()
        installedModelIDs.insert(modelID)
        onDownloadFinished?()
    }

    func cancelDownload() {
        cancelCallCount += 1
    }

    func deleteModel(_ modelID: LocalLLMModelID) throws {
        if let deleteError {
            throw deleteError
        }
        deleteCallCount += 1
        lastDeletedModelID = modelID
        installedModelIDs.remove(modelID)
    }

    private func catalogEntry(for modelID: LocalLLMModelID) -> LocalLLMModelCatalogEntry {
        catalog.first { $0.id == modelID } ?? LocalLLMModelCatalog.entry(for: modelID)
    }
}
