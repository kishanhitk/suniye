import AVFoundation
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
    private(set) var attemptedTexts: [String] = []
    private(set) var insertedTexts: [String] = []
    private(set) var copiedTexts: [String] = []
    private(set) var submitCallCount = 0
    private(set) var warmTargetAppAccessibilityCallCount = 0
    var insertionContext: TextInsertionContext?
    var insertError: Error?
    var insertOutcome: InsertionOutcome = .intoFocusedElement
    var copyError: Error?
    var submitError: Error?
    var fieldValueProvider: (() -> String?)?

    func captureInsertionContext() -> TextInsertionContext? {
        insertionContext
    }

    func makeFocusedFieldValueProvider() -> (() -> String?)? {
        fieldValueProvider
    }

    func warmTargetAppAccessibility() {
        warmTargetAppAccessibilityCallCount += 1
    }

    @MainActor
    @discardableResult
    func insertText(_ text: String) async throws -> InsertionOutcome {
        attemptedTexts.append(text)
        if let insertError {
            throw insertError
        }
        insertedTexts.append(text)
        return insertOutcome
    }

    func copyTextToClipboard(_ text: String) throws {
        if let copyError {
            throw copyError
        }
        copiedTexts.append(text)
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

/// In-memory stats store. Tests must never touch the real
/// ~/Library/Application Support/Suniye/stats.json.
final class TestDictationStatsStore: DictationStatsStoring {
    private(set) var flushCount = 0
    private(set) var stats = DictationStats.empty
    private(set) var recordedSeeds = 0

    func record(words: Int, seconds: TimeInterval, at date: Date) {
        stats.record(words: words, seconds: seconds, on: date)
    }

    func seedFromHistoryIfNeeded(_ results: [RecentResult]) {
        guard !stats.didSeedFromHistory else {
            return
        }
        recordedSeeds += 1
        for result in results.sorted(by: { $0.createdAt < $1.createdAt }) {
            stats.record(words: result.wordCount, seconds: result.durationSeconds, on: result.createdAt)
        }
        stats.didSeedFromHistory = true
    }

    func flush() {
        flushCount += 1
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
    var isUpdateReadyToInstall = false
    var automaticallyChecksForUpdates = false
    var updateChannel: UpdateChannel = .stable
    var onStateChange: (() -> Void)?

    private(set) var startCallCount = 0
    private(set) var checkForUpdatesCallCount = 0
    private(set) var installUpdateAndRelaunchCallCount = 0

    func start() {
        startCallCount += 1
        canCheckForUpdates = true
        onStateChange?()
    }

    func checkForUpdates() {
        checkForUpdatesCallCount += 1
    }

    func installUpdateAndRelaunch() {
        installUpdateAndRelaunchCallCount += 1
    }

    func notifyStateChanged() {
        onStateChange?()
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
    var lastTranscribeInput: (samples: [Float], sampleRate: Int)?
    var loadedConfigs: [RecognizerConfig] = []
    var onTranscribe: (() -> Void)?
    /// Awaited after the scripted result is claimed; receives the 1-based call number.
    var onTranscribeAwait: ((Int) async -> Void)?
    /// Reported, in order, before each decode runs.
    var progressToReport: [TranscriptionProgress] = []

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

    func transcribe(
        samples: [Float],
        sampleRate: Int,
        purpose: TranscriptionPurpose,
        onProgress: @escaping @Sendable (TranscriptionProgress) -> Void
    ) async throws -> String {
        transcribeCallCount += 1
        transcribePurposes.append(purpose)
        lastTranscribeInput = (samples, sampleRate)
        let callNumber = transcribeCallCount
        progressToReport.forEach(onProgress)
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
        fallbackReason: nil,
        standIn: nil
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
    var onHotkeyChord: (() -> Void)?
    var onEditModeHotkeyDown: (() -> Void)?
    var onEditModeHotkeyUp: (() -> Void)?
    var onPasteLastTranscript: (() -> Void)?
    var onCancel: (() -> Void)?
    private(set) var startMonitoringCallCount = 0
    private(set) var lastConfiguration: HotkeyConfiguration?
    private(set) var lastEditModeConfiguration: HotkeyConfiguration?
    private(set) var lastPasteLastTranscriptConfiguration: HotkeyConfiguration?
    private(set) var isCancelShortcutEnabled = false

    func startMonitoring(
        configuration: HotkeyConfiguration,
        editModeConfiguration: HotkeyConfiguration?,
        pasteLastTranscriptConfiguration: HotkeyConfiguration
    ) {
        startMonitoringCallCount += 1
        lastConfiguration = configuration
        lastEditModeConfiguration = editModeConfiguration
        lastPasteLastTranscriptConfiguration = pasteLastTranscriptConfiguration
    }

    func stopMonitoring() {}

    func setCancelShortcutEnabled(_ enabled: Bool) {
        isCancelShortcutEnabled = enabled
    }
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

    private(set) var shownMessages: [String] = []

    func show(message: String, detail: String?, actionTitle: String?, action: (() -> Void)?) {
        shownMessages.append(message)
    }
}

@MainActor
final class SpyAccessibilityOnboarding: AccessibilityOnboardingPresenting {
    private(set) var presentCallCount = 0
    private(set) var dismissCallCount = 0
    private(set) var isPresenting = false
    private var pendingOnGranted: (() -> Void)?
    private var pendingOnEnded: ((AccessibilityOnboardingEnd) -> Void)?

    func present(onGranted: @escaping () -> Void, onEnded: @escaping (AccessibilityOnboardingEnd) -> Void) {
        presentCallCount += 1
        isPresenting = true
        pendingOnGranted = onGranted
        pendingOnEnded = onEnded
    }

    func dismiss() {
        dismissCallCount += 1
        end(.dismissed)
    }

    /// Simulate the user dragging the app in and the poller detecting the grant.
    func simulateGrant() {
        let onGranted = pendingOnGranted
        pendingOnGranted = nil
        end(.granted)
        onGranted?()
    }

    /// Simulate the user backing out of the overlay (back chevron / close).
    func simulateUserDismiss() {
        pendingOnGranted = nil
        end(.dismissed)
    }

    /// Simulate the 300s safety timeout firing with no grant.
    func simulateTimeout() {
        pendingOnGranted = nil
        end(.timedOut)
    }

    private func end(_ outcome: AccessibilityOnboardingEnd) {
        guard isPresenting else {
            return
        }
        isPresenting = false
        pendingOnGranted = nil
        let onEnded = pendingOnEnded
        pendingOnEnded = nil
        onEnded?(outcome)
    }
}

/// A test app that can record right away: phase ready, microphone and Accessibility granted.
@MainActor
func makeReadyTestAppState(
    transcriptionService: TranscriptionServiceProtocol = StubTranscriptionService(),
    audioCaptureService: AudioCaptureServiceProtocol = StubAudioCaptureService(),
    textInsertionService: TextInsertionServiceProtocol = SpyTextInsertionService(),
    analytics: Analytics = SpyAnalytics()
) -> AppState {
    let appState = makeTestAppState(
        transcriptionService: transcriptionService,
        audioCaptureService: audioCaptureService,
        textInsertionService: textInsertionService,
        analytics: analytics
    )
    appState.phase = .ready
    appState.hasMicPermission = true
    appState.hasAccessibilityPermission = true
    return appState
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
    statsStore: DictationStatsStoring = TestDictationStatsStore(),
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
    micAuthorizationStatusProvider: (() -> AVAuthorizationStatus)? = nil,
    micAccessRequester: (() async -> Bool)? = nil,
    accessibilityTrustProvider: (() -> Bool)? = nil,
    accessibilityTrustPrompter: (() -> Bool)? = nil,
    systemGlobeKeyActionProvider: @escaping () -> SystemGlobeKeyAction = { .doNothing },
    availableDiskCapacityProvider: (() async -> Int64?)? = nil,
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
        statsStore: statsStore,
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
        // Tests default to "not determined": permission state is then driven via
        // the stored Bools or per-test providers, never live TCC.
        micAuthorizationStatusProvider: micAuthorizationStatusProvider ?? { .notDetermined },
        micAccessRequester: micAccessRequester ?? { false },
        accessibilityTrustProvider: accessibilityTrustProvider ?? { true },
        // Never the live API: a real call would raise the system dialog.
        accessibilityTrustPrompter: accessibilityTrustPrompter ?? accessibilityTrustProvider ?? { true },
        // Never the live setting: the test Mac's Keyboard settings must not change results.
        systemGlobeKeyActionProvider: systemGlobeKeyActionProvider,
        availableDiskCapacityProvider: availableDiskCapacityProvider ?? { nil },
        issueReportDiagnosticsDestinationPicker: issueReportDiagnosticsDestinationPicker,
        temporaryFileCleanupScheduler: temporaryFileCleanupScheduler,
        magicFormatSlowWarningDelaySeconds: magicFormatSlowWarningDelaySeconds,
        meetingCoordinator: makeTestMeetingCoordinator(engine: transcriptionService, analytics: analytics),
        startServices: startServices,
        llmE2EMode: llmE2EMode
    )
}

/// Meetings on a temporary folder, with no audio source and no call app, so
/// a test app never reads, recovers or records the real meetings.
@MainActor
func makeTestMeetingCoordinator(engine: TranscriptionServiceProtocol, analytics: Analytics) -> MeetingCoordinator {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("suniye-meeting-tests-\(UUID().uuidString)", isDirectory: true)
    return MeetingCoordinator(
        store: MeetingStore(rootDirectory: root.appendingPathComponent("meetings", isDirectory: true)),
        templates: MeetingTemplateStore(fileURL: root.appendingPathComponent("templates.json")),
        settingsStore: MeetingSettingsStore(userDefaults: UserDefaults(suiteName: "suniye-meeting-tests-\(UUID().uuidString)")!),
        engine: engine,
        environment: MeetingEnvironment(
            makeSources: { _, _ in [:] },
            confirmNotice: { false },
            freeDiskBytes: { nil },
            callPlaysOnSpeakers: { false },
            makeMicrophoneUsers: { FakeMicrophoneUsers() },
            now: Date.init
        ),
        canRecordCallAudio: false,
        summaryAvailability: { .unavailable },
        makeSummaryModel: { _ in nil },
        analytics: analytics
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

/// Collects values from callbacks that may fire on any thread.
final class LockedRecorder<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Value] = []

    var values: [Value] {
        lock.withLock { storage }
    }

    func record(_ value: Value) {
        lock.withLock { storage.append(value) }
    }
}

/// Answers each `containsSpeech` call from `answers` in turn, repeating the last
/// one, and records the length of every clip it is asked about.
final class StubSpeechDetector: SpeechDetecting {
    private var answers: [Bool]
    private(set) var clipLengths: [Int] = []

    init(answers: [Bool]) {
        self.answers = answers
    }

    convenience init(result: Bool) {
        self.init(answers: [result])
    }

    func containsSpeech(_ samples: [Float]) -> Bool {
        clipLengths.append(samples.count)
        return answers.count > 1 ? answers.removeFirst() : answers[0]
    }
}
