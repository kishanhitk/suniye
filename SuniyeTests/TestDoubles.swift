import Foundation
@testable import Suniye

final class TestLLMSettingsStore: LLMSettingsStoreProtocol {
    private var value = LLMSettings()

    var latest: LLMSettings {
        value
    }

    func load() -> LLMSettings {
        value
    }

    func save(_ settings: LLMSettings) {
        value = settings
    }
}

final class TestGeneralSettingsStore: GeneralSettingsStoreProtocol {
    private var value: GeneralSettings

    init(value: GeneralSettings = GeneralSettings()) {
        self.value = value
    }

    var latest: GeneralSettings {
        value
    }

    func load() -> GeneralSettings {
        value
    }

    func save(_ settings: GeneralSettings) {
        value = settings
    }
}

final class SpyTextInsertionService: TextInsertionServiceProtocol {
    private(set) var insertedTexts: [String] = []
    private(set) var submitCallCount = 0

    func insertText(_ text: String) throws {
        insertedTexts.append(text)
    }

    func submitActiveInput() throws {
        submitCallCount += 1
    }
}

final class TestHistoryStore: HistoryStoreProtocol {
    var value: [RecentResult] = []

    func load() -> [RecentResult] {
        value
    }

    func save(_ results: [RecentResult]) {
        value = results
    }
}

final class TestKeychainService: KeychainServiceProtocol {
    private var stored: String?

    init(value: String?) {
        stored = value
    }

    func setLLMKey(_ key: String) throws {
        stored = key
    }

    func hasLLMKey() -> Bool {
        stored?.isEmpty == false
    }

    func getLLMKey() throws -> String? {
        stored
    }

    func deleteLLMKey() throws {
        stored = nil
    }
}

final class StubUpdateService: UpdateServiceProtocol {
    private(set) var checkCallCount = 0
    var checkResult: Result<UpdateCheckResult, Error>
    var downloadResult: Result<URL, Error> = .failure(UpdateError.network("not configured"))

    init(checkResult: Result<UpdateCheckResult, Error>) {
        self.checkResult = checkResult
    }

    func checkForUpdate(currentVersion: AppVersion) async throws -> UpdateCheckResult {
        checkCallCount += 1
        return try checkResult.get()
    }

    func downloadAndVerify(release: UpdateRelease) async throws -> URL {
        try downloadResult.get()
    }
}

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

    func installedModels() -> [ASRModelID] {
        catalog.map(\.id).filter { installedModelIDs.contains($0) }
    }

    func makeRecognizerConfig(for modelID: ASRModelID) throws -> RecognizerConfig {
        recognizerConfigs[modelID] ?? recognizerConfigs[.parakeetV3]!
    }

    func downloadAndExtractModel(_ modelID: ASRModelID, progress: @escaping @Sendable (Double) -> Void) async throws {
        progress(1)
        try downloadResult.get()
        installedModelIDs.insert(modelID)
        lastDownloadedModelID = modelID
    }

    func expectedDownloadSizeBytes(for modelID: ASRModelID) -> Int64 {
        ASRModelCatalog.entry(for: modelID).estimatedSizeBytes
    }

    func installedByteCount(for modelID: ASRModelID) -> Int64 {
        installedByteCounts[modelID] ?? 0
    }

    func deleteModel(_ modelID: ASRModelID) throws {
        deleteCallCount += 1
        lastDeletedModelID = modelID
        installedModelIDs.remove(modelID)
    }
}

final class StubTranscriptionService: TranscriptionServiceProtocol {
    var transcribeResult: Result<String, Error> = .success("")
    var loadModelResult: Result<Void, Error> = .success(())
    var unloadCallCount = 0
    var loadCallCount = 0
    var loadedConfigs: [RecognizerConfig] = []

    func loadModel(config: RecognizerConfig) async throws {
        loadCallCount += 1
        loadedConfigs.append(config)
        try loadModelResult.get()
    }

    func transcribe(samples: [Float], sampleRate: Int) async throws -> String {
        try transcribeResult.get()
    }

    func unloadModel() async {
        unloadCallCount += 1
    }
}

final class StubAudioCaptureService: AudioCaptureServiceProtocol {
    var onLevelsUpdate: (([Float]) -> Void)?
    var startCaptureCallCount = 0
    var lastPreferredInputDeviceID: String?
    var stopCaptureResult = CapturedAudio(samples: [], sampleRate: 16_000)
    var availableDevices: [AudioInputDevice] = []
    var startCaptureError: Error?

    func startCapture(preferredInputDeviceID: String?, echoCancellationEnabled: Bool) throws {
        startCaptureCallCount += 1
        lastPreferredInputDeviceID = preferredInputDeviceID
        if let startCaptureError {
            throw startCaptureError
        }
    }

    func stopCapture() -> CapturedAudio {
        stopCaptureResult
    }

    func availableInputDevices() -> [AudioInputDevice] {
        availableDevices
    }
}

final class StubHotkeyService: HotkeyServiceProtocol {
    var onHotkeyDown: (() -> Void)?
    var onHotkeyUp: (() -> Void)?
    private(set) var startMonitoringCallCount = 0
    private(set) var lastConfiguration: HotkeyConfiguration?

    func startMonitoring(configuration: HotkeyConfiguration) {
        startMonitoringCallCount += 1
        lastConfiguration = configuration
    }

    func stopMonitoring() {}
}

final class StubLaunchAtLoginService: LaunchAtLoginServiceProtocol {
    var status: LaunchAtLoginStatus = .disabled
    var setEnabledError: Error?

    func currentStatus() -> LaunchAtLoginStatus {
        status
    }

    func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginStatus {
        if let setEnabledError {
            throw setEnabledError
        }
        status = enabled ? .enabled : .disabled
        return status
    }
}

struct FakeError: LocalizedError, Equatable {
    let message: String

    var errorDescription: String? {
        message
    }
}

@MainActor
func makeTestAppState(
    modelManager: ModelManagerProtocol = StubModelManager(),
    transcriptionService: TranscriptionServiceProtocol = StubTranscriptionService(),
    audioCaptureService: AudioCaptureServiceProtocol = StubAudioCaptureService(),
    textInsertionService: TextInsertionServiceProtocol = SpyTextInsertionService(),
    hotkeyService: HotkeyServiceProtocol = StubHotkeyService(),
    llmPostProcessor: LLMPostProcessor = NoopLLMPostProcessor(),
    llmSettingsStore: LLMSettingsStoreProtocol = TestLLMSettingsStore(),
    generalSettingsStore: GeneralSettingsStoreProtocol = TestGeneralSettingsStore(),
    historyStore: HistoryStoreProtocol = TestHistoryStore(),
    keychainService: KeychainServiceProtocol = TestKeychainService(value: nil),
    updateService: UpdateServiceProtocol = StubUpdateService(checkResult: .success(.upToDate)),
    launchAtLoginService: LaunchAtLoginServiceProtocol = StubLaunchAtLoginService(),
    currentAppVersionProvider: @escaping () -> AppVersion? = { AppVersion(marketing: SemVer(rawValue: "0.0.1")!, build: 1) },
    nowProvider: @escaping () -> Date = Date.init,
    fileOpener: @escaping (URL) -> Bool = { _ in true },
    startServices: Bool = false,
    llmE2EMode: LLME2EMode = .none
) -> AppState {
    AppState(
        modelManager: modelManager,
        transcriptionService: transcriptionService,
        audioCaptureService: audioCaptureService,
        textInsertionService: textInsertionService,
        hotkeyService: hotkeyService,
        llmPostProcessor: llmPostProcessor,
        llmSettingsStore: llmSettingsStore,
        generalSettingsStore: generalSettingsStore,
        historyStore: historyStore,
        keychainService: keychainService,
        updateService: updateService,
        launchAtLoginService: launchAtLoginService,
        currentAppVersionProvider: currentAppVersionProvider,
        nowProvider: nowProvider,
        fileOpener: fileOpener,
        startServices: startServices,
        llmE2EMode: llmE2EMode
    )
}

private final class NoopLLMPostProcessor: LLMPostProcessor {
    func polish(text: String, config: LLMConfig) async throws -> String {
        text
    }

    func testSetup(config: LLMConfig) async throws {}
}
