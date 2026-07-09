import Foundation
import SuniyeAnalytics
@testable import Suniye

/// Records analytics interactions for assertions in tests.
final class SpyAnalytics: Analytics, @unchecked Sendable {
    private(set) var trackedEvents: [AnalyticsEvent] = []
    private(set) var enabledStates: [Bool] = []
    private(set) var flushCount = 0
    private(set) var sessionEndCount = 0
    private(set) var started = false

    func track(_ event: AnalyticsEvent) { trackedEvents.append(event) }
    func setEnabled(_ enabled: Bool) { enabledStates.append(enabled) }
    func flush() async { flushCount += 1 }
    func start() { started = true }
    func stop() {}
    func recordSessionEnd(cleanExit: Bool) { sessionEndCount += 1 }
    func endSession(cleanExit: Bool) async { sessionEndCount += 1; flushCount += 1 }

    var trackedEventNames: [String] { trackedEvents.map(\.name) }
}

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
    var insertionContext: TextInsertionContext?
    var insertError: Error?
    var submitError: Error?
    var fieldValueProvider: (() -> String?)?

    func captureInsertionContext() -> TextInsertionContext? {
        insertionContext
    }

    func makeFocusedFieldValueProvider() -> (() -> String?)? {
        fieldValueProvider
    }

    func insertText(_ text: String) throws {
        if let insertError {
            throw insertError
        }
        insertedTexts.append(text)
    }

    func submitActiveInput() throws {
        if let submitError {
            throw submitError
        }
        submitCallCount += 1
    }
}

final class SpySoundFeedbackService: SoundFeedbackServiceProtocol {
    private(set) var playedEvents: [SoundFeedbackEvent] = []

    func play(_ event: SoundFeedbackEvent) {
        playedEvents.append(event)
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

@MainActor
final class StubAppUpdateController: AppUpdateControllerProtocol {
    var canCheckForUpdates = false
    var automaticallyChecksForUpdates = false
    var updateChannel: UpdateChannel = .stable
    var onStateChange: (() -> Void)?

    private(set) var startCallCount = 0
    private(set) var checkForUpdatesCallCount = 0

    func start() {
        startCallCount += 1
        canCheckForUpdates = true
        onStateChange?()
    }

    func checkForUpdates() {
        checkForUpdatesCallCount += 1
    }

    func notifyStateChanged() {
        onStateChange?()
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
        deleteCallCount += 1
        lastDeletedModelID = modelID
        installedModelIDs.remove(modelID)
    }

    private func catalogEntry(for modelID: LocalLLMModelID) -> LocalLLMModelCatalogEntry {
        catalog.first { $0.id == modelID } ?? LocalLLMModelCatalog.entry(for: modelID)
    }
}

/// MainActor-isolated so overlapping decodes in tests (e.g. a gated partial plus
/// a concurrent final) serialize their mutations instead of racing on the
/// cooperative pool. All consuming tests already run on the main actor.
@MainActor
final class StubTranscriptionService: TranscriptionServiceProtocol {
    var transcribeResult: Result<String, Error> = .success("")
    /// Consumed in order before falling back to `transcribeResult`.
    var scriptedTranscribeResults: [Result<String, Error>] = []
    var loadModelResult: Result<Void, Error> = .success(())
    var loadModelErrorsByModelID: [ASRModelID: Error] = [:]
    var unloadCallCount = 0
    var loadCallCount = 0
    var transcribeCallCount = 0
    var transcribePurposes: [TranscriptionPurpose] = []
    var loadedConfigs: [RecognizerConfig] = []
    var onTranscribe: (() -> Void)?
    /// Awaited after the scripted result is claimed; receives the 1-based call number.
    var onTranscribeAwait: ((Int) async -> Void)?

    /// Nonisolated so it can serve as a default argument (evaluated outside the main actor).
    nonisolated init() {}

    func loadModel(config: RecognizerConfig) async throws {
        loadCallCount += 1
        loadedConfigs.append(config)
        if let error = loadModelErrorsByModelID[config.modelID] {
            throw error
        }
        try loadModelResult.get()
    }

    func transcribe(samples: [Float], sampleRate: Int, purpose: TranscriptionPurpose) async throws -> String {
        transcribeCallCount += 1
        transcribePurposes.append(purpose)
        let callNumber = transcribeCallCount
        onTranscribe?()
        let result = scriptedTranscribeResults.isEmpty
            ? transcribeResult
            : scriptedTranscribeResults.removeFirst()
        if let onTranscribeAwait {
            await onTranscribeAwait(callNumber)
        }
        return try result.get()
    }

    func unloadModel() async {
        unloadCallCount += 1
    }
}

final class StubAudioCaptureService: AudioCaptureServiceProtocol {
    var onEvent: ((AudioCaptureEvent) -> Void)?
    var startCaptureCallCount = 0
    var stopCaptureCallCount = 0
    var cancelCaptureCallCount = 0
    var handleSystemSleepCallCount = 0
    var handleSystemWakeCallCount = 0
    var lastPreferredInputDeviceID: String?
    var lastEchoCancellationEnabled: Bool?
    var lastStartedSessionID: UUID?
    var lastStoppedSessionID: UUID?
    var lastCanceledSessionID: UUID?
    var startCaptureDelayNanoseconds: UInt64 = 0
    var stopCaptureResult = CapturedAudio(samples: [], sampleRate: 16_000)
    var snapshotCallCount = 0
    var lastSnapshotMaxDurationSeconds: Double?
    var snapshotSamplesResult: [Float]? = Array(repeating: 0.2, count: 1_600)
    var availableDevices: [AudioInputDevice] = []
    var startCaptureError: Error?
    var routeSnapshotError: Error?
    var suspendsStartCapture = false
    var onStartCapture: ((UUID) -> Void)?
    var onStopCapture: ((UUID) -> Void)?
    var onCancelCapture: ((UUID) -> Void)?
    var onSystemSleep: (() -> Void)?
    var onSystemWake: (() -> Void)?
    private var startCaptureContinuation: CheckedContinuation<Void, Never>?
    var route = AudioRouteSnapshot(
        preferredInputDeviceID: nil,
        effectiveInputDeviceID: "default-device",
        effectiveInputName: "System Microphone",
        inputTransport: .builtIn,
        outputTransport: .builtIn,
        inputSampleRate: 16_000,
        inputChannelCount: 1,
        requestedEchoCancellation: false,
        effectiveEchoCancellation: false,
        backend: .inputOnlyHAL,
        fallbackReason: nil
    )

    func startCapture(
        sessionID: UUID,
        preferredInputDeviceID: String?,
        echoCancellationEnabled: Bool
    ) async throws -> AudioCaptureSession {
        startCaptureCallCount += 1
        lastStartedSessionID = sessionID
        lastPreferredInputDeviceID = preferredInputDeviceID
        lastEchoCancellationEnabled = echoCancellationEnabled
        onStartCapture?(sessionID)
        if suspendsStartCapture {
            await withCheckedContinuation { continuation in
                startCaptureContinuation = continuation
            }
        }
        if startCaptureDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: startCaptureDelayNanoseconds)
        }
        if let startCaptureError {
            throw startCaptureError
        }
        return AudioCaptureSession(id: sessionID, route: route)
    }

    func stopCapture(sessionID: UUID) async -> CapturedAudio {
        stopCaptureCallCount += 1
        lastStoppedSessionID = sessionID
        onStopCapture?(sessionID)
        return stopCaptureResult
    }

    func snapshotSamples(sessionID: UUID, maxDurationSeconds: Double) async -> AudioSampleSnapshot? {
        snapshotCallCount += 1
        lastSnapshotMaxDurationSeconds = maxDurationSeconds
        guard let snapshotSamplesResult else {
            return nil
        }
        return AudioSampleSnapshot(
            samples: snapshotSamplesResult,
            sampleRate: route.inputSampleRate
        )
    }

    func cancelCapture(sessionID: UUID, reason: AudioCaptureInterruption?) async {
        cancelCaptureCallCount += 1
        lastCanceledSessionID = sessionID
        onCancelCapture?(sessionID)
    }

    func availableInputDevices() -> [AudioInputDevice] {
        availableDevices
    }

    func routeSnapshot(preferredInputDeviceID: String?, echoCancellationEnabled: Bool) throws -> AudioRouteSnapshot {
        if let routeSnapshotError {
            throw routeSnapshotError
        }
        return route
    }

    func handleSystemSleep() async {
        handleSystemSleepCallCount += 1
        onSystemSleep?()
    }

    func handleSystemWake() {
        handleSystemWakeCallCount += 1
        onSystemWake?()
    }

    func resumeStartCapture() {
        startCaptureContinuation?.resume()
        startCaptureContinuation = nil
    }
}

func makeValidCapturedAudio(sampleRate: Int = 16_000) -> CapturedAudio {
    CapturedAudio(
        samples: Array(repeating: 0.2, count: sampleRate / 10),
        sampleRate: sampleRate
    )
}

final class StubHotkeyService: HotkeyServiceProtocol {
    var onHotkeyDown: (() -> Void)?
    var onHotkeyUp: (() -> Void)?
    var onEditModeHotkeyDown: (() -> Void)?
    var onEditModeHotkeyUp: (() -> Void)?
    var onCommandHotkeyDown: (() -> Void)?
    var onCommandHotkeyUp: (() -> Void)?
    private(set) var startMonitoringCallCount = 0
    private(set) var lastConfiguration: HotkeyConfiguration?
    private(set) var lastEditModeConfiguration: HotkeyConfiguration?
    private(set) var lastCommandConfiguration: HotkeyConfiguration?

    func startMonitoring(configuration: HotkeyConfiguration, editModeConfiguration: HotkeyConfiguration?, commandConfiguration: HotkeyConfiguration?) {
        startMonitoringCallCount += 1
        lastConfiguration = configuration
        lastEditModeConfiguration = editModeConfiguration
        lastCommandConfiguration = commandConfiguration
    }

    func stopMonitoring() {}
}

@MainActor
final class StubEditModeSelectionProvider: EditModeSelectionProviding {
    var selection: String?
    private(set) var captureCallCount = 0

    init(selection: String? = nil) {
        self.selection = selection
    }

    func captureSelectedText() async -> String? {
        captureCallCount += 1
        return selection
    }
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

/// One-shot gate for holding an async stub call open until the test releases it.
final class AsyncGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if isOpen {
                lock.unlock()
                continuation.resume()
                return
            }
            waiters.append(continuation)
            lock.unlock()
        }
    }

    func open() {
        lock.lock()
        let pending = waiters
        waiters = []
        isOpen = true
        lock.unlock()
        pending.forEach { $0.resume() }
    }
}

struct FakeError: LocalizedError, Equatable {
    let message: String

    var errorDescription: String? {
        message
    }
}

@MainActor
final class SpyEditLearningService: EditLearningServiceProtocol {
    enum Event: Equatable {
        case finalize
        case begin(insertedText: String)
    }

    var onLearnedTerms: (([String]) -> Void)?
    var onEditRate: ((Int) -> Void)?
    private(set) var events: [Event] = []
    private(set) var beganSessions: [EditLearningSession] = []

    func beginTracking(_ session: EditLearningSession) {
        events.append(.begin(insertedText: session.insertedText))
        beganSessions.append(session)
    }

    func finalizeActiveSession() {
        events.append(.finalize)
    }
}

@MainActor
final class SpyLearningToastPresenter: LearningToastPresenting {
    private(set) var shownTermBatches: [[String]] = []
    private(set) var lastUndo: (() -> Void)?

    func showLearnedTerms(_ terms: [String], onUndo: @escaping () -> Void) {
        shownTermBatches.append(terms)
        lastUndo = onUndo
    }
}

@MainActor
final class SpyAccessibilityOnboarding: AccessibilityOnboardingPresenting {
    private(set) var presentCallCount = 0
    private(set) var dismissCallCount = 0
    private(set) var isPresenting = false
    private var pendingOnGranted: (() -> Void)?

    func present(onGranted: @escaping () -> Void) {
        presentCallCount += 1
        isPresenting = true
        pendingOnGranted = onGranted
    }

    func dismiss() {
        dismissCallCount += 1
        isPresenting = false
        pendingOnGranted = nil
    }

    /// Simulate the user dragging the app in and the poller detecting the grant.
    func simulateGrant() {
        isPresenting = false
        let onGranted = pendingOnGranted
        pendingOnGranted = nil
        onGranted?()
    }
}

@MainActor
func makeTestAppState(
    modelManager: ModelManagerProtocol = StubModelManager(),
    transcriptionService: TranscriptionServiceProtocol = StubTranscriptionService(),
    audioCaptureService: AudioCaptureServiceProtocol = StubAudioCaptureService(),
    textInsertionService: TextInsertionServiceProtocol = SpyTextInsertionService(),
    editModeSelectionProvider: EditModeSelectionProviding? = nil,
    hotkeyService: HotkeyServiceProtocol = StubHotkeyService(),
    soundFeedbackService: SoundFeedbackServiceProtocol = SpySoundFeedbackService(),
    partialTranscriptionScheduler: PartialTranscriptionScheduler? = nil,
    llmPostProcessor: LLMPostProcessor = NoopLLMPostProcessor(),
    appleMagicFormatPostProcessor: AppleMagicFormatPostProcessor = NoopAppleMagicFormatPostProcessor(),
    localGemmaMagicFormatPostProcessor: LocalGemmaMagicFormatPostProcessor = NoopLocalGemmaMagicFormatPostProcessor(),
    localLLMModelManager: LocalLLMModelManagerProtocol = StubLocalLLMModelManager(),
    llmSettingsStore: LLMSettingsStoreProtocol = TestLLMSettingsStore(),
    magicFormatPromptFileStore: MagicFormatPromptFileStoreProtocol = MagicFormatPromptFileStore(
        promptsDirectoryURL: FileManager.default.temporaryDirectory.appendingPathComponent("suniye-prompt-tests-\(UUID().uuidString)", isDirectory: true)
    ),
    generalSettingsStore: GeneralSettingsStoreProtocol = TestGeneralSettingsStore(),
    historyStore: HistoryStoreProtocol = TestHistoryStore(),
    keychainService: KeychainServiceProtocol = TestKeychainService(value: nil),
    appUpdateController: AppUpdateControllerProtocol? = nil,
    launchAtLoginService: LaunchAtLoginServiceProtocol = StubLaunchAtLoginService(),
    diagnosticBundleService: DiagnosticBundleServiceProtocol = StubDiagnosticBundleService(),
    issueReportUploadService: IssueReportUploadServiceProtocol = StubIssueReportUploadService(),
    analytics: Analytics = SpyAnalytics(),
    editLearningService: EditLearningServiceProtocol? = nil,
    learningToastPresenter: LearningToastPresenting? = nil,
    currentAppVersionProvider: @escaping () -> AppVersion? = { AppVersion(marketing: SemVer(rawValue: "0.0.1")!, build: 1) },
    nowProvider: @escaping () -> Date = Date.init,
    frontmostAppBundleIDProvider: @escaping () -> String? = { nil },
    fileOpener: @escaping (URL) -> Bool = { _ in true },
    accessibilityOnboarding: AccessibilityOnboardingPresenting? = nil,
    issueReportDiagnosticsDestinationPicker: @escaping @MainActor (String) -> URL? = { _ in nil },
    temporaryFileCleanupScheduler: @escaping (URL) -> Void = { _ in },
    magicFormatSlowWarningDelaySeconds: TimeInterval = 5,
    startServices: Bool = false,
    llmE2EMode: LLME2EMode = .none
) -> AppState {
    AppState(
        modelManager: modelManager,
        transcriptionService: transcriptionService,
        audioCaptureService: audioCaptureService,
        textInsertionService: textInsertionService,
        editModeSelectionProvider: editModeSelectionProvider ?? StubEditModeSelectionProvider(),
        hotkeyService: hotkeyService,
        soundFeedbackService: soundFeedbackService,
        partialTranscriptionScheduler: partialTranscriptionScheduler,
        llmPostProcessor: llmPostProcessor,
        appleMagicFormatPostProcessor: appleMagicFormatPostProcessor,
        localGemmaMagicFormatPostProcessor: localGemmaMagicFormatPostProcessor,
        localLLMModelManager: localLLMModelManager,
        llmSettingsStore: llmSettingsStore,
        magicFormatPromptFileStore: magicFormatPromptFileStore,
        generalSettingsStore: generalSettingsStore,
        historyStore: historyStore,
        keychainService: keychainService,
        appUpdateController: appUpdateController ?? StubAppUpdateController(),
        launchAtLoginService: launchAtLoginService,
        diagnosticBundleService: diagnosticBundleService,
        issueReportUploadService: issueReportUploadService,
        analytics: analytics,
        editLearningService: editLearningService ?? SpyEditLearningService(),
        learningToastPresenter: learningToastPresenter ?? SpyLearningToastPresenter(),
        currentAppVersionProvider: currentAppVersionProvider,
        nowProvider: nowProvider,
        frontmostAppBundleIDProvider: frontmostAppBundleIDProvider,
        fileOpener: fileOpener,
        accessibilityOnboarding: accessibilityOnboarding ?? SpyAccessibilityOnboarding(),
        issueReportDiagnosticsDestinationPicker: issueReportDiagnosticsDestinationPicker,
        temporaryFileCleanupScheduler: temporaryFileCleanupScheduler,
        magicFormatSlowWarningDelaySeconds: magicFormatSlowWarningDelaySeconds,
        startServices: startServices,
        llmE2EMode: llmE2EMode
    )
}

private final class NoopLLMPostProcessor: LLMPostProcessor {
    func polish(text: String, config: LLMConfig) async throws -> String {
        text
    }

    func generate(instructions: String, userText: String, config: LLMConfig) async throws -> String {
        userText
    }

    func testSetup(config: LLMConfig) async throws {}
}

final class NoopAppleMagicFormatPostProcessor: AppleMagicFormatPostProcessor {
    var availability: AppleFoundationModelsAvailability

    init(availability: AppleFoundationModelsAvailability = .unsupportedSDKOrRuntime) {
        self.availability = availability
    }

    func polish(text: String, config: AppleMagicFormatConfig) async throws -> String {
        text
    }

    func generate(instructions: String, userText: String, config: AppleMagicFormatConfig) async throws -> String {
        userText
    }

    func testSetup(config: AppleMagicFormatConfig) async throws {}
}

final class NoopLocalGemmaMagicFormatPostProcessor: LocalGemmaMagicFormatPostProcessor {
    var availability: LocalGemmaAvailability

    init(availability: LocalGemmaAvailability = .modelNotInstalled) {
        self.availability = availability
    }

    func polish(text: String, config: LocalGemmaMagicFormatConfig) async throws -> String {
        text
    }

    func generate(instructions: String, userText: String, config: LocalGemmaMagicFormatConfig) async throws -> String {
        userText
    }

    func testSetup(config: LocalGemmaMagicFormatConfig) async throws {}
}

final class StubDiagnosticBundleService: DiagnosticBundleServiceProtocol {
    var result: Result<URL, Error>
    private(set) var requests: [DiagnosticBundleRequest] = []

    init(result: Result<URL, Error> = .success(FileManager.default.temporaryDirectory.appendingPathComponent("diagnostics.zip"))) {
        self.result = result
    }

    func makeBundle(request: DiagnosticBundleRequest) async throws -> URL {
        requests.append(request)
        return try result.get()
    }
}

final class StubIssueReportUploadService: IssueReportUploadServiceProtocol {
    var result: Result<IssueReportSubmissionResponse, Error>
    private(set) var submissions: [(payload: IssueReportPayload, diagnosticsURL: URL?)] = []

    init(
        result: Result<IssueReportSubmissionResponse, Error> = .success(
            IssueReportSubmissionResponse(
                reportId: "suniye-test-report",
                issueId: "issue-id",
                issueIdentifier: "KIS-128",
                issueUrl: URL(string: "https://linear.app/kishan/issue/KIS-128/report")
            )
        )
    ) {
        self.result = result
    }

    func submit(payload: IssueReportPayload, diagnosticsURL: URL?) async throws -> IssueReportSubmissionResponse {
        submissions.append((payload, diagnosticsURL))
        return try result.get()
    }
}

/// A CommandActing surface for tool tests — records click/focus/type and returns
/// the native-style output strings, no live AX or browser.
@MainActor
final class FakeCommandSurface: CommandActing {
    var activeKind: CommandSurfaceKind = .native
    var screen = "Frontmost app: Finder"
    private(set) var clicks: [String] = []
    private(set) var focuses: [String] = []
    private(set) var typed: [String] = []
    func readScreen() async -> String { screen }
    func click(id: String) async -> ToolResult { clicks.append(id); return ToolResult(output: "clicked \(id)", isTerminal: false) }
    func focus(id: String) async -> ToolResult { focuses.append(id); return ToolResult(output: "focused \(id)", isTerminal: false) }
    func typeText(_ text: String) async -> ToolResult { typed.append(text); return ToolResult(output: "typed \(text.count) chars", isTerminal: false) }
}
