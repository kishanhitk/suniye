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

enum AttentionItemFixAction: Equatable {
    case requestMicrophonePermission
    case requestAccessibilityPermission

    var title: String {
        switch self {
        case .requestMicrophonePermission, .requestAccessibilityPermission:
            return "Grant Access"
        }
    }
}

struct AttentionItem: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let severity: AttentionSeverity
    let recommendedSection: MainWindowSection
    let fixAction: AttentionItemFixAction?

    var fixTitle: String? {
        fixAction?.title
    }

    init(id: String, title: String, detail: String, severity: AttentionSeverity, recommendedSection: MainWindowSection, fixAction: AttentionItemFixAction? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
        self.severity = severity
        self.recommendedSection = recommendedSection
        self.fixAction = fixAction
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

struct ASRModelBannerState: Equatable {
    enum Tone: Equatable {
        case info
        case error

        var color: Color {
            switch self {
            case .info:
                return .accentColor
            case .error:
                return .red
            }
        }

        var icon: String {
            switch self {
            case .info:
                return "arrow.triangle.2.circlepath.circle.fill"
            case .error:
                return "exclamationmark.triangle.fill"
            }
        }
    }

    let title: String
    let detail: String
    let tone: Tone
    let progress: Double?
}

@MainActor
@Observable
final class AppState {
    typealias RecordingSource = FloatingIndicatorState.Source

    enum Phase: String {
        case needsModel
        case downloadingModel
        case loading
        case ready
        case recording
        case transcribing
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

    var canCheckForUpdates = false {
        didSet {
            if oldValue != canCheckForUpdates {
                onStateChange?()
            }
        }
    }
    var automaticallyChecksForUpdates = false {
        didSet {
            if oldValue != automaticallyChecksForUpdates {
                onStateChange?()
            }
        }
    }
    var updateChannel: UpdateChannel = .stable {
        didSet {
            guard !isHydratingGeneralSettings, oldValue != updateChannel else {
                return
            }

            persistGeneralSettings()
            applyUpdateChannelToController()
            onStateChange?()
        }
    }
    var appVersionText: String {
        currentAppVersionProvider()?.displayString ?? "Unknown"
    }

    var downloadProgress: Double = 0 {
        didSet {
            if oldValue != downloadProgress {
                onStateChange?()
            }
        }
    }
    var modelDownloadStartedAt: Date?
    var activeASRModelOperationID: ASRModelID? {
        didSet {
            if oldValue != activeASRModelOperationID {
                onStateChange?()
            }
        }
    }
    var loadedASRModelID: ASRModelID? {
        didSet {
            if oldValue != loadedASRModelID {
                onStateChange?()
            }
        }
    }
    var lastFailedASRModelID: ASRModelID? {
        didSet {
            if oldValue != lastFailedASRModelID {
                onStateChange?()
            }
        }
    }
    var lastFailedASRModelError: String? {
        didSet {
            if oldValue != lastFailedASRModelError {
                onStateChange?()
            }
        }
    }
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

    var availableInputDevices: [AudioInputDevice] = [] {
        didSet {
            if oldValue != availableInputDevices {
                onStateChange?()
            }
        }
    }
    private(set) var preferredInputDeviceName: String?
    var selectedInputDeviceID: String? {
        didSet {
            guard !isHydratingGeneralSettings else {
                return
            }
            if let selectedInputDeviceID,
               let selected = availableInputDevices.first(where: { $0.id == selectedInputDeviceID && $0.isAvailable }) {
                preferredInputDeviceName = selected.name
            } else if selectedInputDeviceID == nil {
                preferredInputDeviceName = nil
            }
            persistGeneralSettings()
            refreshAudioRouteSnapshot()
            onStateChange?()
        }
    }
    private(set) var audioRouteSnapshot: AudioRouteSnapshot? {
        didSet {
            if oldValue != audioRouteSnapshot {
                onStateChange?()
            }
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
            refreshAudioRouteSnapshot()
            onStateChange?()
        }
    }
    var soundFeedbackEnabled = false {
        didSet {
            guard !isHydratingGeneralSettings else {
                return
            }
            persistGeneralSettings()
            onStateChange?()
        }
    }
    var hideFloatingIndicatorWhenIdle = false {
        didSet {
            guard !isHydratingGeneralSettings else {
                return
            }
            guard oldValue != hideFloatingIndicatorWhenIdle else {
                return
            }
            persistGeneralSettings()
            syncFloatingIndicatorPreferences()
            onStateChange?()
        }
    }
    var floatingIndicatorPlacement: FloatingIndicatorPlacement? {
        didSet {
            guard !isHydratingGeneralSettings else {
                return
            }
            guard oldValue != floatingIndicatorPlacement else {
                return
            }
            persistGeneralSettings()
            syncFloatingIndicatorPreferences()
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
    var selectedASRModelID: ASRModelID = .parakeetV3 {
        didSet {
            guard !isHydratingGeneralSettings else {
                return
            }
            guard oldValue != selectedASRModelID else {
                return
            }
            persistGeneralSettings()
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

    var issueReportType: IssueReportType = .other
    var issueReportTitle = ""
    var issueReportDescription = ""
    var issueReportContactEmail = ""
    var issueReportIncludesDiagnostics = true
    var issueReportStatus: IssueReportSubmissionStatus = .idle
    var issueReportDiagnosticsMessage: String?
    private var shouldResetIssueReportAfterClosedSubmission = false

    var canSubmitIssueReport: Bool {
        !issueReportStatus.isBusy
            && issueReportSubmitRequirementMessage == nil
    }

    var issueReportTitleRequirementMessage: String? {
        let count = issueReportTitle.trimmingCharacters(in: .whitespacesAndNewlines).count
        guard count < 3 else {
            return nil
        }

        let remaining = 3 - count
        return remaining == 1
            ? "Add 1 more character to the title."
            : "Add \(remaining) more characters to the title."
    }

    var issueReportDescriptionRequirementMessage: String? {
        let count = issueReportDescription.trimmingCharacters(in: .whitespacesAndNewlines).count
        guard count < 10 else {
            return nil
        }

        let remaining = 10 - count
        return remaining == 1
            ? "Add 1 more character to the description."
            : "Add \(remaining) more characters to the description."
    }

    var issueReportSubmitRequirementMessage: String? {
        issueReportTitleRequirementMessage
            ?? issueReportDescriptionRequirementMessage
            ?? issueReportContactEmailValidationError
    }

    var issueReportContactEmailValidationError: String? {
        let email = issueReportContactEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else {
            return nil
        }
        guard email.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil else {
            return "Enter a valid email address or leave it blank."
        }
        return nil
    }

    var llmEnabled = false {
        didSet { persistLLMSettings() }
    }
    var llmProvider: MagicFormatProvider = .automatic {
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
    var llmAppleSystemPrompt = LLMDefaults.defaultAppleMagicFormatPrompt {
        didSet { persistLLMSettings() }
    }
    var llmGemmaSystemPrompt = LLMDefaults.defaultGemmaMagicFormatPrompt {
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
    var localGemmaInstallState: LocalLLMInstallState = .notInstalled {
        didSet {
            if oldValue != localGemmaInstallState {
                onStateChange?()
            }
        }
    }

    var launchAtLoginStatus: LaunchAtLoginStatus = .disabled
    var launchAtLoginError: String?

    var asrModelCatalog: [ASRModelCatalogEntry] {
        modelManager.catalog
    }

    var currentASRModelEntry: ASRModelCatalogEntry {
        ASRModelCatalog.entry(for: selectedASRModelID)
    }

    var availableASRModelEntries: [ASRModelCatalogEntry] {
        asrModelCatalog.filter { $0.id != selectedASRModelID }
    }

    var hasAnyInstalledModel: Bool {
        !modelManager.installedModels().isEmpty
    }

    var isModelInstalled: Bool {
        modelManager.isInstalled(selectedASRModelID)
    }

    var llmKeyStatusText: String {
        if usesLocalMagicFormatSettings {
            if usesAppleMagicFormatSettings {
                return appleMagicFormatAvailability.isAvailable ? "Ready" : "Unavailable"
            }
            return localGemmaMagicFormatAvailability.isAvailable ? "Ready" : "Unavailable"
        }
        if hasLLMAPIKey && isMagicFormatSetupVerified {
            return "Connected"
        }
        return hasLLMAPIKey ? "Saved" : "Not connected"
    }

    var isMagicFormatSetupVerified: Bool {
        magicFormatSetupTestResult?.severity == .success
    }

    func canTestMagicFormatSetup(apiKeyDraft: String) -> Bool {
        guard llmEnabled, needsAPIConfigurationForMagicFormat, !isMagicFormatSetupTestInProgress else {
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
        if usesAppleMagicFormatSettings {
            return appleMagicFormatAvailability.isAvailable ? .ready : .needsServiceSetup
        }
        if usesLocalGemmaMagicFormatSettings {
            return localGemmaMagicFormatAvailability.isAvailable ? .ready : .needsServiceSetup
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
        guard needsAPIConfigurationForMagicFormat else {
            return nil
        }
        return currentLLMSettings().endpointValidationError
    }

    var llmModelValidationError: String? {
        guard needsAPIConfigurationForMagicFormat else {
            return nil
        }
        return currentLLMSettings().modelValidationError
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

    var appleMagicFormatAvailability: AppleFoundationModelsAvailability {
        appleMagicFormatPostProcessor.availability
    }

    var localGemmaMagicFormatAvailability: LocalGemmaAvailability {
        guard localLLMModelManager.isHardwareSupported else {
            return .unsupportedHardware
        }
        guard localLLMModelManager.isInstalled(localLLMModelManager.preferredModelID) else {
            return .modelNotInstalled
        }
        return localGemmaMagicFormatPostProcessor.availability
    }

    var isLocalGemmaProviderSelectable: Bool {
        localLLMModelManager.isHardwareSupported
    }

    var canSelectLocalGemmaDuringOnboarding: Bool {
        isLocalGemmaProviderSelectable
            && (!localGemmaInstallState.isInstalled || localGemmaMagicFormatAvailability.isAvailable)
    }

    var localGemmaModelEntry: LocalLLMModelCatalogEntry {
        localGemmaCatalogEntry(for: localLLMModelManager.preferredModelID)
    }

    var localGemmaInstallStatusText: String {
        switch localGemmaInstallState {
        case let .unavailable(reason):
            return reason
        case .notInstalled:
            return "Local model not installed."
        case let .downloading(progress):
            return "\(progress.percentageText) downloaded • \(progress.downloadedSizeText) of \(progress.expectedSizeText)"
        case .verifying:
            return "Verifying local model..."
        case let .installed(byteCount):
            if localGemmaMagicFormatAvailability.isAvailable {
                return "Local model ready."
            }
            let sizeText = ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
            return "\(sizeText) installed. \(localGemmaMagicFormatAvailability.statusText)"
        case let .failed(message):
            return message
        }
    }

    var localGemmaInstallProgress: Double? {
        if case let .downloading(progress) = localGemmaInstallState {
            return progress.fractionCompleted
        }
        return nil
    }

    var canStartLocalGemmaDownload: Bool {
        guard localLLMModelManager.isHardwareSupported,
              !localGemmaInstallState.isActive,
              localGemmaDownloadTask == nil else {
            return false
        }
        return !localGemmaInstallState.isInstalled
    }

    var canCancelLocalGemmaDownload: Bool {
        if case .downloading = localGemmaInstallState {
            return true
        }
        return false
    }

    var canDeleteLocalGemmaModel: Bool {
        localGemmaInstallState.isInstalled && !localGemmaInstallState.isActive
    }

    var usesAppleMagicFormatSettings: Bool {
        MagicFormatCoordinator.usesAppleSettings(
            requestedProvider: llmProvider,
            appleAvailability: appleMagicFormatAvailability
        )
    }

    var usesLocalGemmaMagicFormatSettings: Bool {
        MagicFormatCoordinator.usesLocalGemmaSettings(
            requestedProvider: llmProvider,
            appleAvailability: appleMagicFormatAvailability,
            localGemmaAvailability: localGemmaMagicFormatAvailability
        )
    }

    var usesLocalMagicFormatSettings: Bool {
        usesAppleMagicFormatSettings || usesLocalGemmaMagicFormatSettings
    }

    var needsAPIConfigurationForMagicFormat: Bool {
        MagicFormatCoordinator.needsAPIConfiguration(
            requestedProvider: llmProvider,
            appleAvailability: appleMagicFormatAvailability,
            localGemmaAvailability: localGemmaMagicFormatAvailability
        )
    }

    var magicFormatProviderDetailText: String {
        switch llmProvider {
        case .automatic:
            if appleMagicFormatAvailability.isAvailable {
                return "Using Apple Intelligence locally."
            }
            if localGemmaMagicFormatAvailability.isAvailable {
                return "Using local model."
            }
            return "Local providers unavailable. API endpoint will be used if configured."
        case .appleFoundationModels:
            return appleMagicFormatAvailability.statusText
        case .localGemma:
            return localGemmaInstallStatusText
        case .openAICompatible:
            return "Using your OpenAI-compatible endpoint."
        }
    }

    var recentResultsPreview: [RecentResult] {
        Array(recentResults.prefix(12))
    }

    var lastTranscriptText: String? {
        recentResults.first?.text
    }

    var todaySessionCount: Int {
        let calendar = Calendar.current
        return recentResults.filter { calendar.isDateInToday($0.createdAt) }.count
    }

    var modelInstalledSizeText: String {
        ByteCountFormatter.string(fromByteCount: modelManager.installedByteCount(for: selectedASRModelID), countStyle: .file)
    }

    var modelExpectedByteCount: Int64 {
        modelManager.expectedDownloadSizeBytes(for: activeASRModelOperationID ?? selectedASRModelID)
    }

    var modelExpectedSizeText: String {
        "~" + ByteCountFormatter.string(fromByteCount: modelExpectedByteCount, countStyle: .file)
    }

    var modelDownloadETAStatusText: String {
        modelDownloadETAText ?? "Estimating time remaining"
    }

    var modelDownloadProgressLabel: String {
        guard phase == .downloadingModel else {
            return ""
        }

        let percentage = Int(downloadProgress * 100)
        let downloadedBytes = Int64(Double(modelExpectedByteCount) * downloadProgress)
        let downloadedSize = ByteCountFormatter.string(fromByteCount: downloadedBytes, countStyle: .file)
        if let etaText = modelDownloadETAText {
            return "\(percentage)% downloaded • \(downloadedSize) of \(modelExpectedSizeText)\n\(etaText)"
        }
        return "\(percentage)% downloaded • \(downloadedSize) of \(modelExpectedSizeText)\nEstimating time remaining"
    }

    var isModelOperationInProgress: Bool {
        activeASRModelOperationID != nil && (phase == .downloadingModel || phase == .loading)
    }

    var modelOperationStatusText: String {
        let modelName = (activeASRModelOperationID.map { ASRModelCatalog.entry(for: $0).displayName }) ?? currentASRModelEntry.displayName
        switch phase {
        case .downloadingModel:
            return "Downloading \(modelName)…"
        case .loading where activeASRModelOperationID != nil && !isModelInstalled:
            return "Extracting and validating \(modelName)…"
        case .loading where activeASRModelOperationID != nil:
            return "Loading \(modelName)…"
        default:
            return ""
        }
    }

    var modelStatusValue: String {
        switch phase {
        case .downloadingModel:
            if activeASRModelOperationID == selectedASRModelID {
                return "Downloading \(Int(downloadProgress * 100))%"
            }
            return loadedASRModelID == selectedASRModelID ? "Current" : (isModelInstalled ? "Installed" : "Missing")
        case .loading:
            return activeASRModelOperationID == selectedASRModelID ? (isModelInstalled ? "Loading" : "Validating") : (loadedASRModelID == selectedASRModelID ? "Current" : "Missing")
        case .ready, .recording, .transcribing:
            return loadedASRModelID == selectedASRModelID ? "Current" : (isModelInstalled ? "Installed" : "Missing")
        case .error:
            if lastFailedASRModelID == selectedASRModelID {
                return "Download failed"
            }
            return loadedASRModelID == selectedASRModelID ? "Current" : (isModelInstalled ? "Installed" : "Missing")
        case .needsModel:
            return "Missing"
        }
    }

    var modelStatusColor: Color {
        switch phase {
        case .ready, .recording, .transcribing:
            return loadedASRModelID == selectedASRModelID ? .green : .orange
        case .downloadingModel, .loading:
            if activeASRModelOperationID == selectedASRModelID {
                return .accentColor
            }
            return loadedASRModelID == selectedASRModelID ? .green : .orange
        case .error:
            return lastFailedASRModelID == selectedASRModelID ? .red : (loadedASRModelID == selectedASRModelID ? .green : .orange)
        case .needsModel:
            return .orange
        }
    }

    var modelStatusIcon: String {
        switch phase {
        case .ready, .recording, .transcribing:
            return loadedASRModelID == selectedASRModelID ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        case .downloadingModel, .loading:
            if activeASRModelOperationID == selectedASRModelID {
                return "arrow.down.circle.fill"
            }
            return loadedASRModelID == selectedASRModelID ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        case .error:
            return lastFailedASRModelID == selectedASRModelID ? "xmark.octagon.fill" : "checkmark.circle.fill"
        case .needsModel:
            return "exclamationmark.triangle.fill"
        }
    }

    var modelPrimaryActionTitle: String {
        if activeASRModelOperationID == selectedASRModelID {
            return phase == .loading ? "Loading…" : "Downloading…"
        }
        if loadedASRModelID == selectedASRModelID {
            return "Current"
        }
        if isModelInstalled {
            return "Use Model"
        }
        return "Download Model"
    }

    var modelPrimaryActionDetail: String {
        if loadedASRModelID == selectedASRModelID {
            return "Stored locally for offline dictation. Delete it if you want to reclaim disk space."
        }
        if activeASRModelOperationID == selectedASRModelID {
            return "Keep Suniye open while \(currentASRModelEntry.displayName) is downloaded, validated, and loaded."
        }
        if lastFailedASRModelID == selectedASRModelID, let lastFailedASRModelError, !lastFailedASRModelError.isEmpty {
            return "Last attempt failed. Retry setup for \(currentASRModelEntry.displayName) to use it for dictation."
        }
        return "Download \(currentASRModelEntry.displayName) to keep speech recognition fully local."
    }

    var modelLocationText: String {
        (try? modelManager.modelDirectoryURL(for: selectedASRModelID).path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) ?? "~/Library/Application Support/Suniye/models"
    }

    var asrModelBanner: ASRModelBannerState? {
        if let activeASRModelOperationID {
            let entry = ASRModelCatalog.entry(for: activeASRModelOperationID)
            switch phase {
            case .downloadingModel:
                return ASRModelBannerState(
                    title: "Downloading Model",
                    detail: "Installing \(entry.displayName) locally. Keep Suniye open until the files finish validating.",
                    tone: .info,
                    progress: downloadProgress
                )
            case .loading:
                return ASRModelBannerState(
                    title: "Loading Model",
                    detail: "Loading \(entry.displayName) into memory. The first load can take a moment.",
                    tone: .info,
                    progress: nil
                )
            default:
                break
            }
        }

        if let lastFailedASRModelID, let lastFailedASRModelError, !lastFailedASRModelError.isEmpty {
            return ASRModelBannerState(
                title: "Model Action Failed",
                detail: "\(ASRModelCatalog.entry(for: lastFailedASRModelID).displayName): \(lastFailedASRModelError)",
                tone: .error,
                progress: nil
            )
        }

        if phase == .error, let lastError, !lastError.isEmpty {
            return ASRModelBannerState(
                title: "Model Unavailable",
                detail: lastError,
                tone: .error,
                progress: nil
            )
        }

        return nil
    }

    func asrModelStatusText(for modelID: ASRModelID) -> String {
        if activeASRModelOperationID == modelID {
            switch phase {
            case .downloadingModel:
                return "Downloading"
            case .loading:
                return "Loading"
            default:
                break
            }
        }

        if loadedASRModelID == modelID && selectedASRModelID == modelID {
            return "Current"
        }

        if lastFailedASRModelID == modelID {
            return "Failed"
        }

        if modelManager.isInstalled(modelID) {
            return "Installed"
        }

        return "Missing"
    }

    func asrModelStatusColor(for modelID: ASRModelID) -> Color {
        if activeASRModelOperationID == modelID {
            return .accentColor
        }

        if loadedASRModelID == modelID && selectedASRModelID == modelID {
            return .green
        }

        if lastFailedASRModelID == modelID {
            return .red
        }

        if modelManager.isInstalled(modelID) {
            return MainWindowPalette.secondaryText
        }

        return .orange
    }

    func asrModelPrimaryActionTitle(for modelID: ASRModelID) -> String {
        if activeASRModelOperationID == modelID {
            return phase == .loading ? "Loading…" : "Downloading…"
        }

        if loadedASRModelID == modelID && selectedASRModelID == modelID {
            return "Current"
        }

        return modelManager.isInstalled(modelID) ? "Use Model" : "Download Model"
    }

    func asrModelCanPerformPrimaryAction(for modelID: ASRModelID) -> Bool {
        guard activeASRModelOperationID == nil else {
            return false
        }

        guard phase != .recording && phase != .transcribing else {
            return false
        }

        return !(loadedASRModelID == modelID && selectedASRModelID == modelID)
    }

    func asrModelSecondaryActionsEnabled(for modelID: ASRModelID) -> Bool {
        modelManager.isInstalled(modelID) && activeASRModelOperationID == nil && phase != .recording && phase != .transcribing
    }

    func asrModelProgressLabel(for modelID: ASRModelID) -> String? {
        guard activeASRModelOperationID == modelID else {
            return nil
        }

        switch phase {
        case .downloadingModel:
            return modelDownloadProgressLabel
        case .loading:
            return "Preparing the local recognizer."
        default:
            return nil
        }
    }

    func asrModelInstalledSizeText(for modelID: ASRModelID) -> String {
        ByteCountFormatter.string(fromByteCount: modelManager.installedByteCount(for: modelID), countStyle: .file)
    }

    func asrModelLocationText(for modelID: ASRModelID) -> String {
        (try? modelManager.modelDirectoryURL(for: modelID).path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) ?? "~/Library/Application Support/Suniye/models"
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
        if selectedInputDeviceID != nil {
            return preferredInputDeviceName ?? "Selected Microphone"
        }
        return audioRouteSnapshot?.effectiveInputName
            ?? availableInputDevices.first(where: \.isDefault)?.name
            ?? "System Default"
    }

    var effectiveInputDeviceStatusText: String {
        guard let route = audioRouteSnapshot else {
            if selectedInputDeviceID != nil {
                return "\(selectedInputDeviceName) is unavailable"
            }
            return "No microphone is available"
        }
        return "Using \(route.effectiveInputName) - \(route.inputTransport.title)"
    }

    var audioRouteWarningText: String? {
        if selectedInputDeviceID != nil, audioRouteSnapshot == nil {
            return "Reconnect this microphone or choose another input device."
        }
        guard let route = audioRouteSnapshot else {
            return nil
        }
        if route.inputTransport.isBluetooth {
            return "Bluetooth microphones put headphones into call-quality audio while dictating."
        }
        if route.requestedEchoCancellation, !route.effectiveEchoCancellation {
            return "Echo cancellation is unavailable for the current audio route."
        }
        return nil
    }

    var recommendedInputDevice: AudioInputDevice? {
        let effectiveID = audioRouteSnapshot?.effectiveInputDeviceID
        return availableInputDevices
            .filter { $0.isAvailable && $0.transport.isRecommendedPhysicalInput && $0.id != effectiveID }
            .sorted {
                if $0.isDefault != $1.isDefault {
                    return $0.isDefault
                }
                if $0.transport != $1.transport {
                    return $0.transport == .builtIn
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            .first
    }

    var isOnboardingSetupComplete: Bool {
        hasMicPermission && hasAccessibilityPermission && isModelInstalled && phase == .ready
    }

    var onboardingPracticeLevels: [Float] {
        switch floatingIndicatorState {
        case let .listening(levels, _):
            return levels
        default:
            return Self.defaultIndicatorLevels(level: 0.08)
        }
    }

    var isOnboardingPracticeRecording: Bool {
        activeOnboardingStep == .practice && phase == .recording
    }

    var isOnboardingPracticeProcessing: Bool {
        activeOnboardingStep == .practice && phase == .transcribing
    }

    var onboardingLocalModelStatusText: String? {
        guard activeOnboardingStep == .practice,
              llmEnabled,
              llmProvider == .localGemma else {
            return nil
        }

        switch localGemmaInstallState {
        case .downloading, .verifying, .failed, .unavailable:
            return localGemmaInstallStatusText
        case .notInstalled, .installed:
            return nil
        }
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
                    title: "Dictation model not installed",
                    detail: "Download \(currentASRModelEntry.displayName) to enable offline speech recognition.",
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
                    fixAction: .requestMicrophonePermission
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
                    fixAction: .requestAccessibilityPermission
                )
            )
        }

        if llmEnabled, needsAPIConfigurationForMagicFormat, let endpointValidationError = llmEndpointValidationError {
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

        if llmEnabled, needsAPIConfigurationForMagicFormat, let modelValidationError = llmModelValidationError {
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

        if llmEnabled && needsAPIConfigurationForMagicFormat && !hasLLMAPIKey {
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

        if llmEnabled && llmProvider == .appleFoundationModels && !appleMagicFormatAvailability.isAvailable {
            items.append(
                AttentionItem(
                    id: "apple-magic-format-unavailable",
                    title: "Magic Format Apple Intelligence unavailable",
                    detail: "\(appleMagicFormatAvailability.statusText) This only affects Magic Format cleanup.",
                    severity: .warning,
                    recommendedSection: .style
                )
            )
        }

        if llmEnabled && llmProvider == .localGemma && !localGemmaMagicFormatAvailability.isAvailable {
            items.append(
                AttentionItem(
                    id: "local-gemma-magic-format-unavailable",
                    title: "Magic Format local model unavailable",
                    detail: "\(localGemmaMagicFormatAvailability.statusText) This only affects Magic Format cleanup, not dictation.",
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
    private let soundFeedbackService: SoundFeedbackServiceProtocol
    private let floatingIndicatorController = FloatingIndicatorController()
    private let llmPostProcessor: LLMPostProcessor
    private let appleMagicFormatPostProcessor: AppleMagicFormatPostProcessor
    private let localGemmaMagicFormatPostProcessor: LocalGemmaMagicFormatPostProcessor
    private let magicFormatCoordinator: MagicFormatCoordinator
    private let localLLMModelManager: LocalLLMModelManagerProtocol
    private let llmSettingsStore: LLMSettingsStoreProtocol
    private let generalSettingsStore: GeneralSettingsStoreProtocol
    private let historyStore: HistoryStoreProtocol
    private let keychainService: KeychainServiceProtocol
    private let appUpdateController: AppUpdateControllerProtocol
    private let launchAtLoginService: LaunchAtLoginServiceProtocol
    private let diagnosticBundleService: DiagnosticBundleServiceProtocol
    private let issueReportUploadService: IssueReportUploadServiceProtocol
    private let currentAppVersionProvider: () -> AppVersion?
    private let nowProvider: () -> Date
    private let fileOpener: (URL) -> Bool
    private let issueReportDiagnosticsDestinationPicker: @MainActor (String) -> URL?
    private let temporaryFileCleanupScheduler: (URL) -> Void
    private let magicFormatSlowWarningDelaySeconds: TimeInterval
    private let runtimeServicesEnabled: Bool
    private let floatingIndicatorEnabled: Bool

    private struct DictationSessionContext {
        let id: UUID
        let source: RecordingSource
        let startedAt: Date
        let destination: DictationDestination
    }

    private enum ActiveDictationSession {
        case starting(DictationSessionContext)
        case recording(DictationSessionContext)
        case transcribing(DictationSessionContext)

        var context: DictationSessionContext {
            switch self {
            case let .starting(context), let .recording(context), let .transcribing(context):
                return context
            }
        }
    }

    private var activeDictationSession: ActiveDictationSession?
    private var activeAudioCaptureSessionID: UUID? { activeDictationSession?.context.id }
    private var activeRecordingSource: RecordingSource? { activeDictationSession?.context.source }
    private var recordingStart: Date? { activeDictationSession?.context.startedAt }
    private var overlayErrorResetTask: Task<Void, Never>?
    private var localGemmaDownloadTask: Task<Void, Never>?
    private var localGemmaDownloadID: UUID?
    private var isHydratingLLMSettings = false
    private var isHydratingGeneralSettings = false
    private var isHydratingHistory = false
    private let llmE2EMode: LLME2EMode
    private enum DictationDestination: Equatable {
        case systemInsertion
        case onboardingPractice
    }

    init(
        modelManager: ModelManagerProtocol = ModelManager(),
        transcriptionService: TranscriptionServiceProtocol = TranscriptionService(),
        audioCaptureService: AudioCaptureServiceProtocol = AudioCaptureService(),
        textInsertionService: TextInsertionServiceProtocol = TextInsertionService(),
        hotkeyService: HotkeyServiceProtocol = HotkeyService(),
        soundFeedbackService: SoundFeedbackServiceProtocol = SoundFeedbackService(),
        llmPostProcessor: LLMPostProcessor = OpenRouterPostProcessor(),
        appleMagicFormatPostProcessor: AppleMagicFormatPostProcessor = AppleFoundationModelsPostProcessor(),
        localGemmaMagicFormatPostProcessor: LocalGemmaMagicFormatPostProcessor? = nil,
        localLLMModelManager: LocalLLMModelManagerProtocol = LocalLLMModelManager(),
        llmSettingsStore: LLMSettingsStoreProtocol = LLMSettingsStore(),
        generalSettingsStore: GeneralSettingsStoreProtocol = GeneralSettingsStore(),
        historyStore: HistoryStoreProtocol = HistoryStore(),
        keychainService: KeychainServiceProtocol = KeychainService(),
        appUpdateController: AppUpdateControllerProtocol? = nil,
        launchAtLoginService: LaunchAtLoginServiceProtocol = LaunchAtLoginService(),
        diagnosticBundleService: DiagnosticBundleServiceProtocol = DiagnosticBundleService(),
        issueReportUploadService: IssueReportUploadServiceProtocol = IssueReportUploadService(),
        currentAppVersionProvider: @escaping () -> AppVersion? = { AppVersion.fromBundle() },
        nowProvider: @escaping () -> Date = Date.init,
        fileOpener: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
        issueReportDiagnosticsDestinationPicker: @escaping @MainActor (String) -> URL? = { defaultName in
            let panel = NSSavePanel()
            panel.nameFieldStringValue = defaultName
            panel.canCreateDirectories = true
            return panel.runModal() == .OK ? panel.url : nil
        },
        temporaryFileCleanupScheduler: @escaping (URL) -> Void = { url in
            Task.detached(priority: .utility) {
                try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
                try? FileManager.default.removeItem(at: url)
            }
        },
        magicFormatSlowWarningDelaySeconds: TimeInterval = 5,
        startServices: Bool = true,
        llmE2EMode: LLME2EMode? = nil
    ) {
        self.modelManager = modelManager
        self.transcriptionService = transcriptionService
        self.audioCaptureService = audioCaptureService
        self.textInsertionService = textInsertionService
        self.hotkeyService = hotkeyService
        self.soundFeedbackService = soundFeedbackService
        self.llmPostProcessor = llmPostProcessor
        self.appleMagicFormatPostProcessor = appleMagicFormatPostProcessor
        self.localLLMModelManager = localLLMModelManager
        let resolvedLocalGemmaPostProcessor = localGemmaMagicFormatPostProcessor ?? LocalGemmaPostProcessor(
            client: LocalGemmaLlamaCppClient(
                locator: LocalGemmaRuntimeLocator(modelManager: localLLMModelManager)
            )
        )
        self.localGemmaMagicFormatPostProcessor = resolvedLocalGemmaPostProcessor
        self.magicFormatCoordinator = MagicFormatCoordinator(
            apiPostProcessor: llmPostProcessor,
            applePostProcessor: appleMagicFormatPostProcessor,
            localGemmaPostProcessor: resolvedLocalGemmaPostProcessor
        )
        self.llmSettingsStore = llmSettingsStore
        self.generalSettingsStore = generalSettingsStore
        self.historyStore = historyStore
        self.keychainService = keychainService
        self.appUpdateController = appUpdateController ?? SparkleUpdateController()
        self.launchAtLoginService = launchAtLoginService
        self.diagnosticBundleService = diagnosticBundleService
        self.issueReportUploadService = issueReportUploadService
        self.currentAppVersionProvider = currentAppVersionProvider
        self.nowProvider = nowProvider
        self.fileOpener = fileOpener
        self.issueReportDiagnosticsDestinationPicker = issueReportDiagnosticsDestinationPicker
        self.temporaryFileCleanupScheduler = temporaryFileCleanupScheduler
        self.magicFormatSlowWarningDelaySeconds = magicFormatSlowWarningDelaySeconds
        self.runtimeServicesEnabled = startServices
        self.floatingIndicatorEnabled = startServices && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
        self.llmE2EMode = llmE2EMode ?? AppState.detectLLME2EMode(arguments: CommandLine.arguments)
        self.appUpdateController.onStateChange = { [weak self] in
            self?.refreshUpdateControllerState()
        }
        self.audioCaptureService.onEvent = { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch event {
                case let .levelsUpdated(sessionID, levels):
                    guard activeAudioCaptureSessionID == sessionID else { return }
                    handleAudioLevelsUpdate(levels)
                case let .devicesChanged(devices):
                    applyInputDevices(devices)
                    refreshAudioRouteSnapshot()
                case let .routeChanged(sessionID, route):
                    guard activeAudioCaptureSessionID == sessionID else { return }
                    audioRouteSnapshot = route
                case let .interrupted(sessionID, reason):
                    await handleAudioCaptureInterruption(sessionID: sessionID, reason: reason)
                }
            }
        }

        AppLogger.shared.log(.info, "app state init")
        loadHistory()
        loadGeneralSettings()
        loadLLMSettings()
        refreshUpdateControllerState()
        refreshInputDevices()
        refreshLaunchAtLoginStatus()
        refreshLLMKeyStatus()
        refreshLocalGemmaInstallState()

        if floatingIndicatorEnabled {
            floatingIndicatorController.onAction = { [weak self] in
                self?.toggleFloatingIndicatorRecording()
            }
            floatingIndicatorController.onPlacementChanged = { [weak self] placement in
                self?.handleFloatingIndicatorPlacementChanged(placement)
            }
            syncFloatingIndicatorPreferences()
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
        let bootstrapCandidates = orderedInstalledASRModelIDs()
        if !bootstrapCandidates.isEmpty {
            phase = .loading
            statusText = "Loading model..."
            do {
                let bootstrapModelID = try await loadFirstAvailableASRModel(from: bootstrapCandidates)
                if bootstrapModelID != selectedASRModelID {
                    selectedASRModelID = bootstrapModelID
                }
                phase = .ready
                statusText = "Ready"
                lastError = nil
            } catch {
                phase = .error
                lastError = "Model load failed: \(error.localizedDescription)"
                statusText = "Load failed"
            }
            activeASRModelOperationID = nil
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
            showMagicFormatOnboarding()
            return
        }

        activeOnboardingStep = hasSeenOnboardingWelcome ? .setup : .welcome
    }

    func advanceOnboarding() {
        switch activeOnboardingStep {
        case .welcome:
            hasSeenOnboardingWelcome = true
            if isOnboardingSetupComplete {
                showMagicFormatOnboarding()
            } else {
                activeOnboardingStep = .setup
            }
        case .setup:
            guard isOnboardingSetupComplete else {
                return
            }
            showMagicFormatOnboarding()
        case .magicFormat:
            skipMagicFormatDuringOnboarding()
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

    func confirmMagicFormatDuringOnboarding(_ provider: OnboardingMagicFormatProvider) {
        guard activeOnboardingStep == .magicFormat else {
            return
        }

        switch provider {
        case .localModel:
            guard canSelectLocalGemmaDuringOnboarding else {
                return
            }
            llmProvider = provider.magicFormatProvider
            startLocalGemmaDownload()
        case .appleIntelligence:
            guard appleMagicFormatAvailability.isAvailable else {
                return
            }
            llmProvider = provider.magicFormatProvider
        }

        llmEnabled = true
        completeCoreOnboarding()
    }

    func skipMagicFormatDuringOnboarding() {
        guard activeOnboardingStep == .magicFormat else {
            return
        }

        llmEnabled = false
        completeCoreOnboarding()
    }

    private func showMagicFormatOnboarding() {
        hasSeenOnboardingWelcome = true
        activeOnboardingStep = .magicFormat
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

    func handleAttentionFixAction(_ action: AttentionItemFixAction) {
        switch action {
        case .requestMicrophonePermission:
            requestMicrophonePermission()
        case .requestAccessibilityPermission:
            requestAccessibilityPermission()
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

    func openAppleIntelligenceSettings() {
        openSystemSettings(urlCandidates: [
            "x-apple.systempreferences:com.apple.Siri-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.speech",
            "x-apple.systempreferences:",
        ])
    }

    func refreshInputDevices() {
        applyInputDevices(audioCaptureService.availableInputDevices())
        refreshAudioRouteSnapshot()
    }

    private func applyInputDevices(_ devices: [AudioInputDevice]) {
        var visibleDevices = devices
        if let selectedInputDeviceID,
           let selected = devices.first(where: { $0.id == selectedInputDeviceID }),
           preferredInputDeviceName != selected.name {
            preferredInputDeviceName = selected.name
            if !isHydratingGeneralSettings {
                persistGeneralSettings()
            }
        }
        if let selectedInputDeviceID,
           !devices.contains(where: { $0.id == selectedInputDeviceID }) {
            visibleDevices.append(
                AudioInputDevice(
                    id: selectedInputDeviceID,
                    name: preferredInputDeviceName ?? "Selected Microphone",
                    isDefault: false,
                    transport: .other,
                    isAvailable: false
                )
            )
        }
        availableInputDevices = visibleDevices
    }

    func refreshAudioRouteSnapshot() {
        audioRouteSnapshot = try? audioCaptureService.routeSnapshot(
            preferredInputDeviceID: selectedInputDeviceID,
            echoCancellationEnabled: echoCancellationEnabled
        )
    }

    func useRecommendedInputDevice() {
        guard let recommendedInputDevice else {
            return
        }
        selectedInputDeviceID = recommendedInputDevice.id
    }

    func handleSystemWillSleep() async {
        await audioCaptureService.handleSystemSleep()
    }

    func handleSystemDidWake() {
        audioCaptureService.handleSystemWake()
        refreshInputDevices()
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
        guard needsAPIConfigurationForMagicFormat else {
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
        let config = MagicFormatCoordinator.makeAPIConfig(
            settings: currentLLMSettings(),
            apiKey: apiKey,
            endpointURL: endpointURL,
            modelId: modelId
        )
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

    func resetAppleMagicFormatPrompt() {
        llmAppleSystemPrompt = LLMDefaults.defaultAppleMagicFormatPrompt
    }

    func resetGemmaMagicFormatPrompt() {
        llmGemmaSystemPrompt = LLMDefaults.defaultGemmaMagicFormatPrompt
    }

    func resetBaseMagicFormatPrompt() {
        llmBaseSystemPrompt = LLMDefaults.defaultBaseSystemPrompt
    }

    func refreshLocalGemmaInstallState() {
        guard !localGemmaInstallState.isActive else {
            return
        }
        localGemmaInstallState = localLLMModelManager.installState(for: localLLMModelManager.preferredModelID)
    }

    func startLocalGemmaDownload() {
        guard canStartLocalGemmaDownload else {
            return
        }

        let modelID = localLLMModelManager.preferredModelID
        let entry = localGemmaCatalogEntry(for: modelID)
        localGemmaInstallState = .downloading(LocalLLMDownloadProgress(
            fractionCompleted: 0,
            downloadedBytes: 0,
            expectedBytes: entry.expectedSizeBytes
        ))
        clearMagicFormatSetupTestResult()

        let downloadID = UUID()
        localGemmaDownloadID = downloadID
        localGemmaDownloadTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                AppLogger.shared.log(.info, "local gemma download started model=\(entry.filename)")
                try await self.localLLMModelManager.downloadModel(modelID) { [weak self] progress in
                    Task { @MainActor in
                        guard let self,
                              self.localGemmaDownloadID == downloadID,
                              self.localGemmaInstallState.isActive else { return }
                        if progress.fractionCompleted >= 0.999 {
                            self.localGemmaInstallState = .verifying
                        } else {
                            self.localGemmaInstallState = .downloading(progress)
                        }
                    }
                }

                self.localGemmaDownloadID = nil
                self.localGemmaInstallState = self.localLLMModelManager.installState(for: modelID)
                self.magicFormatSetupTestResult = nil
                AppLogger.shared.log(.info, "local gemma download complete model=\(entry.filename)")
            } catch {
                self.localGemmaDownloadID = nil
                let message: String
                if Task.isCancelled || (error as NSError).code == NSURLErrorCancelled {
                    message = "Download canceled."
                    AppLogger.shared.log(.info, "local gemma download canceled model=\(entry.filename)")
                } else {
                    message = error.localizedDescription
                    AppLogger.shared.log(.error, "local gemma download failed model=\(entry.filename) error=\(message)")
                }
                self.localGemmaInstallState = .failed(message)
            }

            self.localGemmaDownloadTask = nil
        }
    }

    func cancelLocalGemmaDownload() {
        guard canCancelLocalGemmaDownload else {
            return
        }
        localGemmaDownloadTask?.cancel()
        localLLMModelManager.cancelDownload()
    }

    func deleteLocalGemmaModel() async {
        guard !localGemmaInstallState.isActive else {
            return
        }

        await localGemmaMagicFormatPostProcessor.stopRuntime()

        let modelID = localLLMModelManager.preferredModelID
        do {
            try localLLMModelManager.deleteModel(modelID)
            localGemmaInstallState = localLLMModelManager.installState(for: modelID)
            clearMagicFormatSetupTestResult()
            AppLogger.shared.log(.info, "local gemma model deleted")
        } catch {
            localGemmaInstallState = .failed(error.localizedDescription)
            AppLogger.shared.log(.error, "local gemma model delete failed error=\(error.localizedDescription)")
        }
    }

    func testLocalGemmaSetup() async {
        clearMagicFormatSetupTestResult()

        guard llmEnabled, usesLocalGemmaMagicFormatSettings else {
            return
        }

        guard localGemmaInstallState.isInstalled else {
            magicFormatSetupTestResult = MagicFormatSetupTestResult(
                message: "Download the local model first.",
                severity: .error
            )
            return
        }

        let requestID = magicFormatSetupTestRequestID
        isMagicFormatSetupTestInProgress = true
        let startTime = Date()
        let config = MagicFormatCoordinator.makeLocalGemmaConfig(settings: currentLLMSettings())

        defer {
            if requestID == magicFormatSetupTestRequestID {
                isMagicFormatSetupTestInProgress = false
            }
        }

        do {
            try await localGemmaMagicFormatPostProcessor.testSetup(config: config)
            guard requestID == magicFormatSetupTestRequestID else {
                AppLogger.shared.log(.info, "ignored stale local gemma setup test success")
                return
            }
            magicFormatSetupTestResult = MagicFormatSetupTestResult(
                message: "Local model works.",
                severity: .success
            )
            let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
            AppLogger.shared.log(.info, "local gemma setup test success latency_ms=\(latencyMs)")
        } catch {
            guard requestID == magicFormatSetupTestRequestID else {
                AppLogger.shared.log(.info, "ignored stale local gemma setup test failure")
                return
            }
            magicFormatSetupTestResult = MagicFormatSetupTestResult(
                message: localGemmaSetupTestMessage(for: error),
                severity: .error
            )
            let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
            AppLogger.shared.log(.warning, "local gemma setup test failed latency_ms=\(latencyMs) error=\(error.localizedDescription)")
        }
    }

    func copyRecentResult(_ result: RecentResult) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(result.text, forType: .string)
    }

    @discardableResult
    func copyLastTranscript() -> Bool {
        guard let text = lastTranscriptText else {
            return false
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return true
    }

    func deleteRecentResult(_ result: RecentResult) {
        recentResults.removeAll { $0.id == result.id }
    }

    func startModelDownload() {
        downloadASRModel(selectedASRModelID, autoSelect: true)
    }

    func deleteModel() {
        deleteASRModel(selectedASRModelID)
    }

    func openModelFolder() {
        openModelFolder(for: selectedASRModelID)
    }

    func performPrimaryASRAction(for modelID: ASRModelID) {
        guard asrModelCanPerformPrimaryAction(for: modelID) else {
            return
        }

        if modelManager.isInstalled(modelID) {
            selectASRModel(modelID)
        } else {
            downloadASRModel(modelID, autoSelect: true)
        }
    }

    func downloadASRModel(_ modelID: ASRModelID, autoSelect: Bool) {
        guard phase != .recording && phase != .transcribing && activeASRModelOperationID == nil else {
            return
        }

        let hadLoadedModel = loadedASRModelID != nil
        activeASRModelOperationID = modelID
        phase = .downloadingModel
        statusText = "Downloading model..."
        lastError = nil
        lastFailedASRModelID = nil
        lastFailedASRModelError = nil
        downloadProgress = 0
        modelDownloadStartedAt = nowProvider()

        Task {
            do {
                AppLogger.shared.log(.info, "model download started id=\(modelID.rawValue)")
                try await modelManager.downloadAndExtractModel(modelID) { [weak self] progress in
                    Task { @MainActor in
                        self?.downloadProgress = progress
                    }
                }

                phase = .loading
                statusText = "Validating model..."
                modelDownloadStartedAt = nil

                guard modelManager.isInstalled(modelID) else {
                    throw AppStateError.modelValidationFailed
                }

                if autoSelect {
                    do {
                        try await loadRecognizer(for: modelID)
                        selectedASRModelID = modelID
                        phase = .ready
                        statusText = "Ready"
                        lastError = nil
                        lastFailedASRModelID = nil
                        lastFailedASRModelError = nil
                        refreshOnboardingProgressIfNeeded()
                        AppLogger.shared.log(.info, "model download complete id=\(modelID.rawValue)")
                    } catch {
                        handleASRModelOperationFailure(
                            for: modelID,
                            error: error,
                            fallbackToReadyState: hadLoadedModel
                        )
                    }
                } else {
                    if hadLoadedModel {
                        phase = .ready
                        statusText = "Ready"
                    } else {
                        phase = .needsModel
                        statusText = "Model required"
                    }
                    lastFailedASRModelID = nil
                    lastFailedASRModelError = nil
                }
            } catch {
                handleASRModelOperationFailure(
                    for: modelID,
                    error: error,
                    fallbackToReadyState: hadLoadedModel
                )
                AppLogger.shared.log(.error, "model download failed id=\(modelID.rawValue) error=\(error.localizedDescription)")
            }

            activeASRModelOperationID = nil
            modelDownloadStartedAt = nil
        }
    }

    func selectASRModel(_ modelID: ASRModelID) {
        guard phase != .recording && phase != .transcribing && activeASRModelOperationID == nil else {
            return
        }
        guard loadedASRModelID != modelID else {
            return
        }

        if !modelManager.isInstalled(modelID) {
            downloadASRModel(modelID, autoSelect: true)
            return
        }

        let hadLoadedModel = loadedASRModelID != nil
        activeASRModelOperationID = modelID
        phase = .loading
        statusText = "Loading model..."
        lastError = nil
        lastFailedASRModelID = nil
        lastFailedASRModelError = nil

        Task {
            do {
                try await loadRecognizer(for: modelID)
                selectedASRModelID = modelID
                phase = .ready
                statusText = "Ready"
                lastError = nil
                lastFailedASRModelID = nil
                lastFailedASRModelError = nil
                AppLogger.shared.log(.info, "model switch complete id=\(modelID.rawValue)")
            } catch {
                handleASRModelOperationFailure(
                    for: modelID,
                    error: error,
                    fallbackToReadyState: hadLoadedModel
                )
            }
            activeASRModelOperationID = nil
        }
    }

    func deleteASRModel(_ modelID: ASRModelID) {
        guard phase != .recording && phase != .transcribing && activeASRModelOperationID == nil else {
            return
        }

        let isCurrentModel = selectedASRModelID == modelID || loadedASRModelID == modelID
        activeASRModelOperationID = modelID

        Task {
            do {
                try modelManager.deleteModel(modelID)
                if isCurrentModel {
                    await transcriptionService.unloadModel()
                    loadedASRModelID = nil
                }

                let fallbackCandidates = orderedInstalledASRModelIDs(excluding: Set([modelID]))
                if isCurrentModel, !fallbackCandidates.isEmpty {
                    phase = .loading
                    statusText = "Loading model..."
                    do {
                        let fallbackModelID = try await loadFirstAvailableASRModel(from: fallbackCandidates)
                        selectedASRModelID = fallbackModelID
                        phase = .ready
                        statusText = "Ready"
                        lastError = nil
                    } catch {
                        phase = .error
                        statusText = "Load failed"
                        lastError = "Model load failed: \(error.localizedDescription)"
                    }
                    activeASRModelOperationID = nil
                    if phase == .ready {
                        lastFailedASRModelID = nil
                        lastFailedASRModelError = nil
                    }
                } else if isCurrentModel {
                    selectedASRModelID = .parakeetV3
                    phase = .needsModel
                    statusText = "Model required"
                }

                downloadProgress = 0
                modelDownloadStartedAt = nil
                lastFailedASRModelID = nil
                lastFailedASRModelError = nil
                if !isCurrentModel {
                    lastError = nil
                }
                AppLogger.shared.log(.info, "model deleted id=\(modelID.rawValue)")
            } catch {
                phase = .error
                statusText = "Model delete failed"
                lastError = error.localizedDescription
                lastFailedASRModelID = modelID
                lastFailedASRModelError = error.localizedDescription
                AppLogger.shared.log(.error, "model delete failed id=\(modelID.rawValue) error=\(error.localizedDescription)")
            }
            activeASRModelOperationID = nil
        }
    }

    func openModelFolder(for modelID: ASRModelID) {
        do {
            let folder = try modelManager.modelDirectoryURL(for: modelID)
            NSWorkspace.shared.open(folder)
            AppLogger.shared.log(.info, "open model folder: \(folder.path)")
        } catch {
            AppLogger.shared.log(.error, "open model folder failed: \(error.localizedDescription)")
        }
    }

    func openMainWindow() {
        MainWindowController.shared.show(appState: self)
    }

    func openIssueReportWindow() {
        prepareIssueReportWindowPresentation()
        IssueReportWindowController.shared.show(appState: self)
    }

    func prepareIssueReportWindowPresentation() {
        issueReportDiagnosticsMessage = nil

        guard shouldResetIssueReportAfterClosedSubmission else {
            return
        }

        switch issueReportStatus {
        case .sent, .failed:
            resetIssueReportDraft()
        case .idle:
            shouldResetIssueReportAfterClosedSubmission = false
        case .preparing, .sending:
            break
        }
    }

    func issueReportWindowDidClose() {
        switch issueReportStatus {
        case .sent:
            resetIssueReportDraft()
        case .failed where shouldResetIssueReportAfterClosedSubmission:
            resetIssueReportDraft()
        case .preparing, .sending:
            shouldResetIssueReportAfterClosedSubmission = true
        case .idle, .failed:
            shouldResetIssueReportAfterClosedSubmission = false
        }
    }

    func resetIssueReportDraft() {
        issueReportType = .other
        issueReportTitle = ""
        issueReportDescription = ""
        issueReportContactEmail = ""
        issueReportIncludesDiagnostics = true
        issueReportStatus = .idle
        issueReportDiagnosticsMessage = nil
        shouldResetIssueReportAfterClosedSubmission = false
    }

    func submitIssueReport() async {
        guard !issueReportStatus.isBusy else {
            return
        }

        if let validationError = validateIssueReportDraft() {
            issueReportStatus = .failed(validationError)
            return
        }

        let reportId = IssueReportPayload.makeReportId()
        let payload = makeIssueReportPayload(reportId: reportId)
        var diagnosticsURL: URL?

        do {
            issueReportDiagnosticsMessage = nil
            if issueReportIncludesDiagnostics {
                issueReportStatus = .preparing
                diagnosticsURL = try await makeDiagnosticBundle(payload: payload)
            }

            issueReportStatus = .sending
            let response = try await issueReportUploadService.submit(
                payload: payload,
                diagnosticsURL: diagnosticsURL
            )
            issueReportStatus = .sent
            AppLogger.shared.log(.info, "issue report sent id=\(response.issueIdentifier) report_id=\(response.reportId)")
        } catch {
            issueReportStatus = .failed(issueReportErrorMessage(error))
            AppLogger.shared.log(.error, "issue report failed: \(error.localizedDescription)")
        }

        if let diagnosticsURL {
            try? FileManager.default.removeItem(at: diagnosticsURL)
        }
    }

    func reviewIssueReportDiagnostics() async {
        do {
            issueReportStatus = .preparing
            issueReportDiagnosticsMessage = nil
            let payload = makeIssueReportPayload(
                reportId: IssueReportPayload.makeReportId(),
                titleOverride: issueReportTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Diagnostic preview" : nil,
                descriptionOverride: issueReportDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Diagnostic preview for manual support." : nil,
                includeDiagnosticsOverride: true
            )
            let diagnosticsURL = try await makeDiagnosticBundle(payload: payload)
            if fileOpener(diagnosticsURL) {
                temporaryFileCleanupScheduler(diagnosticsURL)
                issueReportStatus = .idle
                issueReportDiagnosticsMessage = "Diagnostics opened for review."
            } else {
                try? FileManager.default.removeItem(at: diagnosticsURL)
                issueReportStatus = .failed("Could not open diagnostics.")
            }
        } catch {
            issueReportStatus = .failed(issueReportErrorMessage(error))
        }
    }

    func exportIssueReportDiagnostics() async {
        do {
            issueReportStatus = .preparing
            issueReportDiagnosticsMessage = nil
            let payload = makeIssueReportPayload(
                reportId: IssueReportPayload.makeReportId(),
                titleOverride: issueReportTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Diagnostic export" : nil,
                descriptionOverride: issueReportDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Diagnostic export for manual support." : nil,
                includeDiagnosticsOverride: true
            )
            let diagnosticsURL = try await makeDiagnosticBundle(payload: payload)
            defer {
                try? FileManager.default.removeItem(at: diagnosticsURL)
            }

            guard let destinationURL = issueReportDiagnosticsDestinationPicker(diagnosticsURL.lastPathComponent) else {
                issueReportStatus = .idle
                return
            }

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: diagnosticsURL, to: destinationURL)
            issueReportStatus = .idle
            issueReportDiagnosticsMessage = "Diagnostics exported."
        } catch {
            issueReportStatus = .failed(issueReportErrorMessage(error))
        }
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

    func resetFloatingIndicatorPlacement() {
        floatingIndicatorPlacement = nil
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

    func startUpdateController() {
        AppLogger.shared.log(.info, "sparkle updater start")
        appUpdateController.start()
        refreshUpdateControllerState()
    }

    func checkForUpdates() {
        AppLogger.shared.log(.info, "sparkle updater manual check")
        appUpdateController.checkForUpdates()
        refreshUpdateControllerState()
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        appUpdateController.automaticallyChecksForUpdates = enabled
        refreshUpdateControllerState()
        AppLogger.shared.log(.info, "sparkle automatic update checks set enabled=\(enabled)")
    }

    func setUpdateChannel(_ channel: UpdateChannel) {
        updateChannel = channel
        AppLogger.shared.log(.info, "sparkle update channel set channel=\(channel.rawValue)")
    }

    private func refreshUpdateControllerState() {
        canCheckForUpdates = appUpdateController.canCheckForUpdates
        automaticallyChecksForUpdates = appUpdateController.automaticallyChecksForUpdates
    }

    private func applyUpdateChannelToController() {
        appUpdateController.updateChannel = updateChannel
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

        return await magicFormatCoordinator.polish(
            input: input,
            rawText: rawText,
            request: MagicFormatCoordinator.PolishRequest(
                requestedProvider: llmProvider,
                settings: currentLLMSettings(),
                hasAPIKey: hasLLMAPIKey,
                appleAvailability: appleMagicFormatAvailability,
                localGemmaAvailability: localGemmaMagicFormatAvailability,
                readAPIKey: { [keychainService] in
                    try? keychainService.getLLMKey()
                },
                onAPIKeyReadFailed: { [weak self] in
                    self?.refreshLLMKeyStatus()
                },
                startSlowWarning: { [weak self] in
                    self?.startMagicFormatSlowWarningTask() ?? Task {}
                },
                setStatusText: { [weak self] text in
                    self?.statusText = text
                },
                setProcessingMessage: { [weak self] message in
                    guard let self, case .processing = self.floatingIndicatorState else {
                        return
                    }
                    self.setFloatingIndicatorState(.processing(message: message))
                }
            )
        )
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
            setFloatingIndicatorState(.processing())
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

    private func orderedInstalledASRModelIDs(excluding excludedModelIDs: Set<ASRModelID> = []) -> [ASRModelID] {
        let installedModelIDs = Set(modelManager.installedModels())
        var orderedModelIDs: [ASRModelID] = []

        if installedModelIDs.contains(selectedASRModelID), !excludedModelIDs.contains(selectedASRModelID) {
            orderedModelIDs.append(selectedASRModelID)
        }

        for modelID in modelManager.fallbackOrder
        where installedModelIDs.contains(modelID)
            && !excludedModelIDs.contains(modelID)
            && !orderedModelIDs.contains(modelID) {
            orderedModelIDs.append(modelID)
        }

        return orderedModelIDs
    }

    private func loadFirstAvailableASRModel(from candidateModelIDs: [ASRModelID]) async throws -> ASRModelID {
        guard !candidateModelIDs.isEmpty else {
            throw AppStateError.modelValidationFailed
        }

        var lastError: Error?

        for modelID in candidateModelIDs {
            activeASRModelOperationID = modelID
            do {
                try await loadRecognizer(for: modelID)
                return modelID
            } catch {
                lastError = error
                AppLogger.shared.log(
                    .warning,
                    "model load fallback failed id=\(modelID.rawValue) error=\(error.localizedDescription)"
                )
            }
        }

        throw lastError ?? AppStateError.modelValidationFailed
    }

    private func handleASRModelOperationFailure(for modelID: ASRModelID, error: Error, fallbackToReadyState: Bool) {
        downloadProgress = 0
        lastFailedASRModelID = modelID
        lastFailedASRModelError = error.localizedDescription

        if fallbackToReadyState, loadedASRModelID != nil {
            phase = .ready
            statusText = "Ready"
            lastError = nil
            return
        }

        phase = .error
        lastError = error.localizedDescription
        statusText = "Download failed"
    }

    private func loadRecognizer(for modelID: ASRModelID) async throws {
        let config = try modelManager.makeRecognizerConfig(for: modelID)
        try await transcriptionService.loadModel(config: config)
        loadedASRModelID = modelID
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
            playSoundFeedback(.error)
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
            playSoundFeedback(.error)
            showTransientIndicatorError("Enable Accessibility for dictation")
            return
        }
        await startRecording(trigger: trigger)
    }

    private func startRecording(trigger: RecordingSource) async {
        guard phase == .ready else {
            return
        }

        let sessionID = UUID()
        let context = DictationSessionContext(
            id: sessionID,
            source: trigger,
            startedAt: Date(),
            destination: currentDictationDestination
        )
        activeDictationSession = .starting(context)
        phase = .recording
        statusText = "Recording"
        overlayErrorResetTask?.cancel()
        overlayErrorResetTask = nil
        if context.destination == .onboardingPractice {
            onboardingPracticeText = ""
            onboardingPracticeResult = nil
        }
        setFloatingIndicatorState(.listening(levels: Self.defaultIndicatorLevels(level: 0), source: trigger))

        do {
            let session = try await audioCaptureService.startCapture(
                sessionID: sessionID,
                preferredInputDeviceID: selectedInputDeviceID,
                echoCancellationEnabled: echoCancellationEnabled
            )
            guard activeAudioCaptureSessionID == sessionID else {
                await audioCaptureService.cancelCapture(sessionID: sessionID, reason: nil)
                return
            }
            if case .some(.starting) = activeDictationSession {
                activeDictationSession = .recording(context)
            }
            audioRouteSnapshot = session.route
            AppLogger.shared.log(.info, "recording started session=\(sessionID.uuidString) \(session.route.privacySafeLogValue)")
        } catch {
            guard activeAudioCaptureSessionID == sessionID else {
                return
            }
            clearActiveDictationSession(sessionID: sessionID)
            phase = .ready
            lastError = "Audio start failed: \(error.localizedDescription)"
            statusText = "Ready"
            AppLogger.shared.log(.error, "audio start failed: \(error.localizedDescription)")
            playSoundFeedback(.error)
            showTransientIndicatorError(error.localizedDescription)
        }
    }

    private func stopRecordingAndTranscribe(trigger: RecordingSource) async {
        guard phase == .recording else {
            return
        }
        guard let context = activeDictationSession?.context, context.source == trigger else {
            return
        }
        let sessionID = context.id

        activeDictationSession = .transcribing(context)
        phase = .transcribing
        statusText = "Transcribing..."
        setFloatingIndicatorState(.processing())

        let captured = await audioCaptureService.stopCapture(sessionID: sessionID)
        guard let context = activeDictationSession?.context, context.id == sessionID else {
            return
        }
        let samples = captured.samples
        let sampleRate = captured.sampleRate
        let duration = Date().timeIntervalSince(context.startedAt)
        let destination = context.destination
        AppLogger.shared.log(.info, "dictation stop samples=\(samples.count) sr=\(sampleRate) duration=\(String(format: "%.2f", duration))")

        guard captured.outcome == .complete else {
            handleAudioCaptureFailure(captured.outcome, destination: destination)
            return
        }

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
            var didCompleteDictation = false

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
                    didCompleteDictation = true
                }

                if shouldSubmit {
                    if !finalText.isEmpty {
                        try? await Task.sleep(nanoseconds: 120_000_000)
                    }
                    try textInsertionService.submitActiveInput()
                    AppLogger.shared.log(.info, "submit command executed")
                    didCompleteDictation = true
                }

                if finalText.isEmpty && !shouldSubmit {
                    AppLogger.shared.log(.warning, "transcription returned empty text samples=\(samples.count) sr=\(sampleRate)")
                    playSoundFeedback(.error)
                }
            case .onboardingPractice:
                onboardingPracticeText = finalText
                if finalText.isEmpty {
                    let message = rawText.isEmpty
                        ? "No speech detected. Try a short phrase."
                        : "Practice mode captured audio, but there was no text to preview."
                    onboardingPracticeResult = OnboardingPracticeResult(message: message, severity: .error)
                    AppLogger.shared.log(.warning, "onboarding practice produced empty text")
                    playSoundFeedback(.error)
                } else {
                    onboardingPracticeResult = OnboardingPracticeResult(
                        message: "Captured locally. You can finish onboarding whenever you're ready.",
                        severity: .success
                    )
                    AppLogger.shared.log(.info, "onboarding practice transcription complete words=\(wordCount)")
                    didCompleteDictation = true
                }
            }
            if didCompleteDictation {
                playSoundFeedback(.transcriptionSucceeded)
            }
            clearActiveDictationSession(sessionID: sessionID)
            lastError = nil
            phase = .ready
            statusText = "Ready"
            setFloatingIndicatorState(.idle)
        } catch {
            clearActiveDictationSession(sessionID: sessionID)
            lastError = "Transcription failed: \(error.localizedDescription)"
            if destination == .onboardingPractice {
                onboardingPracticeText = ""
                onboardingPracticeResult = OnboardingPracticeResult(
                    message: error.localizedDescription,
                    severity: .error
                )
            }
            phase = .ready
            statusText = "Ready"
            AppLogger.shared.log(.error, "transcription failed: \(error.localizedDescription)")
            playSoundFeedback(.error)
            showTransientIndicatorError("Transcription failed")
        }
    }

    private func handleAudioCaptureInterruption(
        sessionID: UUID,
        reason: AudioCaptureInterruption
    ) async {
        guard let context = activeDictationSession?.context, context.id == sessionID else {
            return
        }
        if reason == .maximumDurationReached {
            await stopRecordingAndTranscribe(trigger: activeRecordingSource ?? .manual)
            return
        }
        await audioCaptureService.cancelCapture(sessionID: sessionID, reason: reason)
        guard activeAudioCaptureSessionID == sessionID else {
            return
        }
        handleAudioCaptureFailure(.interrupted(reason), destination: context.destination)
    }

    private func handleAudioCaptureFailure(
        _ outcome: AudioCaptureOutcome,
        destination: DictationDestination
    ) {
        let message = outcome.userMessage ?? "Audio capture was interrupted. Try again."
        clearActiveDictationSession()
        lastError = "Audio capture failed: \(message)"
        if destination == .onboardingPractice {
            onboardingPracticeText = ""
            onboardingPracticeResult = OnboardingPracticeResult(message: message, severity: .error)
        }
        phase = .ready
        statusText = "Ready"
        AppLogger.shared.log(.warning, "audio capture rejected outcome=\(String(describing: outcome))")
        playSoundFeedback(.error)
        showTransientIndicatorError(message)
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
        preferredInputDeviceName = settings.preferredInputDeviceName
        autoSubmitEnabled = settings.autoSubmitEnabled
        hotkeyConfiguration = settings.hotkeyConfiguration
        echoCancellationEnabled = settings.echoCancellationEnabled
        soundFeedbackEnabled = settings.soundFeedbackEnabled
        hideFloatingIndicatorWhenIdle = settings.hideFloatingIndicatorWhenIdle
        floatingIndicatorPlacement = settings.floatingIndicatorPlacement
        selectedASRModelID = settings.selectedASRModelID
        updateChannel = settings.updateChannel
        hasSeenOnboardingWelcome = settings.hasSeenOnboardingWelcome ?? false
        hasCompletedCoreOnboarding = settings.hasCompletedCoreOnboarding ?? false
        isHydratingGeneralSettings = false
        applyUpdateChannelToController()
        normalizeOnboardingSettingsIfNeeded(loadedSettings: settings)
    }

    private func persistGeneralSettings() {
        generalSettingsStore.save(currentGeneralSettings())
    }

    private func currentGeneralSettings() -> GeneralSettings {
        GeneralSettings(
            preferredInputDeviceID: selectedInputDeviceID,
            preferredInputDeviceName: preferredInputDeviceName,
            autoSubmitEnabled: autoSubmitEnabled,
            hotkeyConfiguration: hotkeyConfiguration,
            echoCancellationEnabled: echoCancellationEnabled,
            soundFeedbackEnabled: soundFeedbackEnabled,
            hideFloatingIndicatorWhenIdle: hideFloatingIndicatorWhenIdle,
            floatingIndicatorPlacement: floatingIndicatorPlacement,
            hasSeenOnboardingWelcome: hasSeenOnboardingWelcome,
            hasCompletedCoreOnboarding: hasCompletedCoreOnboarding,
            selectedASRModelID: selectedASRModelID,
            updateChannel: updateChannel
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
        let providerPromptMigration = Self.legacyProviderPromptMigration(
            settings: settings,
            mergedPrompt: mergedPrompt
        )
        let shouldMigrateProviderPrompts = providerPromptMigration != nil
            && (!settings.hasExplicitAppleSystemPrompt || !settings.hasExplicitGemmaSystemPrompt)
        let shouldNormalizeHiddenSettings = settings.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || settings.timeoutSeconds != LLMDefaults.defaultTimeoutSeconds
            || settings.maxTokens != LLMDefaults.defaultMaxTokens
            || shouldMigrateProviderPrompts
        llmEnabled = settings.isEnabled
        llmProvider = settings.provider
        llmSelectedModelPreset = settings.selectedModelPreset
        llmCustomModelId = settings.customModelId
        llmEndpointURLString = settings.endpointURLString
        llmBaseSystemPrompt = mergedPrompt
        llmAppleSystemPrompt = Self.loadedProviderPrompt(
            explicitPrompt: settings.composedAppleSystemPrompt,
            hasExplicitPrompt: settings.hasExplicitAppleSystemPrompt,
            defaultPrompt: LLMDefaults.defaultAppleMagicFormatPrompt,
            migrationPrompt: providerPromptMigration
        )
        llmGemmaSystemPrompt = Self.loadedProviderPrompt(
            explicitPrompt: settings.composedGemmaSystemPrompt,
            hasExplicitPrompt: settings.hasExplicitGemmaSystemPrompt,
            defaultPrompt: LLMDefaults.defaultGemmaMagicFormatPrompt,
            migrationPrompt: providerPromptMigration
        )
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
            provider: llmProvider,
            selectedModelPreset: llmSelectedModelPreset,
            customModelId: llmCustomModelId,
            endpointURLString: llmEndpointURLString,
            baseSystemPrompt: llmBaseSystemPrompt,
            appleSystemPrompt: llmAppleSystemPrompt,
            gemmaSystemPrompt: llmGemmaSystemPrompt,
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

    private static func legacyProviderPromptMigration(settings: LLMSettings, mergedPrompt: String) -> String? {
        let normalizedBase = settings.baseSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let visiblePrompt = normalizedBase.isEmpty ? LLMDefaults.defaultBaseSystemPrompt : normalizedBase
        let normalizedExtra = settings.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let legacyPromptWasCustomized = !normalizedExtra.isEmpty || visiblePrompt != LLMDefaults.defaultBaseSystemPrompt
        return legacyPromptWasCustomized ? mergedPrompt : nil
    }

    private static func loadedProviderPrompt(
        explicitPrompt: String,
        hasExplicitPrompt: Bool,
        defaultPrompt: String,
        migrationPrompt: String?
    ) -> String {
        guard !hasExplicitPrompt else {
            let normalized = explicitPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.isEmpty ? defaultPrompt : normalized
        }
        return migrationPrompt ?? defaultPrompt
    }

    private func localGemmaCatalogEntry(for modelID: LocalLLMModelID) -> LocalLLMModelCatalogEntry {
        localLLMModelManager.catalog.first { $0.id == modelID } ?? LocalLLMModelCatalog.entry(for: modelID)
    }

    private func validateIssueReportDraft() -> String? {
        if issueReportTitle.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 {
            return "Add a short title for the issue."
        }
        if issueReportDescription.trimmingCharacters(in: .whitespacesAndNewlines).count < 10 {
            return "Describe what happened in a little more detail."
        }
        if let issueReportContactEmailValidationError {
            return issueReportContactEmailValidationError
        }
        return nil
    }

    private func makeIssueReportPayload(
        reportId: String,
        titleOverride: String? = nil,
        descriptionOverride: String? = nil,
        includeDiagnosticsOverride: Bool? = nil
    ) -> IssueReportPayload {
        let version = currentAppVersionProvider()
        let entry = currentASRModelEntry
        return IssueReportPayload(
            schemaVersion: 1,
            reportId: reportId,
            issueType: issueReportType,
            title: titleOverride ?? issueReportTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            description: descriptionOverride ?? issueReportDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            contactEmail: normalizedIssueReportEmail,
            includeDiagnostics: includeDiagnosticsOverride ?? issueReportIncludesDiagnostics,
            app: .init(
                version: version?.displayString ?? "Unknown",
                build: version?.build.map(String.init),
                macOSVersion: ProcessInfo.processInfo.suniyeOperatingSystemVersionString,
                architecture: ProcessInfo.suniyeArchitecture
            ),
            state: .init(
                phase: phase.rawValue,
                lastError: lastError.map { DiagnosticRedactor().redact($0) },
                updateStatus: "sparkle-\(updateChannel.rawValue)"
            ),
            permissions: .init(
                microphone: hasMicPermission,
                accessibility: hasAccessibilityPermission
            ),
            model: .init(
                selectedModelId: selectedASRModelID.rawValue,
                selectedModelName: entry.displayName,
                selectedModelInstalled: modelManager.isInstalled(selectedASRModelID),
                installedModelIds: modelManager.installedModels().map(\.rawValue)
            ),
            settings: .init(
                autoSubmitEnabled: autoSubmitEnabled,
                echoCancellationEnabled: echoCancellationEnabled,
                soundFeedbackEnabled: soundFeedbackEnabled,
                hideFloatingIndicatorWhenIdle: hideFloatingIndicatorWhenIdle,
                llmEnabled: llmEnabled,
                llmHasAPIKey: hasLLMAPIKey
            )
        )
    }

    private var normalizedIssueReportEmail: String? {
        let email = issueReportContactEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        return email.isEmpty ? nil : email
    }

    private func makeDiagnosticBundle(payload: IssueReportPayload) async throws -> URL {
        let logFileURL = AppLogger.shared.logFileURL
        let rotatedLogFileURL = logFileURL.deletingLastPathComponent().appendingPathComponent("app.log.1")
        return try await diagnosticBundleService.makeBundle(
            request: DiagnosticBundleRequest(
                payload: payload,
                createdAt: nowProvider(),
                logFileURL: logFileURL,
                rotatedLogFileURL: FileManager.default.fileExists(atPath: rotatedLogFileURL.path) ? rotatedLogFileURL : nil
            )
        )
    }

    private func issueReportErrorMessage(_ error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription, !localized.isEmpty {
            return localized
        }
        return error.localizedDescription
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

    private func localGemmaSetupTestMessage(for error: Error) -> String {
        if let llmError = error as? LLMPostProcessorError {
            switch llmError {
            case .timeout:
                return "Local model took too long to respond."
            case .invalidConfiguration:
                return localGemmaMagicFormatAvailability.statusText
            case .provider, .malformedResponse, .emptyOutput:
                return "Local model responded, but not in a compatible format."
            case .network:
                return "Couldn't reach the local model server."
            case .unauthorized:
                return "Local model rejected the local authorization token."
            }
        }

        return error.localizedDescription
    }

    private func setFloatingIndicatorState(_ state: FloatingIndicatorState) {
        floatingIndicatorState = state
        guard floatingIndicatorEnabled else { return }
        floatingIndicatorController.update(state)
    }

    private func startMagicFormatSlowWarningTask() -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            guard let delaySeconds = self?.magicFormatSlowWarningDelaySeconds else { return }
            let nanoseconds = UInt64(max(0, delaySeconds) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard let self, !Task.isCancelled else { return }
            guard case .processing = self.floatingIndicatorState else { return }
            self.setFloatingIndicatorState(.processing(message: "Magic Format is taking longer than usual."))
        }
    }

    private func playSoundFeedback(_ event: SoundFeedbackEvent) {
        guard soundFeedbackEnabled else { return }
        soundFeedbackService.play(event)
    }

    private func syncFloatingIndicatorPreferences() {
        guard floatingIndicatorEnabled else { return }
        floatingIndicatorController.configure(
            hideWhenIdle: hideFloatingIndicatorWhenIdle,
            placement: floatingIndicatorPlacement
        )
    }

    func handleFloatingIndicatorPlacementChanged(_ placement: FloatingIndicatorPlacement?) {
        floatingIndicatorPlacement = placement
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
            return .processing()
        case .needsModel, .downloadingModel, .loading, .ready, .error:
            return .idle
        }
    }

    private var currentDictationDestination: DictationDestination {
        activeOnboardingStep == .practice ? .onboardingPractice : .systemInsertion
    }

    private func clearActiveDictationSession(sessionID: UUID? = nil) {
        guard sessionID == nil || activeAudioCaptureSessionID == sessionID else {
            return
        }
        activeDictationSession = nil
    }

    private var isOnboardingBlockingRecordingStart: Bool {
        activeOnboardingStep == .welcome
            || activeOnboardingStep == .setup
            || activeOnboardingStep == .magicFormat
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
        showMagicFormatOnboarding()
    }

    private func handleAudioLevelsUpdate(_ levels: [Float]) {
        guard case let .listening(_, source) = floatingIndicatorState else {
            return
        }
        setFloatingIndicatorState(.listening(levels: levels, source: source))
    }

    private static func defaultIndicatorLevels(level: Float, count: Int = AudioLevelMeter.bandCount) -> [Float] {
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

enum AppStateError: LocalizedError {
    case modelValidationFailed

    var errorDescription: String? {
        switch self {
        case .modelValidationFailed:
            return "Model files are missing after extraction."
        }
    }
}
