import AppKit
import AVFoundation
import Foundation
import Observation
import SwiftUI

enum LLME2EMode {
    case none
    case forceSuccess
    case forceFailure

    var logValue: String {
        switch self {
        case .none:
            return "none"
        case .forceSuccess:
            return "success"
        case .forceFailure:
            return "fallback"
        }
    }
}

enum AttentionSeverity: String {
    case error
    case warning
}

struct AttentionItem: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let severity: AttentionSeverity
    let recommendedSection: MainWindowSection
    let fixTitle: String?
    let fixAction: (@MainActor () -> Void)?

    init(id: String, title: String, detail: String, severity: AttentionSeverity, recommendedSection: MainWindowSection, fixTitle: String? = nil, fixAction: (@MainActor () -> Void)? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
        self.severity = severity
        self.recommendedSection = recommendedSection
        self.fixTitle = fixTitle
        self.fixAction = fixAction
    }

    static func == (lhs: AttentionItem, rhs: AttentionItem) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.detail == rhs.detail && lhs.severity == rhs.severity && lhs.recommendedSection == rhs.recommendedSection && lhs.fixTitle == rhs.fixTitle
    }
}

enum MagicFormatSetupState: Equatable {
    case off
    case needsAPIKey
    case needsServiceSetup
    case ready

    var title: String {
        switch self {
        case .off:
            return "Off"
        case .needsAPIKey:
            return "Needs API key"
        case .needsServiceSetup:
            return "Needs service setup"
        case .ready:
            return "Ready"
        }
    }

    var detail: String {
        switch self {
        case .off:
            return "Turn it on to improve dictation before text is pasted."
        case .needsAPIKey:
            return "Add an API key to start using Magic Format."
        case .needsServiceSetup:
            return "Finish the service setup above."
        case .ready:
            return "Magic Format is ready to improve your text before it is pasted."
        }
    }

    var icon: String {
        switch self {
        case .off:
            return "pause.circle"
        case .needsAPIKey, .needsServiceSetup:
            return "exclamationmark.circle"
        case .ready:
            return "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .off:
            return MainWindowPalette.secondaryText
        case .needsAPIKey, .needsServiceSetup:
            return .orange
        case .ready:
            return .green
        }
    }
}

struct MagicFormatSetupTestResult: Equatable {
    enum Severity: Equatable {
        case success
        case error

        var color: Color {
            switch self {
            case .success:
                .green
            case .error:
                .red
            }
        }
    }

    let message: String
    let severity: Severity
}

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case setup
    case practice

    var title: String {
        switch self {
        case .welcome:
            return "Welcome"
        case .setup:
            return "Set Up"
        case .practice:
            return "Try It"
        }
    }
}

struct OnboardingPracticeResult: Equatable {
    enum Severity: Equatable {
        case success
        case error

        var color: Color {
            switch self {
            case .success:
                .green
            case .error:
                .red
            }
        }
    }

    let message: String
    let severity: Severity
}

@MainActor
@Observable
final class AppState {
    typealias RecordingSource = FloatingIndicatorState.Source
    private static let automaticUpdateCheckInterval: TimeInterval = 5 * 60 * 60
    private static let automaticUpdateTimerTolerance: TimeInterval = 5 * 60

    enum Phase: String {
        case needsModel
        case downloadingModel
        case loading
        case ready
        case recording
        case transcribing
        case error
    }

    enum UpdateStatus: String {
        case idle
        case checking
        case upToDate
        case available
        case downloading
        case downloaded
        case error
    }

    var phase: Phase = .loading {
        didSet {
            if oldValue != phase {
                onStateChange?()
                AppLogger.shared.log(.info, "phase changed: \(oldValue.rawValue) -> \(phase.rawValue)")
            }
        }
    }
    var statusText = "Initializing..." {
        didSet {
            if oldValue != statusText {
                onStateChange?()
            }
        }
    }
    var lastError: String?

    var updateStatus: UpdateStatus = .idle {
        didSet {
            if oldValue != updateStatus {
                onStateChange?()
                AppLogger.shared.log(.info, "update status changed: \(oldValue.rawValue) -> \(updateStatus.rawValue)")
            }
        }
    }
    var availableUpdateVersion: String? {
        didSet {
            if oldValue != availableUpdateVersion {
                onStateChange?()
            }
        }
    }
    var updateStatusText = "No update check yet." {
        didSet {
            if oldValue != updateStatusText {
                onStateChange?()
            }
        }
    }
    var appVersionText: String {
        currentAppVersionProvider()?.displayString ?? "Unknown"
    }

    var updateDownloadProgress: Double = 0 {
        didSet {
            if oldValue != updateDownloadProgress {
                onStateChange?()
            }
        }
    }

    var downloadProgress: Double = 0 {
        didSet {
            if oldValue != downloadProgress {
                onStateChange?()
            }
        }
    }
    var modelDownloadStartedAt: Date?
    var wordsTranscribed = 0
    var sessionCount = 0
    var totalDictationSeconds: TimeInterval = 0
    var recentResults: [RecentResult] = [] {
        didSet {
            guard !isHydratingHistory else {
                return
            }
            persistHistory()
            recomputeHistoryStats()
        }
    }

    var availableInputDevices: [AudioInputDevice] = []
    var selectedInputDeviceID: String? {
        didSet {
            guard !isHydratingGeneralSettings else {
                return
            }
            persistGeneralSettings()
            onStateChange?()
        }
    }
    var autoSubmitEnabled = false {
        didSet {
            guard !isHydratingGeneralSettings else {
                return
            }
            persistGeneralSettings()
            onStateChange?()
        }
    }
    var echoCancellationEnabled = false {
        didSet {
            guard !isHydratingGeneralSettings else {
                return
            }
            persistGeneralSettings()
            onStateChange?()
        }
    }
    var hotkeyConfiguration: HotkeyConfiguration = .globe {
        didSet {
            guard !isHydratingGeneralSettings else {
                return
            }
            persistGeneralSettings()
            if runtimeServicesEnabled {
                wireHotkey()
            }
            onStateChange?()
        }
    }
    var hasSeenOnboardingWelcome = false {
        didSet {
            guard !isHydratingGeneralSettings else {
                return
            }
            if oldValue != hasSeenOnboardingWelcome {
                persistGeneralSettings()
                onStateChange?()
            }
        }
    }
    var hasCompletedCoreOnboarding = false {
        didSet {
            guard !isHydratingGeneralSettings else {
                return
            }
            if oldValue != hasCompletedCoreOnboarding {
                persistGeneralSettings()
                onStateChange?()
            }
        }
    }
    var activeOnboardingStep: OnboardingStep? {
        didSet {
            guard oldValue != activeOnboardingStep else {
                return
            }
            if activeOnboardingStep != .practice {
                onboardingPracticeResult = nil
            }
            onStateChange?()
        }
    }
    var onboardingPracticeText = "" {
        didSet {
            if oldValue != onboardingPracticeText {
                onStateChange?()
            }
        }
    }
    var onboardingPracticeResult: OnboardingPracticeResult? {
        didSet {
            if oldValue != onboardingPracticeResult {
                onStateChange?()
            }
        }
    }

    var hasMicPermission = false
    var hasAccessibilityPermission = false

    var llmEnabled = false {
        didSet { persistLLMSettings() }
    }
    var llmSelectedModelPreset: LLMModelPreset = .gemini25Flash {
        didSet { persistLLMSettings() }
    }
    var llmCustomModelId = "" {
        didSet { persistLLMSettings() }
    }
    var llmEndpointURLString = LLMDefaults.defaultEndpointURLString {
        didSet { persistLLMSettings() }
    }
    var llmBaseSystemPrompt = LLMDefaults.defaultBaseSystemPrompt {
        didSet { persistLLMSettings() }
    }
    var llmSystemPrompt = "" {
        didSet { persistLLMSettings() }
    }
    var llmKeywordsRaw = "" {
        didSet { persistLLMSettings() }
    }
    var llmTimeoutSeconds = LLMDefaults.defaultTimeoutSeconds {
        didSet {
            let clamped = LLMDefaults.clampTimeout(llmTimeoutSeconds)
            if llmTimeoutSeconds != clamped {
                llmTimeoutSeconds = clamped
                return
            }
            persistLLMSettings()
        }
    }
    var llmMaxTokens = LLMDefaults.defaultMaxTokens {
        didSet {
            let clamped = LLMDefaults.clampMaxTokens(llmMaxTokens)
            if llmMaxTokens != clamped {
                llmMaxTokens = clamped
                return
            }
            persistLLMSettings()
        }
    }

    var hasLLMAPIKey = false {
        didSet {
            if oldValue != hasLLMAPIKey {
                onStateChange?()
            }
        }
    }
    var llmKeyOperationError: String?
    var isMagicFormatSetupTestInProgress = false
    var magicFormatSetupTestResult: MagicFormatSetupTestResult?
    private var magicFormatSetupTestRequestID = 0

    var launchAtLoginStatus: LaunchAtLoginStatus = .disabled
    var launchAtLoginError: String?

    var isModelInstalled: Bool {
        modelManager.isModelReady()
    }

    var llmKeyStatusText: String {
        if hasLLMAPIKey && isMagicFormatSetupVerified {
            return "Connected"
        }
        return hasLLMAPIKey ? "Saved" : "Not connected"
    }

    var isMagicFormatSetupVerified: Bool {
        magicFormatSetupTestResult?.severity == .success
    }

    func canTestMagicFormatSetup(apiKeyDraft: String) -> Bool {
        guard llmEnabled, !isMagicFormatSetupTestInProgress else {
            return false
        }
        guard llmEndpointValidationError == nil, llmModelValidationError == nil else {
            return false
        }
        return effectiveMagicFormatTestAPIKey(apiKeyDraft: apiKeyDraft) != nil
    }

    var magicFormatSetupState: MagicFormatSetupState {
        guard llmEnabled else {
            return .off
        }
        if llmEndpointValidationError != nil || llmModelValidationError != nil {
            return .needsServiceSetup
        }
        if !hasLLMAPIKey {
            return .needsAPIKey
        }
        return .ready
    }

    var llmEndpointValidationError: String? {
        currentLLMSettings().endpointValidationError
    }

    var llmModelValidationError: String? {
        currentLLMSettings().modelValidationError
    }

    var llmStatusHint: String? {
        magicFormatSetupState.detail
    }

    var llmSelectedModelIdPreview: String {
        currentLLMSettings().validatedModelId ?? ""
    }

    func llmDisplayModelId(for preset: LLMModelPreset) -> String {
        currentLLMSettings().displayModelId(for: preset)
    }

    var vocabularyTerms: [String] {
        currentLLMSettings().keywords
    }

    var recentResultsPreview: [RecentResult] {
        Array(recentResults.prefix(12))
    }

    var todaySessionCount: Int {
        let calendar = Calendar.current
        return recentResults.filter { calendar.isDateInToday($0.createdAt) }.count
    }

    var modelInstalledSizeText: String {
        ByteCountFormatter.string(fromByteCount: modelManager.installedByteCount(), countStyle: .file)
    }

    var modelExpectedByteCount: Int64 {
        modelManager.expectedDownloadSizeBytes
    }

    var modelExpectedSizeText: String {
        "~" + ByteCountFormatter.string(fromByteCount: modelManager.expectedDownloadSizeBytes, countStyle: .file)
    }

    var modelDownloadETAStatusText: String {
        modelDownloadETAText ?? "Estimating time remaining"
    }

    var modelDownloadProgressLabel: String {
        guard phase == .downloadingModel else {
            return ""
        }

        let percentage = Int(downloadProgress * 100)
        let downloadedBytes = Int64(Double(modelManager.expectedDownloadSizeBytes) * downloadProgress)
        let downloadedSize = ByteCountFormatter.string(fromByteCount: downloadedBytes, countStyle: .file)
        if let etaText = modelDownloadETAText {
            return "\(percentage)% downloaded • \(downloadedSize) of \(modelExpectedSizeText)\n\(etaText)"
        }
        return "\(percentage)% downloaded • \(downloadedSize) of \(modelExpectedSizeText)\nEstimating time remaining"
    }

    var isModelOperationInProgress: Bool {
        phase == .downloadingModel || (phase == .loading && !isModelInstalled)
    }

    var modelOperationStatusText: String {
        switch phase {
        case .downloadingModel:
            return "Downloading model…"
        case .loading where !isModelInstalled:
            return "Extracting and validating model…"
        default:
            return ""
        }
    }

    var modelStatusValue: String {
        switch phase {
        case .downloadingModel:
            return "Downloading \(Int(downloadProgress * 100))%"
        case .loading:
            return isModelInstalled ? "Loading" : "Validating"
        case .ready, .recording, .transcribing:
            return isModelInstalled ? "Ready" : "Missing"
        case .error:
            return isModelInstalled ? "Ready" : "Download failed"
        case .needsModel:
            return "Missing"
        }
    }

    var modelStatusColor: Color {
        switch phase {
        case .ready, .recording, .transcribing:
            return isModelInstalled ? .green : .orange
        case .downloadingModel, .loading:
            return .accentColor
        case .error:
            return isModelInstalled ? .green : .red
        case .needsModel:
            return .orange
        }
    }

    var modelStatusIcon: String {
        switch phase {
        case .ready, .recording, .transcribing:
            return isModelInstalled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        case .downloadingModel, .loading:
            return "arrow.down.circle.fill"
        case .error:
            return isModelInstalled ? "checkmark.circle.fill" : "xmark.octagon.fill"
        case .needsModel:
            return "exclamationmark.triangle.fill"
        }
    }

    var modelPrimaryActionTitle: String {
        if isModelInstalled {
            return "Delete Model"
        }
        if phase == .downloadingModel {
            return "Downloading…"
        }
        return "Download Model"
    }

    var modelPrimaryActionDetail: String {
        if isModelInstalled {
            return "Stored locally for offline transcription. Delete to reclaim disk space."
        }
        if phase == .downloadingModel {
            return "Keep Suniye open until the archive is downloaded, extracted, and validated."
        }
        if phase == .error, let lastError, !lastError.isEmpty {
            return "Last attempt failed. Retry the offline model download to enable local transcription."
        }
        return "Download the required offline model to enable local transcription."
    }

    var modelLocationText: String {
        (try? modelManager.modelDirectoryURL().path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) ?? "~/Library/Application Support/Suniye/models"
    }

    var launchAtLoginDetailText: String {
        launchAtLoginStatus.detailText
    }

    var launchAtLoginEnabledForUI: Bool {
        launchAtLoginStatus.isEnabledForUI
    }

    var selectedInputDeviceName: String {
        if let selectedInputDeviceID,
           let selected = availableInputDevices.first(where: { $0.id == selectedInputDeviceID }) {
            return selected.name
        }
        return availableInputDevices.first(where: \.isDefault)?.name ?? "System Default"
    }

    var isOnboardingSetupComplete: Bool {
        hasMicPermission && hasAccessibilityPermission && isModelInstalled && phase == .ready
    }

    var onboardingPracticeLevels: [Float] {
        switch floatingIndicatorState {
        case let .listening(levels, _):
            return levels
        default:
            return Array(repeating: 0.08, count: 12)
        }
    }

    var isOnboardingPracticeRecording: Bool {
        activeOnboardingStep == .practice && phase == .recording
    }

    var isOnboardingPracticeProcessing: Bool {
        activeOnboardingStep == .practice && phase == .transcribing
    }

    var attentionItems: [AttentionItem] {
        var items: [AttentionItem] = []

        if phase == .error,
           let error = lastError?.trimmingCharacters(in: .whitespacesAndNewlines),
           !error.isEmpty {
            items.append(
                AttentionItem(
                    id: "runtime-error",
                    title: "Transcription unavailable",
                    detail: error,
                    severity: .error,
                    recommendedSection: .general
                )
            )
        }

        if !isModelInstalled {
            items.append(
                AttentionItem(
                    id: "model-missing",
                    title: "Model not installed",
                    detail: "Download the required Parakeet model to enable dictation.",
                    severity: .warning,
                    recommendedSection: .model
                )
            )
        }

        if !hasMicPermission {
            items.append(
                AttentionItem(
                    id: "mic-permission-missing",
                    title: "Microphone permission missing",
                    detail: "Grant microphone access so audio can be captured.",
                    severity: .warning,
                    recommendedSection: .general,
                    fixTitle: "Grant Access",
                    fixAction: { [weak self] in self?.requestMicrophonePermission() }
                )
            )
        }

        if !hasAccessibilityPermission {
            items.append(
                AttentionItem(
                    id: "accessibility-permission-missing",
                    title: "Accessibility permission missing",
                    detail: "Grant accessibility access so transcribed text can be inserted.",
                    severity: .warning,
                    recommendedSection: .general,
                    fixTitle: "Grant Access",
                    fixAction: { [weak self] in self?.requestAccessibilityPermission() }
                )
            )
        }

        if llmEnabled, let endpointValidationError = llmEndpointValidationError {
            items.append(
                AttentionItem(
                    id: "llm-endpoint-invalid",
                    title: "Magic Format needs service setup",
                    detail: endpointValidationError,
                    severity: .warning,
                    recommendedSection: .style
                )
            )
        }

        if llmEnabled, let modelValidationError = llmModelValidationError {
            items.append(
                AttentionItem(
                    id: "llm-model-invalid",
                    title: "Magic Format needs service setup",
                    detail: modelValidationError,
                    severity: .warning,
                    recommendedSection: .style
                )
            )
        }

        if llmEnabled && !hasLLMAPIKey {
            items.append(
                AttentionItem(
                    id: "llm-key-missing",
                    title: "Magic Format needs an API key",
                    detail: "Magic Format is on, but your API key is missing.",
                    severity: .warning,
                    recommendedSection: .style
                )
            )
        }

        return items
    }

    var onStateChange: (() -> Void)?
    var floatingIndicatorState: FloatingIndicatorState = .idle

    private let modelManager: ModelManagerProtocol
    private let transcriptionService: TranscriptionServiceProtocol
    private let audioCaptureService: AudioCaptureServiceProtocol
    private let textInsertionService: TextInsertionServiceProtocol
    private let hotkeyService: HotkeyServiceProtocol
    private let floatingIndicatorController = FloatingIndicatorController()
    private let llmPostProcessor: LLMPostProcessor
    private let llmSettingsStore: LLMSettingsStoreProtocol
    private let generalSettingsStore: GeneralSettingsStoreProtocol
    private let historyStore: HistoryStoreProtocol
    private let keychainService: KeychainServiceProtocol
    private let updateService: UpdateServiceProtocol
    private let launchAtLoginService: LaunchAtLoginServiceProtocol
    private let currentAppVersionProvider: () -> AppVersion?
    private let nowProvider: () -> Date
    private let fileOpener: (URL) -> Bool
    private let runtimeServicesEnabled: Bool
    private let floatingIndicatorEnabled: Bool

    private var recordingStart: Date?
    private var activeRecordingSource: RecordingSource?
    private var overlayErrorResetTask: Task<Void, Never>?
    private var isHydratingLLMSettings = false
    private var isHydratingGeneralSettings = false
    private var isHydratingHistory = false
    private let llmE2EMode: LLME2EMode
    private var availableUpdateRelease: UpdateRelease?
    private var downloadedUpdateArchiveURL: URL?
    private var automaticUpdateTimer: Timer?
    private var lastAutomaticUpdateAttemptAt: Date?

    private enum DictationDestination: Equatable {
        case systemInsertion
        case onboardingPractice
    }

    deinit {
        MainActor.assumeIsolated {
            automaticUpdateTimer?.invalidate()
        }
    }

    init(
        modelManager: ModelManagerProtocol = ModelManager(),
        transcriptionService: TranscriptionServiceProtocol = TranscriptionService(),
        audioCaptureService: AudioCaptureServiceProtocol = AudioCaptureService(),
        textInsertionService: TextInsertionServiceProtocol = TextInsertionService(),
        hotkeyService: HotkeyServiceProtocol = HotkeyService(),
        llmPostProcessor: LLMPostProcessor = OpenRouterPostProcessor(),
        llmSettingsStore: LLMSettingsStoreProtocol = LLMSettingsStore(),
        generalSettingsStore: GeneralSettingsStoreProtocol = GeneralSettingsStore(),
        historyStore: HistoryStoreProtocol = HistoryStore(),
        keychainService: KeychainServiceProtocol = KeychainService(),
        updateService: UpdateServiceProtocol = GitHubUpdateService(),
        launchAtLoginService: LaunchAtLoginServiceProtocol = LaunchAtLoginService(),
        currentAppVersionProvider: @escaping () -> AppVersion? = { AppVersion.fromBundle() },
        nowProvider: @escaping () -> Date = Date.init,
        fileOpener: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
        startServices: Bool = true,
        llmE2EMode: LLME2EMode? = nil
    ) {
        self.modelManager = modelManager
        self.transcriptionService = transcriptionService
        self.audioCaptureService = audioCaptureService
        self.textInsertionService = textInsertionService
        self.hotkeyService = hotkeyService
        self.llmPostProcessor = llmPostProcessor
        self.llmSettingsStore = llmSettingsStore
        self.generalSettingsStore = generalSettingsStore
        self.historyStore = historyStore
        self.keychainService = keychainService
        self.updateService = updateService
        self.launchAtLoginService = launchAtLoginService
        self.currentAppVersionProvider = currentAppVersionProvider
        self.nowProvider = nowProvider
        self.fileOpener = fileOpener
        self.runtimeServicesEnabled = startServices
        self.floatingIndicatorEnabled = startServices && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
        self.llmE2EMode = llmE2EMode ?? AppState.detectLLME2EMode(arguments: CommandLine.arguments)
        self.audioCaptureService.onLevelsUpdate = { [weak self] levels in
            Task { @MainActor [weak self] in
                self?.handleAudioLevelsUpdate(levels)
            }
        }

        AppLogger.shared.log(.info, "app state init")
        loadHistory()
        loadGeneralSettings()
        loadLLMSettings()
        refreshInputDevices()
        refreshLaunchAtLoginStatus()
        refreshLLMKeyStatus()

        if floatingIndicatorEnabled {
            floatingIndicatorController.onAction = { [weak self] in
                self?.toggleFloatingIndicatorRecording()
            }
        }

        if startServices {
            wireHotkey()
            Task {
                await bootstrap()
            }
        }
    }

    func bootstrap() async {
        AppLogger.shared.log(.info, "bootstrap start")
        if floatingIndicatorEnabled {
            floatingIndicatorController.start()
        }
        statusText = "Checking permissions..."
        await refreshPermissions()

        statusText = "Checking model..."
        if modelManager.isModelReady() {
            phase = .loading
            statusText = "Loading model..."
            let didLoadRecognizer = await loadRecognizerIfPossible()
            if didLoadRecognizer {
                phase = .ready
                statusText = "Ready"
                lastError = nil
            }
        } else {
            phase = .needsModel
            statusText = "Model required"
        }
        startOnboardingIfNeeded()
        setFloatingIndicatorState(.idle)
        AppLogger.shared.log(.info, "bootstrap done")
    }

    func startOnboardingIfNeeded() {
        guard !hasCompletedCoreOnboarding else {
            activeOnboardingStep = nil
            return
        }

        if isOnboardingSetupComplete {
            completeCoreOnboarding()
            return
        }

        activeOnboardingStep = hasSeenOnboardingWelcome ? .setup : .welcome
    }

    func advanceOnboarding() {
        switch activeOnboardingStep {
        case .welcome:
            hasSeenOnboardingWelcome = true
            if isOnboardingSetupComplete {
                completeCoreOnboarding()
            } else {
                activeOnboardingStep = .setup
            }
        case .setup:
            guard isOnboardingSetupComplete else {
                return
            }
            completeCoreOnboarding()
        case .practice:
            finishOnboarding()
        case nil:
            startOnboardingIfNeeded()
        }
    }

    func goBackOnboarding() {
        guard activeOnboardingStep == .setup else {
            return
        }
        activeOnboardingStep = .welcome
    }

    func completeCoreOnboarding() {
        hasSeenOnboardingWelcome = true
        hasCompletedCoreOnboarding = true
        onboardingPracticeText = ""
        onboardingPracticeResult = nil
        activeOnboardingStep = .practice
    }

    func finishOnboarding() {
        onboardingPracticeResult = nil
        activeOnboardingStep = nil
    }

    func refreshPermissions(requestMicrophone: Bool = false, promptAccessibility: Bool = false) async {
        if requestMicrophone {
            hasMicPermission = await AVCaptureDevice.requestAccess(for: .audio)
        } else {
            hasMicPermission = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        }

        if promptAccessibility {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            hasAccessibilityPermission = AXIsProcessTrustedWithOptions(options)
        } else {
            hasAccessibilityPermission = AXIsProcessTrusted()
        }

        AppLogger.shared.log(.info, "permissions: mic=\(hasMicPermission) ax=\(hasAccessibilityPermission)")
        refreshOnboardingProgressIfNeeded()
        onStateChange?()
    }

    func requestAccessibilityPermission() {
        Task {
            await refreshPermissions(promptAccessibility: true)
        }
    }

    func requestMicrophonePermission() {
        Task {
            await refreshPermissions(requestMicrophone: true)
        }
    }

    func refreshPermissionStatus() {
        Task {
            await refreshPermissions()
        }
    }

    func openMicrophonePrivacySettings() {
        openSystemSettings(urlCandidates: [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Microphone",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
        ])
    }

    func openAccessibilityPrivacySettings() {
        openSystemSettings(urlCandidates: [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        ])
    }

    func refreshInputDevices() {
        let devices = audioCaptureService.availableInputDevices()
        availableInputDevices = devices

        if let selectedInputDeviceID,
           !devices.contains(where: { $0.id == selectedInputDeviceID }) {
            self.selectedInputDeviceID = nil
        }
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLoginStatus = launchAtLoginService.currentStatus()
        launchAtLoginError = nil
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        do {
            launchAtLoginStatus = try launchAtLoginService.setEnabled(enabled)
            launchAtLoginError = nil
        } catch {
            launchAtLoginStatus = launchAtLoginService.currentStatus()
            launchAtLoginError = error.localizedDescription
            AppLogger.shared.log(.error, "launch at login update failed: \(error.localizedDescription)")
        }
        onStateChange?()
    }

    func refreshLLMKeyStatus() {
        hasLLMAPIKey = keychainService.hasLLMKey()
    }

    func saveLLMAPIKey(_ key: String) {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            llmKeyOperationError = "API key can't be empty."
            onStateChange?()
            return
        }

        do {
            try keychainService.setLLMKey(normalized)
            llmKeyOperationError = nil
            refreshLLMKeyStatus()
            clearMagicFormatSetupTestResult()
            AppLogger.shared.log(.info, "llm api key saved")
        } catch {
            llmKeyOperationError = "Couldn't save the API key."
            AppLogger.shared.log(.error, "llm api key save failed")
            onStateChange?()
        }
    }

    func clearLLMAPIKey() {
        do {
            try keychainService.deleteLLMKey()
            llmKeyOperationError = nil
            refreshLLMKeyStatus()
            clearMagicFormatSetupTestResult()
            AppLogger.shared.log(.info, "llm api key cleared")
        } catch {
            llmKeyOperationError = "Couldn't clear the API key."
            AppLogger.shared.log(.error, "llm api key clear failed")
            onStateChange?()
        }
    }

    func clearMagicFormatSetupTestResult() {
        magicFormatSetupTestRequestID += 1
        isMagicFormatSetupTestInProgress = false
        magicFormatSetupTestResult = nil
    }

    func testMagicFormatSetup(apiKeyDraft: String) async {
        clearMagicFormatSetupTestResult()

        guard llmEnabled else {
            return
        }
        guard let endpointURL = currentLLMSettings().validatedEndpointURL else {
            return
        }
        guard let modelId = currentLLMSettings().validatedModelId else {
            return
        }
        guard let apiKey = effectiveMagicFormatTestAPIKey(apiKeyDraft: apiKeyDraft) else {
            return
        }

        let requestID = magicFormatSetupTestRequestID
        isMagicFormatSetupTestInProgress = true
        let config = makeLLMConfig(apiKey: apiKey, endpointURL: endpointURL, modelId: modelId)
        let startTime = Date()

        defer {
            if requestID == magicFormatSetupTestRequestID {
                isMagicFormatSetupTestInProgress = false
            }
        }

        do {
            try await llmPostProcessor.testSetup(config: config)
            guard requestID == magicFormatSetupTestRequestID else {
                AppLogger.shared.log(.info, "ignored stale magic format setup test success")
                return
            }
            magicFormatSetupTestResult = MagicFormatSetupTestResult(
                message: "Connection works.",
                severity: .success
            )
            let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
            AppLogger.shared.log(.info, "magic format setup test success model=\(config.modelId) latency_ms=\(latencyMs)")
        } catch let error as LLMPostProcessorError {
            guard requestID == magicFormatSetupTestRequestID else {
                AppLogger.shared.log(.info, "ignored stale magic format setup test failure reason=\(error.logValue)")
                return
            }
            magicFormatSetupTestResult = MagicFormatSetupTestResult(
                message: magicFormatSetupTestMessage(for: error),
                severity: .error
            )
            let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
            AppLogger.shared.log(.warning, "magic format setup test failed reason=\(error.logValue) model=\(config.modelId) latency_ms=\(latencyMs)")
        } catch {
            guard requestID == magicFormatSetupTestRequestID else {
                AppLogger.shared.log(.info, "ignored stale magic format setup test failure reason=unknown")
                return
            }
            magicFormatSetupTestResult = MagicFormatSetupTestResult(
                message: "Couldn't reach that service URL.",
                severity: .error
            )
            let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
            AppLogger.shared.log(.warning, "magic format setup test failed reason=unknown model=\(config.modelId) latency_ms=\(latencyMs)")
        }
    }

    func addVocabularyTerm(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        let combined = vocabularyTerms + [trimmed]
        llmKeywordsRaw = LLMDefaults.parseKeywords(from: combined.joined(separator: "\n")).joined(separator: "\n")
    }

    func removeVocabularyTerm(_ value: String) {
        let filtered = vocabularyTerms.filter { $0.caseInsensitiveCompare(value) != .orderedSame }
        llmKeywordsRaw = filtered.joined(separator: "\n")
    }

    func copyRecentResult(_ result: RecentResult) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(result.text, forType: .string)
    }

    func deleteRecentResult(_ result: RecentResult) {
        recentResults.removeAll { $0.id == result.id }
    }

    func startModelDownload() {
        guard phase != .recording && phase != .transcribing else {
            return
        }

        phase = .downloadingModel
        statusText = "Downloading model..."
        lastError = nil
        downloadProgress = 0
        modelDownloadStartedAt = nowProvider()

        Task {
            do {
                AppLogger.shared.log(.info, "model download started")
                try await modelManager.downloadAndExtractModel { [weak self] progress in
                    Task { @MainActor in
                        self?.downloadProgress = progress
                    }
                }

                phase = .loading
                statusText = "Validating model..."
                modelDownloadStartedAt = nil

                guard modelManager.isModelReady() else {
                    throw AppStateError.modelValidationFailed
                }

                let didLoadRecognizer = await loadRecognizerIfPossible()
                if didLoadRecognizer {
                    phase = .ready
                    statusText = "Ready"
                    lastError = nil
                    refreshOnboardingProgressIfNeeded()
                    AppLogger.shared.log(.info, "model download complete")
                }
            } catch {
                phase = .error
                lastError = error.localizedDescription
                statusText = "Download failed"
                modelDownloadStartedAt = nil
                AppLogger.shared.log(.error, "model download failed: \(error.localizedDescription)")
            }
        }
    }

    func deleteModel() {
        guard phase != .recording && phase != .transcribing && phase != .downloadingModel else {
            return
        }

        Task {
            do {
                try modelManager.deleteModel()
                await transcriptionService.unloadModel()
                phase = .needsModel
                statusText = "Model required"
                downloadProgress = 0
                modelDownloadStartedAt = nil
                lastError = nil
                AppLogger.shared.log(.info, "model deleted")
            } catch {
                phase = .error
                statusText = "Model delete failed"
                lastError = error.localizedDescription
                AppLogger.shared.log(.error, "model delete failed: \(error.localizedDescription)")
            }
        }
    }

    func openModelFolder() {
        do {
            let folder = try modelManager.modelDirectoryURL().deletingLastPathComponent()
            NSWorkspace.shared.open(folder)
            AppLogger.shared.log(.info, "open model folder: \(folder.path)")
        } catch {
            AppLogger.shared.log(.error, "open model folder failed: \(error.localizedDescription)")
        }
    }

    func openMainWindow() {
        MainWindowController.shared.show(appState: self)
    }

    func toggleFloatingIndicatorRecording() {
        Task { @MainActor in
            switch phase {
            case .ready:
                await beginRecordingFlow(trigger: .manual)
            case .recording where activeRecordingSource == .manual:
                await stopRecordingAndTranscribe(trigger: .manual)
            default:
                showTransientIndicatorError(startBlockedMessage(for: phase), restoreState: blockedStartRestoreIndicatorState(), duration: 1.2)
            }
        }
    }

    func startRecordingFromUI() {
        Task { @MainActor in
            await beginRecordingFlow(trigger: .manual)
        }
    }

    func stopRecordingFromUI() {
        guard phase == .recording else {
            return
        }
        let trigger = activeRecordingSource ?? .manual
        Task {
            await stopRecordingAndTranscribe(trigger: trigger)
        }
    }

    func startAutomaticUpdateChecks() {
        guard automaticUpdateTimer == nil else {
            return
        }

        AppLogger.shared.log(.info, "automatic update checks started interval=\(Int(Self.automaticUpdateCheckInterval))s")

        Task { @MainActor [weak self] in
            await self?.performAutomaticUpdateCheckIfEligible()
        }

        let timer = Timer.scheduledTimer(withTimeInterval: Self.automaticUpdateCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.performAutomaticUpdateCheckIfEligible()
            }
        }
        timer.tolerance = Self.automaticUpdateTimerTolerance
        automaticUpdateTimer = timer
    }

    func performAutomaticUpdateCheckIfEligible(now: Date? = nil) async {
        let now = now ?? nowProvider()
        guard shouldPerformAutomaticUpdateCheck(now: now) else {
            return
        }

        lastAutomaticUpdateAttemptAt = now
        await checkForUpdates(background: true)
    }

    func checkForUpdates(background: Bool) async {
        guard updateStatus != .checking, updateStatus != .downloading else {
            return
        }

        if !background, updateStatus == .downloaded, downloadedUpdateArchiveURL != nil {
            AppLogger.shared.log(.info, "manual update check skipped: installer already cached")
            return
        }

        let previousUpdateStatus = updateStatus
        let previousUpdateStatusText = updateStatusText
        let hadCachedDownloadedUpdate = previousUpdateStatus == .downloaded && downloadedUpdateArchiveURL != nil

        updateStatus = .checking
        if !background {
            updateStatusText = "Checking for updates..."
        }

        guard let currentVersion = currentAppVersionProvider() else {
            AppLogger.shared.log(.error, "update check failed: local app version missing")
            if hadCachedDownloadedUpdate {
                updateStatus = .downloaded
                updateStatusText = previousUpdateStatusText
            } else if background {
                updateStatus = previousUpdateStatus
                updateStatusText = previousUpdateStatusText
            } else {
                updateStatus = .error
                updateStatusText = "Unable to read local app version."
            }
            return
        }

        do {
            let result = try await updateService.checkForUpdate(currentVersion: currentVersion)
            switch result {
            case .upToDate:
                availableUpdateRelease = nil
                availableUpdateVersion = nil
                downloadedUpdateArchiveURL = nil
                if background {
                    updateStatus = .idle
                } else {
                    updateStatus = .upToDate
                    updateStatusText = "You're up to date."
                }
                AppLogger.shared.log(.info, "update check complete: up-to-date")
            case let .updateAvailable(release):
                availableUpdateRelease = release
                availableUpdateVersion = release.versionTag
                updateStatus = .available
                updateStatusText = "Update available: \(release.versionTag)"
                AppLogger.shared.log(.info, "update available: \(release.versionTag)")
                await downloadLatestUpdateInBackground(release: release)
            }
        } catch {
            AppLogger.shared.log(.warning, "update check failed: \(error.localizedDescription)")
            if hadCachedDownloadedUpdate {
                updateStatus = .downloaded
                updateStatusText = previousUpdateStatusText
            } else if background {
                updateStatus = previousUpdateStatus
                updateStatusText = previousUpdateStatusText
            } else {
                updateStatus = .error
                updateStatusText = error.localizedDescription
            }
        }
    }

    func downloadAndOpenUpdate() async {
        guard updateStatus != .downloading else {
            return
        }
        guard let release = availableUpdateRelease else {
            updateStatus = .error
            updateStatusText = "No update is currently available."
            return
        }

        if let downloadedUpdateArchiveURL {
            if fileOpener(downloadedUpdateArchiveURL) {
                updateStatus = .downloaded
                updateStatusText = "Installer opened for \(release.versionTag)."
                AppLogger.shared.log(.info, "opened downloaded installer: \(downloadedUpdateArchiveURL.path)")
            } else {
                updateStatus = .downloaded
                updateStatusText = "Update is ready to install. Failed to open the installer. Try again."
                AppLogger.shared.log(.error, "open downloaded installer failed: \(downloadedUpdateArchiveURL.path)")
            }
            return
        }

        updateStatus = .downloading
        updateStatusText = "Downloading update..."
        updateDownloadProgress = 0

        do {
            let archiveURL = try await updateService.downloadAndVerify(release: release)
            downloadedUpdateArchiveURL = archiveURL
            guard fileOpener(archiveURL) else {
                updateStatus = .downloaded
                updateDownloadProgress = 1
                updateStatusText = "Update downloaded. Failed to open installer. Try again."
                AppLogger.shared.log(.error, "update download complete but open failed: \(archiveURL.path)")
                return
            }
            updateDownloadProgress = 1
            updateStatus = .downloaded
            updateStatusText = "Update downloaded. Installer opened."
            AppLogger.shared.log(.info, "update download complete and opened: \(archiveURL.path)")
        } catch {
            updateStatus = .available
            updateStatusText = error.localizedDescription
            updateDownloadProgress = 0
            AppLogger.shared.log(.error, "update download failed: \(error.localizedDescription)")
        }
    }

    func openReleaseNotes() {
        guard let release = availableUpdateRelease else {
            return
        }
        NSWorkspace.shared.open(release.htmlURL)
    }

    private func downloadLatestUpdateInBackground(release: UpdateRelease) async {
        guard updateStatus != .downloading else {
            return
        }

        updateStatus = .downloading
        updateStatusText = "Downloading update \(release.versionTag)..."
        updateDownloadProgress = 0

        do {
            let archiveURL = try await updateService.downloadAndVerify(release: release)
            downloadedUpdateArchiveURL = archiveURL
            updateDownloadProgress = 1
            updateStatus = .downloaded
            updateStatusText = "Update \(release.versionTag) is ready to install."
            AppLogger.shared.log(.info, "update predownload complete: \(archiveURL.path)")
        } catch {
            updateStatus = .available
            updateStatusText = "Update available: \(release.versionTag)"
            updateDownloadProgress = 0
            downloadedUpdateArchiveURL = nil
            AppLogger.shared.log(.warning, "update predownload failed: \(error.localizedDescription)")
        }
    }

    private func shouldPerformAutomaticUpdateCheck(now: Date) -> Bool {
        switch updateStatus {
        case .checking, .downloading, .downloaded:
            return false
        case .idle, .upToDate, .available, .error:
            break
        }

        guard let lastAutomaticUpdateAttemptAt else {
            return true
        }

        return now.timeIntervalSince(lastAutomaticUpdateAttemptAt) >= Self.automaticUpdateCheckInterval
    }

    func postProcessTextIfEnabled(_ rawText: String) async -> String {
        let input = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            return rawText
        }

        switch llmE2EMode {
        case .forceSuccess:
            AppLogger.shared.log(.info, "llm e2e forced success")
            return "\(input)."
        case .forceFailure:
            AppLogger.shared.log(.warning, "llm e2e forced fallback")
            return rawText
        case .none:
            break
        }

        guard llmEnabled else {
            return rawText
        }

        guard let endpointURL = currentLLMSettings().validatedEndpointURL else {
            AppLogger.shared.log(.warning, "llm fallback raw reason=invalid_endpoint")
            return rawText
        }

        guard let modelId = currentLLMSettings().validatedModelId else {
            AppLogger.shared.log(.warning, "llm fallback raw reason=invalid_model")
            return rawText
        }

        // TODO: Generic OpenAI-compatible backends can be keyless, but the current
        // LLM settings flow still treats a missing API key as a hard stop.
        guard hasLLMAPIKey else {
            AppLogger.shared.log(.warning, "llm fallback raw reason=missing_key")
            return rawText
        }

        guard let apiKey = try? keychainService.getLLMKey(),
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            AppLogger.shared.log(.warning, "llm fallback raw reason=key_read_failed")
            refreshLLMKeyStatus()
            return rawText
        }

        let config = makeLLMConfig(apiKey: apiKey, endpointURL: endpointURL, modelId: modelId)
        let startTime = Date()
        statusText = "Polishing..."

        do {
            let polished = try await llmPostProcessor.polish(text: input, config: config)
            let normalized = polished.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else {
                AppLogger.shared.log(.warning, "llm fallback raw reason=empty_output model=\(config.modelId)")
                return rawText
            }
            let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
            AppLogger.shared.log(.info, "llm polish success model=\(config.modelId) latency_ms=\(latencyMs)")
            return normalized
        } catch {
            let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
            if let llmError = error as? LLMPostProcessorError {
                AppLogger.shared.log(.warning, "llm fallback raw reason=\(llmError.logValue) model=\(config.modelId) latency_ms=\(latencyMs)")
            } else {
                AppLogger.shared.log(.warning, "llm fallback raw reason=unknown model=\(config.modelId) latency_ms=\(latencyMs)")
            }
            return rawText
        }
    }

    func runIndicatorE2ESmoke() {
        Task { @MainActor in
            AppLogger.shared.log(.info, "e2e indicator smoke start")
            setFloatingIndicatorState(.idle)
            try? await Task.sleep(nanoseconds: 220_000_000)
            setFloatingIndicatorState(.hover)
            try? await Task.sleep(nanoseconds: 220_000_000)
            setFloatingIndicatorState(.listening(levels: Self.defaultIndicatorLevels(level: 0.72), source: .manual))
            try? await Task.sleep(nanoseconds: 220_000_000)
            setFloatingIndicatorState(.processing)
            try? await Task.sleep(nanoseconds: 220_000_000)
            showTransientIndicatorError("Microphone permission required", restoreState: .idle, duration: 0.35)
            try? await Task.sleep(nanoseconds: 900_000_000)
            AppLogger.shared.log(.info, "e2e indicator smoke done")
            NSApp.terminate(nil)
        }
    }

    func runLLME2ESmoke() {
        Task { @MainActor in
            AppLogger.shared.log(.info, "e2e llm smoke start mode=\(llmE2EMode.logValue)")
            llmEnabled = true
            let input = "this is a llm smoke test"
            let output = await postProcessTextIfEnabled(input)
            let changed = output != input
            AppLogger.shared.log(.info, "e2e llm smoke result mode=\(llmE2EMode.logValue) changed=\(changed)")
            NSApp.terminate(nil)
        }
    }

    func runSubmitCommandE2ESmoke() {
        Task { @MainActor in
            AppLogger.shared.log(.info, "e2e submit smoke start")
            let cases: [(input: String, expectedText: String, expectedSubmit: Bool)] = [
                ("hello world send", "hello world", true),
                ("hello world, enter.", "hello world", true),
                ("send", "", true),
                ("please send me notes", "please send me notes", false)
            ]

            var passed = true
            for testCase in cases {
                let parsed = AppState.parseSubmitCommand(from: testCase.input)
                if parsed.text != testCase.expectedText || parsed.shouldSubmit != testCase.expectedSubmit {
                    passed = false
                    AppLogger.shared.log(.error, "e2e submit smoke case failed")
                }
            }

            AppLogger.shared.log(.info, "e2e submit smoke done passed=\(passed)")
            NSApp.terminate(nil)
        }
    }

    private func wireHotkey() {
        hotkeyService.onHotkeyDown = { [weak self] in
            AppLogger.shared.log(.debug, "hotkey callback: down")
            Task { @MainActor in
                await self?.beginRecordingFlow(trigger: .hotkey)
            }
        }

        hotkeyService.onHotkeyUp = { [weak self] in
            AppLogger.shared.log(.debug, "hotkey callback: up")
            Task { @MainActor in
                await self?.stopRecordingAndTranscribe(trigger: .hotkey)
            }
        }

        hotkeyService.startMonitoring(configuration: hotkeyConfiguration)
        AppLogger.shared.log(.info, "hotkey monitoring started configuration=\(hotkeyConfiguration.displayString)")
    }

    private func loadRecognizerIfPossible() async -> Bool {
        do {
            let config = try modelManager.makeRecognizerConfig()
            try await transcriptionService.loadModel(config: config)
            return true
        } catch {
            phase = .error
            lastError = "Model load failed: \(error.localizedDescription)"
            statusText = "Load failed"
            AppLogger.shared.log(.error, "model load failed: \(error.localizedDescription)")
            return false
        }
    }

    private func beginRecordingFlow(trigger: RecordingSource) async {
        if phase == .error, canRetryRecordingAfterError {
            clearRetryableRecordingError()
        }
        if isOnboardingBlockingRecordingStart {
            AppLogger.shared.log(.debug, "start recording ignored while onboarding setup is active")
            showTransientIndicatorError("Finish setup first", restoreState: .idle, duration: 1.2)
            return
        }
        guard phase == .ready else {
            AppLogger.shared.log(.debug, "start recording ignored in phase=\(phase.rawValue)")
            showTransientIndicatorError(startBlockedMessage(for: phase), restoreState: blockedStartRestoreIndicatorState(), duration: 1.2)
            return
        }
        if !hasMicPermission {
            await refreshPermissions(requestMicrophone: true)
        }
        guard hasMicPermission else {
            lastError = "Microphone permission not granted"
            statusText = "Permission required"
            AppLogger.shared.log(.warning, "microphone permission denied")
            showTransientIndicatorError("Microphone permission required")
            return
        }

        if !hasAccessibilityPermission {
            await refreshPermissions(promptAccessibility: true)
        }
        guard hasAccessibilityPermission else {
            lastError = "Accessibility permission not granted"
            statusText = "Accessibility required"
            AppLogger.shared.log(.warning, "accessibility permission denied before recording")
            showTransientIndicatorError("Enable Accessibility for dictation")
            return
        }
        startRecording(trigger: trigger)
    }

    private func startRecording(trigger: RecordingSource) {
        guard phase == .ready else {
            return
        }

        do {
            try audioCaptureService.startCapture(preferredInputDeviceID: selectedInputDeviceID, echoCancellationEnabled: echoCancellationEnabled)
            phase = .recording
            statusText = "Recording"
            recordingStart = Date()
            activeRecordingSource = trigger
            overlayErrorResetTask?.cancel()
            overlayErrorResetTask = nil
            if currentDictationDestination == .onboardingPractice {
                onboardingPracticeResult = nil
            }
            setFloatingIndicatorState(.listening(levels: Self.defaultIndicatorLevels(level: 0), source: trigger))
            AppLogger.shared.log(.info, "recording started input=\(selectedInputDeviceID ?? "default")")
        } catch {
            lastError = "Audio start failed: \(error.localizedDescription)"
            statusText = "Ready"
            AppLogger.shared.log(.error, "audio start failed: \(error.localizedDescription)")
            showTransientIndicatorError("Failed to start audio capture")
        }
    }

    private func stopRecordingAndTranscribe(trigger: RecordingSource) async {
        guard phase == .recording else {
            return
        }
        guard activeRecordingSource == nil || activeRecordingSource == trigger else {
            return
        }

        phase = .transcribing
        statusText = "Transcribing..."
        setFloatingIndicatorState(.processing)

        let captured = audioCaptureService.stopCapture()
        let samples = captured.samples
        let sampleRate = captured.sampleRate
        let duration = recordingStart.map { Date().timeIntervalSince($0) } ?? 0
        let destination = currentDictationDestination
        AppLogger.shared.log(.info, "dictation stop samples=\(samples.count) sr=\(sampleRate) duration=\(String(format: "%.2f", duration))")

        do {
            let text = try await transcriptionService.transcribe(samples: samples, sampleRate: sampleRate)
            let rawText = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let rawParse = AppState.parseSubmitCommand(from: rawText)
            let llmInputText = destination == .systemInsertion ? rawParse.text : rawText
            var shouldSubmit = destination == .systemInsertion ? rawParse.shouldSubmit : false
            var llmOutputText = llmInputText
            var finalText = llmInputText

            if !finalText.isEmpty {
                llmOutputText = await postProcessTextIfEnabled(llmInputText)
                if destination == .systemInsertion {
                    let polishedParse = AppState.parseSubmitCommand(from: llmOutputText)
                    finalText = polishedParse.text
                    shouldSubmit = shouldSubmit || polishedParse.shouldSubmit
                } else {
                    finalText = llmOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            if destination == .systemInsertion && autoSubmitEnabled && !finalText.isEmpty {
                shouldSubmit = true
            }

            let wordCount = finalText.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            let wasLLMPolished = AppState.didLLMPolish(input: llmInputText, output: llmOutputText)

            if destination == .systemInsertion && (!finalText.isEmpty || shouldSubmit) {
                if !hasAccessibilityPermission {
                    await refreshPermissions(promptAccessibility: true)
                }
                guard hasAccessibilityPermission else {
                    throw NSError(domain: "Suniye", code: 1, userInfo: [NSLocalizedDescriptionKey: "Accessibility permission not granted"])
                }
            }

            switch destination {
            case .systemInsertion:
                if !finalText.isEmpty {
                    try textInsertionService.insertText(finalText)
                    recentResults.insert(
                        RecentResult(
                            id: UUID(),
                            text: finalText,
                            createdAt: Date(),
                            durationSeconds: duration,
                            wasLLMPolished: wasLLMPolished
                        ),
                        at: 0
                    )
                    AppLogger.shared.log(.info, "transcription complete words=\(wordCount)")
                }

                if shouldSubmit {
                    if !finalText.isEmpty {
                        try? await Task.sleep(nanoseconds: 120_000_000)
                    }
                    try textInsertionService.submitActiveInput()
                    AppLogger.shared.log(.info, "submit command executed")
                }

                if finalText.isEmpty && !shouldSubmit {
                    AppLogger.shared.log(.warning, "transcription returned empty text samples=\(samples.count) sr=\(sampleRate)")
                }
            case .onboardingPractice:
                onboardingPracticeText = finalText
                if finalText.isEmpty {
                    let message = rawText.isEmpty
                        ? "No speech detected. Try a short phrase."
                        : "Practice mode captured audio, but there was no text to preview."
                    onboardingPracticeResult = OnboardingPracticeResult(message: message, severity: .error)
                    AppLogger.shared.log(.warning, "onboarding practice produced empty text")
                } else {
                    onboardingPracticeResult = OnboardingPracticeResult(
                        message: "Captured locally. You can finish onboarding whenever you're ready.",
                        severity: .success
                    )
                    AppLogger.shared.log(.info, "onboarding practice transcription complete words=\(wordCount)")
                }
            }
            activeRecordingSource = nil
            recordingStart = nil
            lastError = nil
            phase = .ready
            statusText = "Ready"
            setFloatingIndicatorState(.idle)
        } catch {
            activeRecordingSource = nil
            recordingStart = nil
            lastError = "Transcription failed: \(error.localizedDescription)"
            if destination == .onboardingPractice {
                onboardingPracticeResult = OnboardingPracticeResult(
                    message: error.localizedDescription,
                    severity: .error
                )
            }
            phase = .ready
            statusText = "Ready"
            AppLogger.shared.log(.error, "transcription failed: \(error.localizedDescription)")
            showTransientIndicatorError("Transcription failed")
        }
    }

    private func loadHistory() {
        isHydratingHistory = true
        recentResults = historyStore.load()
        isHydratingHistory = false
        recomputeHistoryStats()
    }

    private func persistHistory() {
        historyStore.save(recentResults)
        onStateChange?()
    }

    private func recomputeHistoryStats() {
        sessionCount = recentResults.count
        wordsTranscribed = recentResults.reduce(0) { $0 + $1.wordCount }
        totalDictationSeconds = recentResults.reduce(0) { $0 + $1.durationSeconds }
    }

    private func loadGeneralSettings() {
        isHydratingGeneralSettings = true
        let settings = generalSettingsStore.load()
        selectedInputDeviceID = settings.preferredInputDeviceID
        autoSubmitEnabled = settings.autoSubmitEnabled
        hotkeyConfiguration = settings.hotkeyConfiguration
        echoCancellationEnabled = settings.echoCancellationEnabled
        hasSeenOnboardingWelcome = settings.hasSeenOnboardingWelcome ?? false
        hasCompletedCoreOnboarding = settings.hasCompletedCoreOnboarding ?? false
        isHydratingGeneralSettings = false
        normalizeOnboardingSettingsIfNeeded(loadedSettings: settings)
    }

    private func persistGeneralSettings() {
        generalSettingsStore.save(currentGeneralSettings())
    }

    private func currentGeneralSettings() -> GeneralSettings {
        GeneralSettings(
            preferredInputDeviceID: selectedInputDeviceID,
            autoSubmitEnabled: autoSubmitEnabled,
            hotkeyConfiguration: hotkeyConfiguration,
            echoCancellationEnabled: echoCancellationEnabled,
            hasSeenOnboardingWelcome: hasSeenOnboardingWelcome,
            hasCompletedCoreOnboarding: hasCompletedCoreOnboarding
        )
    }

    private func normalizeOnboardingSettingsIfNeeded(loadedSettings: GeneralSettings) {
        let needsNormalization = loadedSettings.hasSeenOnboardingWelcome == nil
            || loadedSettings.hasCompletedCoreOnboarding == nil
            || (loadedSettings.hasCompletedCoreOnboarding == true && loadedSettings.hasSeenOnboardingWelcome != true)

        guard needsNormalization else {
            return
        }

        let shouldMarkComplete = shouldAutoCompleteOnboardingForLegacyUser
        let normalizedComplete = loadedSettings.hasCompletedCoreOnboarding ?? shouldMarkComplete
        let normalizedWelcome = loadedSettings.hasSeenOnboardingWelcome ?? (normalizedComplete || shouldMarkComplete)

        hasSeenOnboardingWelcome = normalizedWelcome
        hasCompletedCoreOnboarding = normalizedComplete
        persistGeneralSettings()
    }

    private var shouldAutoCompleteOnboardingForLegacyUser: Bool {
        if isModelInstalled || !recentResults.isEmpty {
            return true
        }

        return selectedInputDeviceID != nil
            || autoSubmitEnabled
            || echoCancellationEnabled
            || hotkeyConfiguration != .globe
    }

    private func loadLLMSettings() {
        isHydratingLLMSettings = true
        let settings = llmSettingsStore.load()
        let mergedPrompt = Self.mergedMagicFormatPrompt(
            basePrompt: settings.baseSystemPrompt,
            extraPrompt: settings.systemPrompt
        )
        let shouldNormalizeHiddenSettings = settings.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || settings.timeoutSeconds != LLMDefaults.defaultTimeoutSeconds
            || settings.maxTokens != LLMDefaults.defaultMaxTokens
        llmEnabled = settings.isEnabled
        llmSelectedModelPreset = settings.selectedModelPreset
        llmCustomModelId = settings.customModelId
        llmEndpointURLString = settings.endpointURLString
        llmBaseSystemPrompt = mergedPrompt
        llmSystemPrompt = ""
        llmKeywordsRaw = settings.keywordsRaw
        llmTimeoutSeconds = LLMDefaults.defaultTimeoutSeconds
        llmMaxTokens = LLMDefaults.defaultMaxTokens
        isHydratingLLMSettings = false

        if shouldNormalizeHiddenSettings {
            persistLLMSettings()
        }
    }

    private func persistLLMSettings() {
        guard !isHydratingLLMSettings else {
            return
        }
        clearMagicFormatSetupTestResult()
        llmSettingsStore.save(currentLLMSettings())
        onStateChange?()
    }

    private func currentLLMSettings() -> LLMSettings {
        LLMSettings(
            isEnabled: llmEnabled,
            selectedModelPreset: llmSelectedModelPreset,
            customModelId: llmCustomModelId,
            endpointURLString: llmEndpointURLString,
            baseSystemPrompt: llmBaseSystemPrompt,
            systemPrompt: "",
            keywordsRaw: llmKeywordsRaw,
            timeoutSeconds: LLMDefaults.defaultTimeoutSeconds,
            maxTokens: LLMDefaults.defaultMaxTokens
        )
    }

    private static func mergedMagicFormatPrompt(basePrompt: String, extraPrompt: String) -> String {
        let normalizedBase = basePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedExtra = extraPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let visiblePrompt = normalizedBase.isEmpty ? LLMDefaults.defaultBaseSystemPrompt : normalizedBase

        guard !normalizedExtra.isEmpty else {
            return visiblePrompt
        }

        if visiblePrompt == normalizedExtra || visiblePrompt.hasSuffix("\n\n\(normalizedExtra)") {
            return visiblePrompt
        }

        return "\(visiblePrompt)\n\n\(normalizedExtra)"
    }

    private func openSystemSettings(urlCandidates: [String]) {
        for candidate in urlCandidates {
            guard let url = URL(string: candidate) else {
                continue
            }
            if fileOpener(url) {
                AppLogger.shared.log(.info, "opened system settings url: \(candidate)")
                return
            }
        }

        lastError = "Unable to open System Settings."
        AppLogger.shared.log(.error, "failed to open system settings")
        onStateChange?()
    }

    private func makeLLMConfig(apiKey: String, endpointURL: URL, modelId: String) -> LLMConfig {
        let settings = currentLLMSettings()
        return LLMConfig(
            modelId: modelId,
            endpointURL: endpointURL,
            systemPrompt: settings.composedSystemPrompt,
            keywords: settings.keywords,
            timeoutSeconds: settings.timeoutSeconds,
            apiKey: apiKey
        )
    }

    private func effectiveMagicFormatTestAPIKey(apiKeyDraft: String) -> String? {
        let normalizedDraft = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedDraft.isEmpty {
            return normalizedDraft
        }

        guard let savedKey = try? keychainService.getLLMKey()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !savedKey.isEmpty else {
            return nil
        }

        return savedKey
    }

    private func magicFormatSetupTestMessage(for error: LLMPostProcessorError) -> String {
        switch error {
        case .unauthorized:
            return "The API key was rejected."
        case .timeout, .network:
            return "Couldn't reach that service URL."
        case let .provider(reason):
            if let statusText = reason.split(separator: "_").last,
               reason.hasPrefix("http_"),
               let status = Int(statusText) {
                switch status {
                case 404:
                    return "HTTP 404: service URL not found."
                case 429:
                    return "HTTP 429: rate limited. Try again in a moment."
                case 500...599:
                    return "HTTP \(status): server error. Try again."
                default:
                    return "HTTP \(status): the service rejected this setup. Check the URL and model."
                }
            }
            return "The service rejected this setup. Check the URL and model, then try again."
        case .malformedResponse, .emptyOutput, .invalidConfiguration:
            return "The service responded, but not in a compatible format."
        }
    }

    private func setFloatingIndicatorState(_ state: FloatingIndicatorState) {
        floatingIndicatorState = state
        guard floatingIndicatorEnabled else { return }
        floatingIndicatorController.update(state)
    }

    private func showTransientIndicatorError(
        _ message: String,
        restoreState: FloatingIndicatorState = .idle,
        duration: TimeInterval = 1.8
    ) {
        overlayErrorResetTask?.cancel()
        setFloatingIndicatorState(.error(message: message))

        let delayNanos = UInt64(max(duration, 0) * 1_000_000_000)
        overlayErrorResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delayNanos)
            guard let self, !Task.isCancelled else { return }
            guard case .error = self.floatingIndicatorState else {
                self.overlayErrorResetTask = nil
                return
            }
            self.setFloatingIndicatorState(restoreState)
            self.overlayErrorResetTask = nil
        }
    }

    private func blockedStartRestoreIndicatorState() -> FloatingIndicatorState {
        switch phase {
        case .recording:
            if case let .listening(levels, source) = floatingIndicatorState {
                return .listening(levels: levels, source: source)
            }
            return .listening(
                levels: Self.defaultIndicatorLevels(level: 0.72),
                source: activeRecordingSource ?? .manual
            )
        case .transcribing:
            return .processing
        case .needsModel, .downloadingModel, .loading, .ready, .error:
            return .idle
        }
    }

    private var currentDictationDestination: DictationDestination {
        activeOnboardingStep == .practice ? .onboardingPractice : .systemInsertion
    }

    private var isOnboardingBlockingRecordingStart: Bool {
        activeOnboardingStep == .welcome || activeOnboardingStep == .setup
    }

    private var modelDownloadETAText: String? {
        guard let startedAt = modelDownloadStartedAt,
              downloadProgress > 0.01 else {
            return nil
        }

        let elapsed = nowProvider().timeIntervalSince(startedAt)
        guard elapsed >= 1 else {
            return nil
        }

        let remaining = elapsed * (1 - downloadProgress) / downloadProgress
        guard remaining.isFinite else {
            return nil
        }
        if remaining <= 1 {
            return "Almost done"
        }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = remaining >= 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2

        guard let formatted = formatter.string(from: remaining) else {
            return nil
        }

        return "About \(formatted) left"
    }

    private func refreshOnboardingProgressIfNeeded() {
        guard activeOnboardingStep == .setup,
              !hasCompletedCoreOnboarding,
              isOnboardingSetupComplete else {
            return
        }
        completeCoreOnboarding()
    }

    private func handleAudioLevelsUpdate(_ levels: [Float]) {
        guard case let .listening(_, source) = floatingIndicatorState else {
            return
        }
        setFloatingIndicatorState(.listening(levels: levels, source: source))
    }

    private static func defaultIndicatorLevels(level: Float, count: Int = 12) -> [Float] {
        Array(repeating: max(0, min(level, 1)), count: count)
    }

    private func startBlockedMessage(for phase: Phase) -> String {
        switch phase {
        case .needsModel:
            return "Download model first"
        case .downloadingModel:
            return "Model download in progress"
        case .loading:
            return "Still loading model"
        case .ready:
            return "Ready"
        case .recording:
            return "Already listening"
        case .transcribing:
            return "Still processing previous clip"
        case .error:
            return "Resolve current error first"
        }
    }

    private var canRetryRecordingAfterError: Bool {
        switch statusText {
        case "Transcription error", "Audio error", "Permission required", "Accessibility required":
            return true
        default:
            return false
        }
    }

    private func clearRetryableRecordingError() {
        lastError = nil
        statusText = "Ready"
        phase = .ready
        AppLogger.shared.log(.info, "cleared retryable error state before recording")
    }

    nonisolated static func parseSubmitCommand(from text: String) -> (text: String, shouldSubmit: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ("", false)
        }

        let pattern = #"(?i)(?:^|\s)(send|enter)\b[\s\.\!\?,;:\)\]\"']*$"#
        guard let commandRange = trimmed.range(of: pattern, options: .regularExpression) else {
            return (trimmed, false)
        }

        var cleaned = String(trimmed[..<commandRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: #"[,\s]+$"#, with: "", options: .regularExpression)

        return (cleaned, true)
    }

    nonisolated static func didLLMPolish(input: String, output: String) -> Bool {
        let normalizedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedInput.isEmpty else {
            return false
        }
        return normalizedInput != output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func detectLLME2EMode(arguments: [String]) -> LLME2EMode {
        if arguments.contains("--e2e-llm-success") {
            return .forceSuccess
        }
        if arguments.contains("--e2e-llm-fallback") {
            return .forceFailure
        }
        return .none
    }
}

private extension LLMPostProcessorError {
    var logValue: String {
        switch self {
        case .invalidConfiguration:
            return "invalid_config"
        case .timeout:
            return "timeout"
        case .unauthorized:
            return "unauthorized"
        case .provider:
            return "provider_error"
        case .malformedResponse:
            return "malformed_response"
        case .emptyOutput:
            return "empty_output"
        case .network:
            return "network"
        }
    }
}

enum AppStateError: LocalizedError {
    case modelValidationFailed

    var errorDescription: String? {
        switch self {
        case .modelValidationFailed:
            return "Model files are missing after extraction."
        }
    }
}
