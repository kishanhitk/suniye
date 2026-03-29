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
    private var value = GeneralSettings()

    func load() -> GeneralSettings {
        value
    }

    func save(_ settings: GeneralSettings) {
        value = settings
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
    private let checkResult: Result<UpdateCheckResult, Error>
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
    var expectedDownloadSizeBytes: Int64 = 680_000_000
    var isReady = true
    var byteCount: Int64 = 631_000_000
    var deleteCallCount = 0
    var downloadResult: Result<Void, Error> = .success(())
    var recognizerConfig = RecognizerConfig(
        encoderPath: "/tmp/encoder.int8.onnx",
        decoderPath: "/tmp/decoder.int8.onnx",
        joinerPath: "/tmp/joiner.int8.onnx",
        tokensPath: "/tmp/tokens.txt",
        numThreads: 4
    )

    func modelDirectoryURL() throws -> URL {
        URL(fileURLWithPath: "/tmp/suniye-model", isDirectory: true)
    }

    func isModelReady() -> Bool {
        isReady
    }

    func makeRecognizerConfig() throws -> RecognizerConfig {
        recognizerConfig
    }

    func downloadAndExtractModel(progress: @escaping @Sendable (Double) -> Void) async throws {
        progress(1)
        try downloadResult.get()
        isReady = true
    }

    func installedByteCount() -> Int64 {
        byteCount
    }

    func deleteModel() throws {
        deleteCallCount += 1
        isReady = false
    }
}

final class StubTranscriptionService: TranscriptionServiceProtocol {
    var transcribeResult: Result<String, Error> = .success("")
    var unloadCallCount = 0
    var loadCallCount = 0

    func loadModel(config: RecognizerConfig) async throws {
        loadCallCount += 1
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
    hotkeyService: HotkeyServiceProtocol = StubHotkeyService(),
    llmPostProcessor: LLMPostProcessor = NoopLLMPostProcessor(),
    llmSettingsStore: LLMSettingsStoreProtocol = TestLLMSettingsStore(),
    generalSettingsStore: GeneralSettingsStoreProtocol = TestGeneralSettingsStore(),
    historyStore: HistoryStoreProtocol = TestHistoryStore(),
    keychainService: KeychainServiceProtocol = TestKeychainService(value: nil),
    updateService: UpdateServiceProtocol = StubUpdateService(checkResult: .success(.upToDate)),
    launchAtLoginService: LaunchAtLoginServiceProtocol = StubLaunchAtLoginService(),
    nowProvider: @escaping () -> Date = Date.init,
    fileOpener: @escaping (URL) -> Bool = { _ in true },
    startServices: Bool = false,
    llmE2EMode: LLME2EMode = .none
) -> AppState {
    AppState(
        modelManager: modelManager,
        transcriptionService: transcriptionService,
        audioCaptureService: audioCaptureService,
        hotkeyService: hotkeyService,
        llmPostProcessor: llmPostProcessor,
        llmSettingsStore: llmSettingsStore,
        generalSettingsStore: generalSettingsStore,
        historyStore: historyStore,
        keychainService: keychainService,
        updateService: updateService,
        launchAtLoginService: launchAtLoginService,
        currentAppVersionProvider: { AppVersion(marketing: SemVer(rawValue: "0.0.1")!, build: 1) },
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
}
