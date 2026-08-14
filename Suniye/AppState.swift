import AppKit
import AVFoundation
import Carbon
import Foundation
import Observation
import SuniyeAnalytics
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
            analytics.track(.featureToggled(feature: .autoSubmit, enabled: autoSubmitEnabled))
            onStateChange?()
        }
    }
    var echoCancellationEnabled = false {
        didSet {
            guard !isHydratingGeneralSettings else {
                return
            }
            persistGeneralSettings()
            analytics.track(.featureToggled(feature: .echoCancellation, enabled: echoCancellationEnabled))
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
            analytics.track(.featureToggled(feature: .soundFeedback, enabled: soundFeedbackEnabled))
            onStateChange?()
        }
    }
    /// Opt-out toggle for anonymous usage analytics (default on).
    var shareAnalyticsEnabled = true {
        didSet {
            guard !isHydratingGeneralSettings else {
                return
            }
            guard oldValue != shareAnalyticsEnabled else {
                return
            }
            persistGeneralSettings()
            analytics.setEnabled(shareAnalyticsEnabled)
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
    var liveTranscriptionPreviewEnabled = false {
        didSet {
            guard !isHydratingGeneralSettings else {
                return
            }
            guard oldValue != liveTranscriptionPreviewEnabled else {
                return
            }
            if !liveTranscriptionPreviewEnabled {
                // Take effect immediately when toggled off mid-recording;
                // re-enabling applies from the next recording.
                stopLivePreview()
            }
            persistGeneralSettings()
            onStateChange?()
        }
    }
    /// Kill switch for the Permiso drag-to-grant Accessibility overlay.
    /// When false, the Accessibility buttons fall back to the System Settings deep-link.
    var accessibilityDragHelperEnabled = true {
        didSet {
            guard !isHydratingGeneralSettings else {
                return
            }
            guard oldValue != accessibilityDragHelperEnabled else {
                return
            }
            persistGeneralSettings()
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
            guard oldValue != hotkeyConfiguration else {
                return
            }
            guard hotkeyConfiguration != pasteLastTranscriptHotkeyConfiguration else {
                hotkeyConfiguration = oldValue
                hotkeyValidationMessage = "Hold to Dictate and Paste Last Transcript must use different shortcuts."
                onStateChange?()
                return
            }
            hotkeyValidationMessage = nil
            // Collision policy lives at this settings boundary: the Edit Mode slot always yields.
            if editModeHotkeyConfiguration == hotkeyConfiguration {
                editModeHotkeyConfiguration = nil
                AppLogger.shared.log(.warning, "edit mode hotkey cleared: matched new dictation hotkey")
                showTransientIndicatorError("Edit Mode shortcut cleared: it matched dictation")
            }
            persistGeneralSettings()
            if runtimeServicesEnabled {
                wireHotkey()
            }
            onStateChange?()
        }
    }
    private(set) var pasteLastTranscriptHotkeyConfiguration: HotkeyConfiguration = .pasteLastTranscriptDefault {
        didSet {
            guard !isHydratingGeneralSettings, oldValue != pasteLastTranscriptHotkeyConfiguration else {
                return
            }
            guard pasteLastTranscriptHotkeyConfiguration.isModifiedKeyCombo else {
                pasteLastTranscriptHotkeyConfiguration = oldValue
                hotkeyValidationMessage = "Paste Last Transcript requires at least one modifier key."
                onStateChange?()
                return
            }
            guard pasteLastTranscriptHotkeyConfiguration != hotkeyConfiguration else {
                pasteLastTranscriptHotkeyConfiguration = oldValue
                hotkeyValidationMessage = "Hold to Dictate and Paste Last Transcript must use different shortcuts."
                onStateChange?()
                return
            }
            guard pasteLastTranscriptHotkeyConfiguration != editModeHotkeyConfiguration else {
                pasteLastTranscriptHotkeyConfiguration = oldValue
                hotkeyValidationMessage = "Paste Last Transcript and Edit Mode must use different shortcuts."
                onStateChange?()
                return
            }
            hotkeyValidationMessage = nil
            persistGeneralSettings()
            if runtimeServicesEnabled {
                wireHotkey()
            }
            if isShowingInsertionRecoveryWarning {
                showInsertionRecoveryWarning()
            }
            onStateChange?()
        }
    }
    var hotkeyValidationMessage: String?
    var editModeHotkeyConfiguration: HotkeyConfiguration? {
        didSet {
            guard !isHydratingGeneralSettings, oldValue != editModeHotkeyConfiguration else {
                return
            }
            if let editModeHotkeyConfiguration {
                if editModeHotkeyConfiguration == hotkeyConfiguration {
                    self.editModeHotkeyConfiguration = oldValue == hotkeyConfiguration ? nil : oldValue
                    AppLogger.shared.log(.warning, "edit mode hotkey rejected: matches dictation hotkey")
                    showTransientIndicatorError("Edit Mode shortcut must differ from dictation")
                    return
                }
                if editModeHotkeyConfiguration == pasteLastTranscriptHotkeyConfiguration {
                    self.editModeHotkeyConfiguration = oldValue == pasteLastTranscriptHotkeyConfiguration ? nil : oldValue
                    hotkeyValidationMessage = "Paste Last Transcript and Edit Mode must use different shortcuts."
                    AppLogger.shared.log(.warning, "edit mode hotkey rejected: matches paste last transcript hotkey")
                    showTransientIndicatorError("Edit Mode shortcut must differ from Paste Last Transcript")
                    return
                }
            }
            hotkeyValidationMessage = nil
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
    /// Single persisted onboarding position. Private setter: every transition
    /// goes through the state-machine funcs so persistence, analytics, and the
    /// active step can never disagree.
    private(set) var onboardingProgress: OnboardingProgress = .notStarted {
        didSet {
            guard !isHydratingGeneralSettings, oldValue != onboardingProgress else {
                return
            }
            persistGeneralSettings()
            onStateChange?()
        }
    }

    /// Legacy accessors kept for read sites (diagnostics, tests).
    var hasSeenOnboardingWelcome: Bool { onboardingProgress != .notStarted }
    var hasCompletedCoreOnboarding: Bool { onboardingProgress.isFinished }

    var activeOnboardingStep: OnboardingStep? {
        didSet {
            guard oldValue != activeOnboardingStep else {
                return
            }
            if activeOnboardingStep != .speak {
                onboardingPracticeResult = nil
            }
            trackOnboardingStepShownIfNeeded()
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
    /// The user has completed at least one successful practice dictation this
    /// onboarding run (gates the Speak screen's Continue button).
    private(set) var onboardingPracticeSucceeded = false
    /// 1-based practice attempt counter for this onboarding run; drives the
    /// "Continue anyway" escape hatch and the practice-result analytics.
    private(set) var onboardingPracticeAttempts = 0
    /// User-facing reason the Get Started preflight refused to start (disk space).
    var onboardingDiskSpaceMessage: String?
    /// The Permiso overlay timed out with no grant — surface a visible hint
    /// instead of the old silent disappearance.
    private(set) var accessibilityAssistTimedOut = false
    /// macOS reset a previously-working Accessibility grant (app update / TCC
    /// reset). The drag overlay would mislead ("drag Suniye in" while it is
    /// already listed), so the UI shows toggle-off-and-on copy instead.
    private(set) var accessibilityGrantLikelyStale = false

    /// Per-run dedupe of onboarding_step emissions (relaunch resume re-fires
    /// once per run with resumed=true; navigation within a run fires once per step).
    @ObservationIgnored private var onboardingStepsTracked: Set<OnboardingStep> = []
    @ObservationIgnored private var onboardingResumedPending = false
    @ObservationIgnored private var onboardingStartedAt: Date?
    @ObservationIgnored private var hasTrackedMagicFormatNudgeShown = false
    @ObservationIgnored private var firstLaunchRecorded = false
    @ObservationIgnored private var lastKnownAccessibilityGranted = false
    private var magicFormatNudgeDismissed = false {
        didSet {
            guard !isHydratingGeneralSettings, oldValue != magicFormatNudgeDismissed else {
                return
            }
            persistGeneralSettings()
            onStateChange?()
        }
    }

    var hasMicPermission = false
    /// True when the mic authorization is `.denied`/`.restricted` — the system
    /// prompt can never re-appear, so Enable buttons must become Open Settings.
    var hasMicPermissionBeenDenied = false
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
        didSet {
            persistLLMSettings()
            // Adoption signal for the flagship feature: fires on any real toggle
            // (settings page, nudge CTA) but never during settings hydration.
            if !isHydratingLLMSettings, oldValue != llmEnabled {
                analytics.track(.featureToggled(feature: .magicFormat, enabled: llmEnabled))
            }
        }
    }
    var llmProvider: MagicFormatProvider = .automatic {
        didSet { persistLLMSettings() }
    }
    var llmSelectedModelPreset: LLMModelPreset = .gemini25Flash {
        didSet { persistLLMSettings() }
    }
    var localModelKeepAlive: LocalLLMKeepAlive = .tenMinutes {
        didSet { persistLLMSettings() }
    }
    var llmCustomModelId = "" {
        didSet { persistLLMSettings() }
    }
    var llmEndpointURLString = LLMDefaults.defaultEndpointURLString {
        didSet { persistLLMSettings() }
    }
    var llmBaseSystemPrompt = LLMDefaults.defaultBaseSystemPrompt {
        didSet {
            persistLLMSettings()
            saveProviderPromptFile(.api, content: llmBaseSystemPrompt)
        }
    }
    var llmAppleSystemPrompt = LLMDefaults.defaultAppleMagicFormatPrompt {
        didSet {
            persistLLMSettings()
            saveProviderPromptFile(.apple, content: llmAppleSystemPrompt)
        }
    }
    var llmGemmaSystemPrompt = LLMDefaults.defaultGemmaMagicFormatPrompt {
        didSet {
            persistLLMSettings()
            saveProviderPromptFile(.localGemma, content: llmGemmaSystemPrompt)
        }
    }
    var llmSystemPrompt = "" {
        didSet { persistLLMSettings() }
    }
    var llmKeywordsRaw = "" {
        didSet { persistLLMSettings() }
    }
    var llmAutoLearnedKeywordsRaw = "" {
        didSet { persistLLMSettings() }
    }
    var learnFromEditsEnabled = true {
        didSet { persistLLMSettings() }
    }
    var llmAppPromptBindings: [AppPromptBinding] = [] {
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
            return "Keep \(AppIdentity.current.displayName) open while \(currentASRModelEntry.displayName) is downloaded, validated, and loaded."
        }
        if lastFailedASRModelID == selectedASRModelID, let lastFailedASRModelError, !lastFailedASRModelError.isEmpty {
            return "Last attempt failed. Retry setup for \(currentASRModelEntry.displayName) to use it for dictation."
        }
        return "Download \(currentASRModelEntry.displayName) to keep speech recognition fully local."
    }

    var modelLocationText: String {
        asrModelLocationText(for: selectedASRModelID)
    }

    var asrModelBanner: ASRModelBannerState? {
        if let activeASRModelOperationID {
            let entry = ASRModelCatalog.entry(for: activeASRModelOperationID)
            switch phase {
            case .downloadingModel:
                return ASRModelBannerState(
                    title: "Downloading Model",
                    detail: "Installing \(entry.displayName) locally. Keep \(AppIdentity.current.displayName) open until the files finish validating.",
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
        // System-managed models (Apple Speech) have no on-disk folder to open and can't
        // be deleted by us, so hide the folder/trash actions for them.
        guard !ASRModelCatalog.entry(for: modelID).isSystemManaged else {
            return false
        }
        return modelManager.isInstalled(modelID) && activeASRModelOperationID == nil && phase != .recording && phase != .transcribing
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
        let entry = ASRModelCatalog.entry(for: modelID)
        if entry.isSystemManaged {
            // Single source of truth for the system-managed label.
            return entry.sizeDisplayText
        }
        return ByteCountFormatter.string(fromByteCount: modelManager.installedByteCount(for: modelID), countStyle: .file)
    }

    func asrModelLocationText(for modelID: ASRModelID) -> String {
        let entry = ASRModelCatalog.entry(for: modelID)
        if entry.isSystemManaged {
            // System-managed models have no on-disk folder; the OS owns the asset.
            return entry.sizeDisplayText
        }
        return (try? modelManager.modelDirectoryURL(for: modelID).path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) ?? "~/Library/Application Support/Suniye/models"
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

    var onboardingPracticeLevels: [Float] {
        switch floatingIndicatorState {
        case let .listening(levels, _, _):
            return levels
        default:
            return Self.defaultIndicatorLevels(level: 0.08)
        }
    }

    var isOnboardingPracticeRecording: Bool {
        activeOnboardingStep == .speak && phase == .recording
    }

    var isOnboardingPracticeProcessing: Bool {
        activeOnboardingStep == .speak && phase == .transcribing
    }

    /// Post-onboarding Magic Format nudge: shown once, after the user has real
    /// dictations to judge the value against. The setup page checks provider
    /// availability after the user opens it.
    var shouldShowMagicFormatNudge: Bool {
        onboardingProgress.isFinished
            && !llmEnabled
            && !magicFormatNudgeDismissed
            && recentResults.count >= 3
    }

    /// Impression tracking for the nudge (idempotent per app run) — the
    /// denominator for nudge-conversion analysis.
    func magicFormatNudgeDidShow() {
        guard shouldShowMagicFormatNudge, !hasTrackedMagicFormatNudgeShown else {
            return
        }
        hasTrackedMagicFormatNudgeShown = true
        analytics.track(.mfNudge(action: .shown))
    }

    func dismissMagicFormatNudge() {
        analytics.track(.mfNudge(action: .dismissed))
        magicFormatNudgeDismissed = true
    }

    /// The nudge's CTA: records the open, retires the card, and hands the
    /// caller the section to navigate to (the existing Magic Format settings
    /// page, which already handles provider choice, unavailability, and repair).
    func openMagicFormatSetupFromNudge() -> MainWindowSection {
        analytics.track(.mfNudge(action: .opened))
        magicFormatNudgeDismissed = true
        return .style
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
    /// Tail of the in-progress transcript shown in the floating indicator while
    /// recording. Cleared on stop, insert, and every error path.
    private(set) var livePartialTranscript: String?
    /// Last full stabilized partial (pre-tail-truncation); the stabilizer anchors
    /// new decodes against it. Reset on preview start/stop so sessions never bleed.
    private var lastPublishedPartialTranscript = ""

    private let modelManager: ModelManagerProtocol
    private let transcriptionService: TranscriptionServiceProtocol
    private let audioCaptureService: AudioCaptureServiceProtocol
    private let textInsertionService: TextInsertionServiceProtocol
    private let editModeSelectionProvider: EditModeSelectionProviding
    private let hotkeyService: HotkeyServiceProtocol
    private let soundFeedbackService: SoundFeedbackServiceProtocol
    private let partialTranscriptionScheduler: PartialTranscriptionScheduler
    private let floatingIndicatorController = FloatingIndicatorController()
    private let llmPostProcessor: LLMPostProcessor
    private let appleMagicFormatPostProcessor: AppleMagicFormatPostProcessor
    private let localGemmaMagicFormatPostProcessor: LocalGemmaMagicFormatPostProcessor
    private let magicFormatCoordinator: MagicFormatCoordinator
    private let localLLMModelManager: LocalLLMModelManagerProtocol
    private let llmSettingsStore: LLMSettingsStoreProtocol
    private let magicFormatPromptFileStore: MagicFormatPromptFileStoreProtocol
    private let generalSettingsStore: GeneralSettingsStoreProtocol
    private let historyStore: HistoryStoreProtocol
    private let keychainService: KeychainServiceProtocol
    private let appUpdateController: AppUpdateControllerProtocol
    private let launchAtLoginService: LaunchAtLoginServiceProtocol
    private let diagnosticBundleService: DiagnosticBundleServiceProtocol
    private let issueReportUploadService: IssueReportUploadServiceProtocol
    private let analytics: Analytics
    /// Per-dictation monotonic latency marks. Safe as a single instance because
    /// the phase machine serializes dictations. Not observed UI state.
    @ObservationIgnored private var dictationTiming = DictationTiming()
    private let editLearningService: EditLearningServiceProtocol
    private let learningToastPresenter: LearningToastPresenting
    private let currentAppVersionProvider: () -> AppVersion?
    private let nowProvider: () -> Date
    private let frontmostAppBundleIDProvider: () -> String?
    private let fileOpener: (URL) -> Bool
    private let accessibilityOnboarding: AccessibilityOnboardingPresenting
    /// Injectable microphone TCC seams so denial/grant paths are unit-testable
    /// (the real AVCaptureDevice statics cannot be driven headless in CI).
    private let micAuthorizationStatusProvider: () -> AVAuthorizationStatus
    private let micAccessRequester: () async -> Bool
    /// Injectable Accessibility TCC seam for route selection after the user grants
    /// access in System Settings while Suniye is inactive.
    private let accessibilityTrustProvider: () -> Bool
    /// Injectable free-disk probe for the onboarding download preflight.
    private let availableDiskCapacityProvider: () async -> Int64?
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
        /// Bundle ID of the app the user was in when recording started, for per-app prompt routing.
        let frontmostAppBundleID: String?
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
    private var isShowingInsertionRecoveryWarning = false
    private var asrDownloadTask: Task<Void, Never>?
    private var localGemmaDownloadTask: Task<Void, Never>?
    private var localGemmaDownloadID: UUID?
    private var localGemmaDownloadStartedAt: Date?
    private var localGemmaDownloadCancelled = false {
        didSet {
            guard !isHydratingGeneralSettings, oldValue != localGemmaDownloadCancelled else {
                return
            }
            persistGeneralSettings()
        }
    }
    private var isHydratingLLMSettings = false
    private var isHydratingGeneralSettings = false
    private var isHydratingHistory = false
    private let llmE2EMode: LLME2EMode
    private enum DictationDestination: Equatable {
        case systemInsertion
        case clipboardOnly
        case onboardingPractice
        case editRewrite(selectedText: String?)

        var needsAccessibility: Bool {
            switch self {
            case .systemInsertion, .editRewrite:
                true
            case .clipboardOnly, .onboardingPractice:
                false
            }
        }

        var analyticsDestination: SuniyeAnalytics.DictationDestination {
            switch self {
            case .systemInsertion, .editRewrite:
                .systemInsertion
            case .clipboardOnly:
                .clipboard
            case .onboardingPractice:
                .onboardingPractice
            }
        }
    }

    init(
        modelManager: ModelManagerProtocol = ModelManager(),
        transcriptionService: TranscriptionServiceProtocol = RoutingTranscriptionService(),
        audioCaptureService: AudioCaptureServiceProtocol = AudioCaptureService(),
        textInsertionService: TextInsertionServiceProtocol = TextInsertionService(),
        editModeSelectionProvider: EditModeSelectionProviding? = nil,
        hotkeyService: HotkeyServiceProtocol = HotkeyService(),
        soundFeedbackService: SoundFeedbackServiceProtocol = SoundFeedbackService(),
        partialTranscriptionScheduler: PartialTranscriptionScheduler? = nil,
        llmPostProcessor: LLMPostProcessor = OpenRouterPostProcessor(),
        appleMagicFormatPostProcessor: AppleMagicFormatPostProcessor = AppleFoundationModelsPostProcessor(),
        localGemmaMagicFormatPostProcessor: LocalGemmaMagicFormatPostProcessor? = nil,
        localLLMModelManager: LocalLLMModelManagerProtocol = LocalLLMModelManager(),
        llmSettingsStore: LLMSettingsStoreProtocol = LLMSettingsStore(),
        magicFormatPromptFileStore: MagicFormatPromptFileStoreProtocol = MagicFormatPromptFileStore(),
        generalSettingsStore: GeneralSettingsStoreProtocol = GeneralSettingsStore(),
        historyStore: HistoryStoreProtocol = HistoryStore(),
        keychainService: KeychainServiceProtocol = KeychainService(),
        appUpdateController: AppUpdateControllerProtocol? = nil,
        launchAtLoginService: LaunchAtLoginServiceProtocol = LaunchAtLoginService(),
        diagnosticBundleService: DiagnosticBundleServiceProtocol = DiagnosticBundleService(),
        issueReportUploadService: IssueReportUploadServiceProtocol = IssueReportUploadService(),
        analytics: Analytics = AppAnalytics.makeDefault(),
        editLearningService: EditLearningServiceProtocol? = nil,
        learningToastPresenter: LearningToastPresenting? = nil,
        currentAppVersionProvider: @escaping () -> AppVersion? = { AppVersion.fromBundle() },
        nowProvider: @escaping () -> Date = Date.init,
        frontmostAppBundleIDProvider: @escaping () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier },
        fileOpener: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
        accessibilityOnboarding: AccessibilityOnboardingPresenting? = nil,
        micAuthorizationStatusProvider: @escaping () -> AVAuthorizationStatus = { AVCaptureDevice.authorizationStatus(for: .audio) },
        micAccessRequester: @escaping () async -> Bool = { await AVCaptureDevice.requestAccess(for: .audio) },
        accessibilityTrustProvider: @escaping () -> Bool = { AXIsProcessTrusted() },
        availableDiskCapacityProvider: (() async -> Int64?)? = nil,
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
        self.editModeSelectionProvider = editModeSelectionProvider ?? EditModeService()
        self.hotkeyService = hotkeyService
        self.soundFeedbackService = soundFeedbackService
        self.partialTranscriptionScheduler = partialTranscriptionScheduler ?? PartialTranscriptionScheduler()
        self.llmPostProcessor = llmPostProcessor
        self.appleMagicFormatPostProcessor = appleMagicFormatPostProcessor
        self.localLLMModelManager = localLLMModelManager
        let resolvedLocalGemmaPostProcessor = localGemmaMagicFormatPostProcessor ?? LocalGemmaPostProcessor(
            client: LocalGemmaLlamaCppClient(
                locator: LocalGemmaRuntimeLocator(modelManager: localLLMModelManager),
                onModelLoad: { model, loadMs in
                    analytics.track(.modelLoad(model: SafeLabel(model), loadMs: loadMs, evictedByKeepAlive: false))
                },
                onKeepAliveEvicted: { model in
                    analytics.track(.modelLoad(model: SafeLabel(model), loadMs: 0, evictedByKeepAlive: true))
                }
            )
        )
        self.localGemmaMagicFormatPostProcessor = resolvedLocalGemmaPostProcessor
        self.magicFormatCoordinator = MagicFormatCoordinator(
            apiPostProcessor: llmPostProcessor,
            applePostProcessor: appleMagicFormatPostProcessor,
            localGemmaPostProcessor: resolvedLocalGemmaPostProcessor
        )
        self.llmSettingsStore = llmSettingsStore
        self.magicFormatPromptFileStore = magicFormatPromptFileStore
        self.generalSettingsStore = generalSettingsStore
        self.historyStore = historyStore
        self.keychainService = keychainService
        self.appUpdateController = appUpdateController ?? AppUpdateControllerFactory.makeDefault()
        self.launchAtLoginService = launchAtLoginService
        self.diagnosticBundleService = diagnosticBundleService
        self.issueReportUploadService = issueReportUploadService
        self.analytics = analytics
        self.editLearningService = editLearningService ?? EditLearningService()
        self.learningToastPresenter = learningToastPresenter ?? LearningToastPresenter()
        self.currentAppVersionProvider = currentAppVersionProvider
        self.nowProvider = nowProvider
        self.frontmostAppBundleIDProvider = frontmostAppBundleIDProvider
        self.fileOpener = fileOpener
        self.accessibilityOnboarding = accessibilityOnboarding ?? PermisoAccessibilityOnboarding()
        self.micAuthorizationStatusProvider = micAuthorizationStatusProvider
        self.micAccessRequester = micAccessRequester
        self.accessibilityTrustProvider = accessibilityTrustProvider
        let modelsRootDirectory = try? modelManager.modelsRootDirectoryURL()
        self.availableDiskCapacityProvider = availableDiskCapacityProvider ?? {
            guard let modelsRootDirectory else {
                return nil
            }
            return await Task.detached(priority: .utility) {
                try? modelsRootDirectory.resourceValues(
                    forKeys: [.volumeAvailableCapacityForImportantUsageKey]
                ).volumeAvailableCapacityForImportantUsage
            }.value
        }
        self.issueReportDiagnosticsDestinationPicker = issueReportDiagnosticsDestinationPicker
        self.temporaryFileCleanupScheduler = temporaryFileCleanupScheduler
        self.magicFormatSlowWarningDelaySeconds = magicFormatSlowWarningDelaySeconds
        self.runtimeServicesEnabled = startServices
        self.floatingIndicatorEnabled = startServices && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
        self.llmE2EMode = llmE2EMode ?? AppState.detectLLME2EMode(arguments: CommandLine.arguments)
        self.appUpdateController.onStateChange = { [weak self] in
            self?.refreshUpdateControllerState()
        }
        self.editLearningService.onLearnedTerms = { [weak self] terms in
            self?.handleLearnedVocabularyTerms(terms)
        }
        self.editLearningService.onEditRate = { [weak self] bucket in
            self?.analytics.track(.dictationEdited(editRateBucket: bucket))
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
                    // Mid-session (async) descent down the capture ladder — record
                    // the re-resolved backend too, else a session that starts on
                    // rung 0 and drops to rung 1 would only ever report rung 0.
                    emitAudioBackendUsed(route)
                case let .interrupted(sessionID, reason):
                    await handleAudioCaptureInterruption(sessionID: sessionID, reason: reason)
                }
            }
        }

        AppLogger.shared.log(.info, "app state init")
        loadHistory()
        loadGeneralSettings()
        loadLLMSettings()
        analytics.setEnabled(shareAnalyticsEnabled)
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
            analytics.start()
            emitAppLaunchEvent()
            wireHotkey()
            Task {
                await bootstrap()
            }
        }
    }

    private func emitAppLaunchEvent() {
        analytics.track(.appLaunch(
            device: DeviceProfileReader.read(),
            settings: analyticsSettingsSnapshot(),
            firstLaunch: !firstLaunchRecorded
        ))
        if !firstLaunchRecorded {
            // Dedicated flag (not the onboarding position): quitting on the
            // welcome screen must not re-count as a new install next launch.
            firstLaunchRecorded = true
            persistGeneralSettings()
        }
    }

    private func analyticsSettingsSnapshot() -> SettingsSnapshot {
        SettingsSnapshot([
            "asr_model": .label(SafeLabel(selectedASRModelID.rawValue)),
            "auto_submit": .bool(autoSubmitEnabled),
            "echo_cancellation": .bool(echoCancellationEnabled),
            "sound_feedback": .bool(soundFeedbackEnabled),
            "magic_format_enabled": .bool(llmEnabled),
            "magic_format_provider": .label(AnalyticsMapping.cleanupProvider(llmProvider)),
            "update_channel": .label(SafeLabel(updateChannel.rawValue)),
        ])
    }

    /// Force-send queued analytics (called on sleep). Best-effort, never blocks.
    func flushAnalytics() async {
        await analytics.flush()
    }

    /// Durably enqueue a session_end without awaiting (safe on app termination;
    /// the event ships on the next launch). Also usable on power-off.
    func recordAnalyticsSessionEnd() {
        analytics.recordSessionEnd(cleanExit: true)
    }

    /// Opens the public "what we collect" privacy page.
    func openAnalyticsPrivacyInfo() {
        if let url = URL(string: "https://suniye.kishans.in/privacy") {
            _ = fileOpener(url)
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
        resumeInterruptedLocalGemmaDownloadIfNeeded()
        setFloatingIndicatorState(.idle)
        AppLogger.shared.log(.info, "bootstrap done")
    }

    // MARK: - Onboarding state machine

    /// Resumes onboarding at the persisted position (or dismisses it once
    /// finished). Steps re-shown by resume carry `resumed=true` in analytics.
    func startOnboardingIfNeeded() {
        guard let step = onboardingProgress.resumeStep else {
            activeOnboardingStep = nil
            return
        }
        if onboardingProgress != .notStarted {
            onboardingResumedPending = true
        }
        if onboardingStartedAt == nil {
            onboardingStartedAt = nowProvider()
        }
        activeOnboardingStep = step
        if step == .welcome {
            startOnboardingModelDownloadIfNeeded()
        }
    }

    /// Single forward transition used by the onboarding UI.
    func advanceOnboarding() async {
        switch activeOnboardingStep {
        case .welcome:
            await beginOnboardingSetup()
        case .speak:
            advanceOnboardingFromSpeak()
        case .typeAnywhere:
            finishOnboarding()
        case nil:
            startOnboardingIfNeeded()
        }
    }

    /// "Get Started": persists progress and starts the required ASR model
    /// download if Welcome did not already start it. Download time overlaps the
    /// mic grant and the first dictation instead of blocking on its own screen.
    func beginOnboardingSetup() async {
        guard activeOnboardingStep == .welcome else {
            return
        }
        onboardingDiskSpaceMessage = nil
        if !isModelInstalled, let message = await modelDownloadDiskSpaceMessage() {
            onboardingDiskSpaceMessage = message
            onStateChange?()
            return
        }
        setOnboardingProgress(.speakReached)
        activeOnboardingStep = .speak
        if !isModelInstalled, activeASRModelOperationID == nil {
            startModelDownload()
        }
    }

    private func startOnboardingModelDownloadIfNeeded() {
        guard !isModelInstalled, activeASRModelOperationID == nil else {
            return
        }
        Task { @MainActor [weak self] in
            guard let self, !isModelInstalled, activeASRModelOperationID == nil else {
                return
            }
            guard let message = await modelDownloadDiskSpaceMessage() else {
                startModelDownload()
                return
            }
            onboardingDiskSpaceMessage = message
            onStateChange?()
        }
    }

    func advanceOnboardingFromSpeak() {
        guard activeOnboardingStep == .speak else {
            return
        }
        setOnboardingProgress(.typeAnywhereReached)
        activeOnboardingStep = .typeAnywhere
    }

    /// Terminal transition (Finish, or the "Later — I'll paste with ⌘V" skip on
    /// the Accessibility screen). This is where completion is persisted and the
    /// `completed` + `onboarding_outcome` events fire — after the flow actually
    /// ends, not before the practice step as the old wizard did.
    func finishOnboarding() {
        guard activeOnboardingStep != nil else {
            return
        }
        let durationMs = onboardingStartedAt.map { Int(nowProvider().timeIntervalSince($0) * 1000) }
        analytics.track(.onboardingStep(step: .completed, granted: nil, resumed: nil))
        analytics.track(.onboardingOutcome(
            durationMs: durationMs,
            practiced: onboardingPracticeSucceeded,
            micGranted: hasMicPermission,
            axGranted: hasAccessibilityPermission,
            modelReady: asrModelReady
        ))
        setOnboardingProgress(.finished)
        onboardingPracticeText = ""
        onboardingPracticeResult = nil
        onboardingStartedAt = nil
        activeOnboardingStep = nil
    }

    private func setOnboardingProgress(_ progress: OnboardingProgress) {
        onboardingProgress = progress
    }

    /// One emission point for onboarding_step, deduped per run so launch-resume
    /// and navigation can never double-count a step.
    private func trackOnboardingStepShownIfNeeded() {
        guard let step = activeOnboardingStep, !onboardingStepsTracked.contains(step) else {
            onboardingResumedPending = false
            return
        }
        onboardingStepsTracked.insert(step)
        let resumed = onboardingResumedPending
        onboardingResumedPending = false
        analytics.track(.onboardingStep(step: step.analyticsName, granted: nil, resumed: resumed ? true : nil))
    }

    /// True while dictation prerequisites for the Speak screen's practice box
    /// are met: installed model that is loaded or actively usable.
    var asrModelReady: Bool {
        isModelInstalled && (phase == .ready || phase == .recording || phase == .transcribing)
    }

    private func modelDownloadDiskSpaceMessage() async -> String? {
        let neededBytes = modelManager.expectedDownloadSizeBytes(for: selectedASRModelID) * 2
        guard neededBytes > 0,
              let available = await availableDiskCapacityProvider(),
              available < neededBytes else {
            return nil
        }
        let neededText = ByteCountFormatter.string(fromByteCount: neededBytes, countStyle: .file)
        return "Not enough free disk space — the speech model needs about \(neededText) free."
    }

    func refreshPermissions(
        requestMicrophone: Bool = false,
        promptAccessibility: Bool = false,
        askSurface: PermissionAskSurface = .settings
    ) async {
        let priorMic = hasMicPermission
        let priorAccessibility = hasAccessibilityPermission

        var micStatus = micAuthorizationStatusProvider()
        if requestMicrophone, micStatus == .notDetermined {
            // A real system prompt: the one moment a mic grant rate is measurable.
            let granted = await micAccessRequester()
            micStatus = micAuthorizationStatusProvider()
            // Some simulated/test providers only answer through the requester;
            // trust the requester when the status read lags behind.
            if granted, micStatus == .notDetermined {
                micStatus = .authorized
            }
            analytics.track(.permissionRequest(
                kind: .microphone,
                surface: askSurface,
                outcome: granted ? .granted : .denied
            ))
        }
        hasMicPermission = micStatus == .authorized
        hasMicPermissionBeenDenied = micStatus == .denied || micStatus == .restricted

        if promptAccessibility {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            hasAccessibilityPermission = AXIsProcessTrustedWithOptions(options)
        } else {
            hasAccessibilityPermission = accessibilityTrustProvider()
        }

        if !priorMic, hasMicPermission {
            analytics.track(.permissionTransition(kind: .microphone, granted: true))
        }
        if !priorAccessibility, hasAccessibilityPermission {
            analytics.track(.permissionTransition(kind: .accessibility, granted: true))
        }
        updateLastKnownAccessibilityGranted()

        AppLogger.shared.log(.info, "permissions: mic=\(hasMicPermission) ax=\(hasAccessibilityPermission)")
        onStateChange?()
    }

    /// Re-reads Accessibility without changing microphone state. This matters when
    /// the user grants access in System Settings while Suniye is not active.
    private func refreshAccessibilityPermission() {
        let wasGranted = hasAccessibilityPermission
        hasAccessibilityPermission = accessibilityTrustProvider()
        if !wasGranted, hasAccessibilityPermission {
            analytics.track(.permissionTransition(kind: .accessibility, granted: true))
        }
        updateLastKnownAccessibilityGranted()
        onStateChange?()
    }

    /// Records the last observed Accessibility trust so a later `false` reading
    /// can be recognized as a stale grant (app update / TCC reset) rather than a
    /// never-granted state — the two need different recovery UI.
    private func updateLastKnownAccessibilityGranted() {
        if hasAccessibilityPermission {
            accessibilityGrantLikelyStale = false
            accessibilityAssistTimedOut = false
            if !lastKnownAccessibilityGranted {
                lastKnownAccessibilityGranted = true
                persistGeneralSettings()
            }
        }
    }

    /// Entry point for the Accessibility "Enable" / "Request Access" buttons.
    /// When the drag helper is enabled, presents the Permiso overlay and auto-advances
    /// once the user drags Suniye into the Accessibility list; otherwise falls back to the
    /// plain System Settings deep-link.
    func beginAccessibilityOnboarding(askSurface: PermissionAskSurface = .onboarding) {
        accessibilityAssistTimedOut = false

        // Stale TCC entry (post-update): Suniye is already in the Accessibility
        // list, just untrusted. The drag overlay's "drag Suniye into the list"
        // instruction would mislead; deep-link with toggle-off-and-on copy instead.
        if lastKnownAccessibilityGranted, !hasAccessibilityPermission {
            accessibilityGrantLikelyStale = true
            onStateChange?()
            openAccessibilityPrivacySettings()
            return
        }

        guard accessibilityDragHelperEnabled else {
            openAccessibilityPrivacySettings()
            return
        }

        accessibilityOnboarding.present(
            onGranted: { [weak self] in
                guard let self else {
                    return
                }
                self.hasAccessibilityPermission = true
                self.updateLastKnownAccessibilityGranted()
                self.onStateChange?()
                // Authoritative re-read of all permission state.
                Task {
                    await self.refreshPermissions()
                }
            },
            onEnded: { [weak self] end in
                guard let self else {
                    return
                }
                switch end {
                case .granted:
                    self.analytics.track(.permissionRequest(kind: .accessibility, surface: askSurface, outcome: .granted))
                case .dismissed:
                    self.analytics.track(.permissionRequest(kind: .accessibility, surface: askSurface, outcome: .overlayDismissed))
                case .timedOut:
                    self.accessibilityAssistTimedOut = true
                    self.onStateChange?()
                    self.analytics.track(.permissionRequest(kind: .accessibility, surface: askSurface, outcome: .overlayTimeout))
                }
            }
        )
    }

    func requestMicrophonePermission(askSurface: PermissionAskSurface = .settings) {
        // Once denied, the system never re-prompts: route straight to the pane
        // the user must flip the switch in.
        if hasMicPermissionBeenDenied {
            openMicrophonePrivacySettings()
            return
        }
        Task {
            await refreshPermissions(requestMicrophone: true, askSurface: askSurface)
        }
    }

    func handleAttentionFixAction(_ action: AttentionItemFixAction) {
        switch action {
        case .requestMicrophonePermission:
            requestMicrophonePermission(askSurface: .dashboard)
        case .requestAccessibilityPermission:
            beginAccessibilityOnboarding(askSurface: .dashboard)
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
        let combined = LLMDefaults.parseKeywords(from: llmKeywordsRaw) + [trimmed]
        llmKeywordsRaw = LLMDefaults.parseKeywords(from: combined.joined(separator: "\n")).joined(separator: "\n")
    }

    func removeVocabularyTerm(_ value: String) {
        let filtered = LLMDefaults.parseKeywords(from: llmKeywordsRaw)
            .filter { $0.caseInsensitiveCompare(value) != .orderedSame }
        llmKeywordsRaw = filtered.joined(separator: "\n")
        removeAutoLearnedVocabularyTerms([value])
    }

    /// Adds a binding for the app, or refreshes the display name of an existing one.
    /// New bindings start blank because the saved prompt is appended to the active provider prompt. Returns the affected binding.
    @discardableResult
    func addAppPromptBinding(bundleID: String, appDisplayName: String) -> AppPromptBinding? {
        guard let trimmedBundleID = AppPromptResolver.normalizedBundleID(bundleID) else {
            return nil
        }
        let trimmedName = appDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = llmAppPromptBindings.firstIndex(where: { AppPromptResolver.matches($0.bundleID, trimmedBundleID) }) {
            if !trimmedName.isEmpty {
                llmAppPromptBindings[index].appDisplayName = trimmedName
            }
            return llmAppPromptBindings[index]
        }
        let binding = AppPromptBinding(
            bundleID: trimmedBundleID,
            appDisplayName: trimmedName.isEmpty ? trimmedBundleID : trimmedName,
            prompt: magicFormatPromptFileStore.syncAppPrompt(bundleID: trimmedBundleID, fallback: "")
        )
        llmAppPromptBindings.append(binding)
        return binding
    }

    func updateAppPromptBinding(id: UUID, prompt: String) {
        guard let index = llmAppPromptBindings.firstIndex(where: { $0.id == id }) else {
            return
        }
        llmAppPromptBindings[index].prompt = prompt
        magicFormatPromptFileStore.saveAppPrompt(bundleID: llmAppPromptBindings[index].bundleID, content: prompt)
    }

    func removeAppPromptBinding(id: UUID) {
        llmAppPromptBindings.removeAll { $0.id == id }
    }

    var autoLearnedVocabularyTerms: [String] {
        currentLLMSettings().autoLearnedKeywords
    }

    func isAutoLearnedVocabularyTerm(_ term: String) -> Bool {
        autoLearnedVocabularyTerms.contains { $0.caseInsensitiveCompare(term) == .orderedSame }
    }

    @discardableResult
    func addAutoLearnedVocabularyTerms(_ terms: [String]) -> [String] {
        let existing = vocabularyTerms
        let newTerms = terms.filter { term in
            !existing.contains { $0.caseInsensitiveCompare(term) == .orderedSame }
        }
        guard !newTerms.isEmpty else {
            return []
        }
        let combined = LLMDefaults.parseKeywords(from: llmAutoLearnedKeywordsRaw) + newTerms
        llmAutoLearnedKeywordsRaw = LLMDefaults.parseKeywords(from: combined.joined(separator: "\n")).joined(separator: "\n")
        return newTerms
    }

    func removeAutoLearnedVocabularyTerms(_ terms: [String]) {
        let remaining = LLMDefaults.parseKeywords(from: llmAutoLearnedKeywordsRaw).filter { existing in
            !terms.contains { $0.caseInsensitiveCompare(existing) == .orderedSame }
        }
        llmAutoLearnedKeywordsRaw = remaining.joined(separator: "\n")
    }

    private func handleLearnedVocabularyTerms(_ terms: [String]) {
        let added = addAutoLearnedVocabularyTerms(terms)
        guard !added.isEmpty else {
            return
        }
        AppLogger.shared.log(.info, "edit learning added vocabulary terms count=\(added.count)")
        analytics.track(.vocabLearnedFromEdit(count: added.count))
        learningToastPresenter.showLearnedTerms(added) { [weak self] in
            self?.removeAutoLearnedVocabularyTerms(added)
        }
    }

    private func beginEditLearningTracking(insertedText: String) {
        guard learnFromEditsEnabled,
              let readFieldValue = textInsertionService.makeFocusedFieldValueProvider() else {
            return
        }
        editLearningService.beginTracking(EditLearningSession(
            insertedText: insertedText,
            fieldValueAfterInsertion: readFieldValue(),
            existingVocabulary: vocabularyTerms,
            readCurrentFieldValue: readFieldValue
        ))
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

    func openCurrentMagicFormatPromptInEditor() {
        _ = fileOpener(currentMagicFormatPromptURL)
    }

    func reloadMagicFormatPromptsFromFiles() {
        applyLLMSettings(magicFormatPromptFileStore.syncPrompts(settings: currentLLMSettings()))
        persistLLMSettings()
    }

    func openAppPromptInEditor(id: UUID) {
        guard let binding = llmAppPromptBindings.first(where: { $0.id == id }),
              let url = magicFormatPromptFileStore.appPromptURL(bundleID: binding.bundleID) else {
            return
        }
        _ = fileOpener(url)
    }

    var currentMagicFormatPromptURL: URL {
        if usesAppleMagicFormatSettings {
            return magicFormatPromptFileStore.providerPromptURL(.apple)
        }
        if usesLocalGemmaMagicFormatSettings {
            return magicFormatPromptFileStore.providerPromptURL(.localGemma)
        }
        return magicFormatPromptFileStore.providerPromptURL(.api)
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
        localGemmaDownloadCancelled = false
        localGemmaInstallState = .downloading(LocalLLMDownloadProgress(
            fractionCompleted: 0,
            downloadedBytes: 0,
            expectedBytes: entry.expectedSizeBytes
        ))
        clearMagicFormatSetupTestResult()

        let downloadID = UUID()
        localGemmaDownloadID = downloadID
        localGemmaDownloadStartedAt = nowProvider()
        trackModelDownload(kind: .cleanup, model: modelID.rawValue, outcome: .started)
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
                self.trackModelDownload(kind: .cleanup, model: modelID.rawValue, outcome: .completed, startedAt: self.localGemmaDownloadStartedAt)
                AppLogger.shared.log(.info, "local gemma download complete model=\(entry.filename)")
            } catch {
                self.localGemmaDownloadID = nil
                let message: String
                if Task.isCancelled || (error as NSError).code == NSURLErrorCancelled {
                    message = "Download canceled."
                    self.trackModelDownload(kind: .cleanup, model: modelID.rawValue, outcome: .canceled, startedAt: self.localGemmaDownloadStartedAt)
                    AppLogger.shared.log(.info, "local gemma download canceled model=\(entry.filename)")
                } else {
                    message = error.localizedDescription
                    self.trackModelDownload(kind: .cleanup, model: modelID.rawValue, outcome: .failed, startedAt: self.localGemmaDownloadStartedAt)
                    AppLogger.shared.log(.error, "local gemma download failed model=\(entry.filename) error=\(message)")
                }
                self.localGemmaInstallState = .failed(message)
            }

            self.localGemmaDownloadStartedAt = nil
            self.localGemmaDownloadTask = nil
        }
    }

    /// Self-heal an interrupted local model download after bootstrap. An
    /// explicit Cancel is persisted, so the user stays in control of resume.
    func resumeInterruptedLocalGemmaDownloadIfNeeded() {
        guard llmEnabled,
              llmProvider == .localGemma,
              localLLMModelManager.isHardwareSupported,
              !localGemmaInstallState.isInstalled,
              !localGemmaDownloadCancelled,
              canStartLocalGemmaDownload else {
            return
        }
        AppLogger.shared.log(.info, "resuming interrupted local gemma download at bootstrap")
        startLocalGemmaDownload()
    }

    func cancelLocalGemmaDownload() {
        guard canCancelLocalGemmaDownload else {
            return
        }
        localGemmaDownloadCancelled = true
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

    @discardableResult
    func pasteLastTranscript() async -> Bool {
        guard let text = lastTranscriptText, !text.isEmpty else {
            return false
        }

        textInsertionService.warmTargetAppAccessibility()
        do {
            try await textInsertionService.insertText(text)
            clearInsertionRecoveryWarning()
            AppLogger.shared.log(.info, "paste last transcript completed")
            return true
        } catch {
            AppLogger.shared.log(.warning, "paste last transcript failed: \(error.localizedDescription)")
            playSoundFeedback(.error)
            showInsertionRecoveryWarning()
            return false
        }
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

        if ASRModelCatalog.entry(for: modelID).isSystemManaged {
            // Presence of the OS-managed asset can only be checked asynchronously, so this
            // path decides download-with-progress vs. straight load inside its own Task.
            prepareSystemManagedModel(modelID)
        } else if modelManager.isInstalled(modelID) {
            selectASRModel(modelID)
        } else {
            downloadASRModel(modelID, autoSelect: true)
        }
    }

    /// Sets up a system-managed model (Apple Speech): if its on-device asset isn't present
    /// yet, download it with a real progress bar; otherwise load it straight away. Then
    /// selects it. Avoids the silent, hung-looking first-run download inside `loadModel`.
    private func prepareSystemManagedModel(_ modelID: ASRModelID) {
        guard phase != .recording && phase != .transcribing && activeASRModelOperationID == nil else {
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
                let assetInstalled = await modelManager.isSystemManagedAssetInstalled(modelID)
                if !assetInstalled {
                    phase = .downloadingModel
                    statusText = "Downloading model..."
                    downloadProgress = 0
                    modelDownloadStartedAt = nowProvider()
                    trackModelDownload(kind: .asr, model: modelID.rawValue, outcome: .started)
                    try await modelManager.downloadAndExtractModel(modelID) { [weak self] progress in
                        Task { @MainActor in
                            self?.downloadProgress = progress
                        }
                    }
                    guard await modelManager.isSystemManagedAssetInstalled(modelID) else {
                        throw AppStateError.modelValidationFailed
                    }
                    trackModelDownload(kind: .asr, model: modelID.rawValue, outcome: .completed, startedAt: modelDownloadStartedAt)
                    modelDownloadStartedAt = nil
                    phase = .loading
                    statusText = "Loading model..."
                }

                try await loadRecognizer(for: modelID)
                selectedASRModelID = modelID
                phase = .ready
                statusText = "Ready"
                lastError = nil
                lastFailedASRModelID = nil
                lastFailedASRModelError = nil
                AppLogger.shared.log(.info, "system-managed model ready id=\(modelID.rawValue)")
            } catch {
                if modelDownloadStartedAt != nil {
                    trackModelDownload(kind: .asr, model: modelID.rawValue, outcome: .failed, startedAt: modelDownloadStartedAt)
                }
                handleASRModelOperationFailure(
                    for: modelID,
                    error: error,
                    fallbackToReadyState: hadLoadedModel
                )
            }

            activeASRModelOperationID = nil
            modelDownloadStartedAt = nil
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
        trackModelDownload(kind: .asr, model: modelID.rawValue, outcome: .started)

        asrDownloadTask = Task {
            do {
                AppLogger.shared.log(.info, "model download started id=\(modelID.rawValue)")
                try await modelManager.downloadAndExtractModel(modelID) { [weak self] progress in
                    Task { @MainActor in
                        self?.downloadProgress = progress
                    }
                }

                phase = .loading
                statusText = "Validating model..."

                guard modelManager.isInstalled(modelID) else {
                    throw AppStateError.modelValidationFailed
                }

                trackModelDownload(kind: .asr, model: modelID.rawValue, outcome: .completed, startedAt: modelDownloadStartedAt)
                modelDownloadStartedAt = nil

                if autoSelect {
                    do {
                        try await loadRecognizer(for: modelID)
                        selectedASRModelID = modelID
                        phase = .ready
                        statusText = "Ready"
                        lastError = nil
                        lastFailedASRModelID = nil
                        lastFailedASRModelError = nil
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
                if Self.isCancellation(error) {
                    trackModelDownload(kind: .asr, model: modelID.rawValue, outcome: .canceled, startedAt: modelDownloadStartedAt)
                    downloadProgress = 0
                    if hadLoadedModel {
                        phase = .ready
                        statusText = "Ready"
                    } else {
                        phase = .needsModel
                        statusText = "Model required"
                    }
                    lastError = nil
                    AppLogger.shared.log(.info, "model download canceled id=\(modelID.rawValue)")
                } else {
                    trackModelDownload(kind: .asr, model: modelID.rawValue, outcome: .failed, startedAt: modelDownloadStartedAt)
                    handleASRModelOperationFailure(
                        for: modelID,
                        error: error,
                        fallbackToReadyState: hadLoadedModel
                    )
                    AppLogger.shared.log(.error, "model download failed id=\(modelID.rawValue) error=\(error.localizedDescription)")
                }
            }

            activeASRModelOperationID = nil
            modelDownloadStartedAt = nil
            asrDownloadTask = nil
        }
    }

    var canCancelASRModelDownload: Bool {
        phase == .downloadingModel && asrDownloadTask != nil
    }

    /// Cancels an in-flight ASR model download (previously impossible: the
    /// ~680 MB required download could only be abandoned by quitting the app).
    func cancelASRModelDownload() {
        guard canCancelASRModelDownload else {
            return
        }
        asrDownloadTask?.cancel()
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    private func trackModelDownload(kind: ModelKind, model: String, outcome: ModelDownloadOutcome, startedAt: Date? = nil) {
        let durationMs = startedAt.map { Int(nowProvider().timeIntervalSince($0) * 1000) }
        analytics.track(.modelDownload(
            kind: kind,
            model: SafeLabel(model),
            outcome: outcome,
            durationMs: durationMs
        ))
    }

    /// Maps the raw download errors most users actually hit to actionable copy.
    private static func friendlyModelDownloadMessage(for error: Error) -> String? {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return nil
        }
        switch nsError.code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorDataNotAllowed:
            return "You appear to be offline. Reconnect and retry the download."
        case NSURLErrorTimedOut:
            return "The download timed out. Retry when your connection is stable."
        case NSURLErrorNetworkConnectionLost:
            return "The connection dropped mid-download. Retry to continue."
        default:
            return nil
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
        analytics.track(.modelChanged(kind: .asr, model: SafeLabel(modelID.rawValue)))
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

    /// Title for the status-bar menu's setup/resume item; nil once onboarding is
    /// finished. Shows live download progress so a window-closed-mid-download
    /// install still has a visible pulse.
    var setupMenuItemTitle: String? {
        guard !onboardingProgress.isFinished else {
            return nil
        }
        if phase == .downloadingModel {
            return "Downloading speech model — \(Int(downloadProgress * 100))%"
        }
        return "Finish Setting Up \(AppIdentity.current.displayName)…"
    }

    /// The Accessibility screen's "Try it in Notes" demo: real insertion into a
    /// real app is the product's actual value, and the old preview-only practice
    /// never demonstrated it.
    func openNotesForInsertionDemo() {
        guard let notesURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Notes") else {
            AppLogger.shared.log(.warning, "notes demo: Notes.app not found")
            return
        }
        _ = fileOpener(notesURL)
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

    func updateDictationHotkey(_ configuration: HotkeyConfiguration) {
        hotkeyConfiguration = configuration
    }

    func updatePasteLastTranscriptHotkey(_ configuration: HotkeyConfiguration) {
        pasteLastTranscriptHotkeyConfiguration = configuration
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
        analytics.track(.updateAction(kind: .autoToggle, fromVersion: nil, toVersion: nil))
        AppLogger.shared.log(.info, "sparkle automatic update checks set enabled=\(enabled)")
    }

    func setUpdateChannel(_ channel: UpdateChannel) {
        updateChannel = channel
        analytics.track(.updateAction(kind: .channelChange, fromVersion: nil, toVersion: SafeLabel(channel.rawValue)))
        AppLogger.shared.log(.info, "sparkle update channel set channel=\(channel.rawValue)")
    }

    private func refreshUpdateControllerState() {
        canCheckForUpdates = appUpdateController.canCheckForUpdates
        automaticallyChecksForUpdates = appUpdateController.automaticallyChecksForUpdates
    }

    private func applyUpdateChannelToController() {
        appUpdateController.updateChannel = updateChannel
    }

    func postProcessTextIfEnabled(_ rawText: String, frontmostAppBundleID: String? = nil) async -> String {
        await polishOutcome(rawText, frontmostAppBundleID: frontmostAppBundleID).text
    }

    /// The full Magic Format outcome (polished text + whether a provider actually
    /// ran + which provider/model + fallback reason). The dictation path needs
    /// this for accurate `dictation_completed` analytics — `was_llm_polished`
    /// must mean "a provider ran", not "the text changed". Other callers use
    /// `postProcessTextIfEnabled`, which just returns `.text`.
    func polishOutcome(_ rawText: String, frontmostAppBundleID: String? = nil) async -> MagicFormatPolishOutcome {
        let input = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            return .notRun(rawText)
        }

        switch llmE2EMode {
        case .forceSuccess:
            AppLogger.shared.log(.info, "llm e2e forced success")
            return .polished("\(input).", provider: .openAICompatible, model: nil)
        case .forceFailure:
            AppLogger.shared.log(.warning, "llm e2e forced fallback")
            return .fellBack(rawText, provider: nil, reason: .unknown)
        case .none:
            break
        }

        guard llmEnabled else {
            // Magic Format is off — not a fallback, just not run.
            return .notRun(rawText)
        }

        var settings = currentLLMSettings()
        if let appInstructions = AppPromptResolver.additionalInstructions(for: frontmostAppBundleID, bindings: llmAppPromptBindings) {
            settings = settings.appendingAppInstructions(appInstructions)
            // No bundle ID here: app.log ships in diagnostic reports.
            AppLogger.shared.log(.info, "llm per-app prompt instructions appended")
        }

        return await magicFormatCoordinator.polish(
            input: input,
            rawText: rawText,
            request: makeMagicFormatRequest(settings: settings)
        )
    }

    /// Pass `settings` when per-app prompt instructions apply (dictation polish);
    /// Edit Mode omits it because the rewrite path never reads the Magic Format prompts.
    private func makeMagicFormatRequest(settings: LLMSettings? = nil) -> MagicFormatCoordinator.PolishRequest {
        MagicFormatCoordinator.PolishRequest(
            requestedProvider: llmProvider,
            settings: settings ?? currentLLMSettings(),
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
            setStage: { [weak self] text in
                guard let self else {
                    return
                }
                self.statusText = text
                guard case .processing = self.floatingIndicatorState else {
                    return
                }
                self.setFloatingIndicatorState(.processing(message: text))
            },
            // The custom preset's model id is user free text: masked here (at
            // request build, pre-suspension) so neither analytics nor app.log
            // ever see it.
            analyticsModelOverride: llmSelectedModelPreset == .custom ? "custom" : nil
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

        hotkeyService.onEditModeHotkeyDown = { [weak self] in
            AppLogger.shared.log(.debug, "edit mode hotkey callback: down")
            Task { @MainActor in
                await self?.beginEditModeRecordingFlow()
            }
        }

        hotkeyService.onEditModeHotkeyUp = { [weak self] in
            AppLogger.shared.log(.debug, "edit mode hotkey callback: up")
            Task { @MainActor in
                await self?.finishEditModeRecording()
            }
        }

        hotkeyService.onPasteLastTranscript = { [weak self] in
            AppLogger.shared.log(.debug, "paste last transcript hotkey callback")
            Task { @MainActor in
                await self?.pasteLastTranscript()
            }
        }

        hotkeyService.startMonitoring(
            configuration: hotkeyConfiguration,
            editModeConfiguration: editModeHotkeyConfiguration,
            pasteLastTranscriptConfiguration: pasteLastTranscriptHotkeyConfiguration
        )
        AppLogger.shared.log(
            .info,
            "hotkey monitoring started configuration=\(hotkeyConfiguration.displayString) editMode=\(editModeHotkeyConfiguration?.displayString ?? "off") pasteLast=\(pasteLastTranscriptHotkeyConfiguration.displayString)"
        )
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
        let message = Self.friendlyModelDownloadMessage(for: error) ?? error.localizedDescription
        downloadProgress = 0
        lastFailedASRModelID = modelID
        lastFailedASRModelError = message

        if fallbackToReadyState, loadedASRModelID != nil {
            phase = .ready
            statusText = "Ready"
            lastError = nil
            return
        }

        phase = .error
        lastError = message
        statusText = "Download failed"
    }

    private func loadRecognizer(for modelID: ASRModelID) async throws {
        let config = try modelManager.makeRecognizerConfig(for: modelID)
        try await transcriptionService.loadModel(config: config)
        loadedASRModelID = modelID
    }

    var isEditModeAvailable: Bool {
        llmEnabled && magicFormatSetupState == .ready
    }

    /// Edit Mode hotkey down: capture the current selection, then record the spoken instruction.
    func beginEditModeRecordingFlow() async {
        guard isEditModeAvailable else {
            lastError = "Edit Mode needs a working Magic Format provider"
            statusText = "Magic Format required"
            AppLogger.shared.log(.warning, "edit mode blocked: magic format not ready")
            playSoundFeedback(.error)
            showTransientIndicatorError("Set up Magic Format to use Edit Mode")
            return
        }
        // Same self-heal as the dictation flow: a transient audio/transcription
        // error must not leave the edit hotkey dead until a dictation clears it.
        if phase == .error, canRetryRecordingAfterError {
            clearRetryableRecordingError()
        }
        guard phase == .ready else {
            AppLogger.shared.log(.debug, "edit mode start ignored in phase=\(phase.rawValue)")
            showTransientIndicatorError(startBlockedMessage(for: phase), restoreState: blockedStartRestoreIndicatorState(), duration: 1.2)
            return
        }

        let selectedText = await editModeSelectionProvider.captureSelectedText()
        AppLogger.shared.log(.info, "edit mode start hasSelection=\(EditModePromptBuilder.hasSelection(selectedText))")
        await beginRecordingFlow(trigger: .editHotkey, destination: .editRewrite(selectedText: selectedText))
    }

    /// Edit Mode hotkey up: transcribe the instruction and run the rewrite.
    func finishEditModeRecording() async {
        await stopRecordingAndTranscribe(trigger: .editHotkey)
    }

    private func beginRecordingFlow(trigger: RecordingSource, destination: DictationDestination? = nil) async {
        if phase == .error, canRetryRecordingAfterError {
            clearRetryableRecordingError()
        }
        if isOnboardingBlockingRecordingStart {
            AppLogger.shared.log(.debug, "start recording ignored on the onboarding welcome screen")
            showTransientIndicatorError("Finish setup first", restoreState: .idle, duration: 1.2)
            return
        }
        guard phase == .ready else {
            AppLogger.shared.log(.debug, "start recording ignored in phase=\(phase.rawValue)")
            analytics.track(.dictationBlocked(reason: .wrongPhase))
            showTransientIndicatorError(startBlockedMessage(for: phase), restoreState: blockedStartRestoreIndicatorState(), duration: 1.2)
            return
        }
        if !hasMicPermission {
            await refreshPermissions(requestMicrophone: true, askSurface: .dictationAttempt)
        }
        // Re-read Accessibility before choosing the normal dictation route. The user
        // can grant it in System Settings while Suniye is not active.
        if destination == nil && activeOnboardingStep != .speak {
            refreshAccessibilityPermission()
        }
        let resolvedDestination = destination ?? currentDictationDestination
        guard hasMicPermission else {
            lastError = "Microphone permission not granted"
            statusText = "Permission required"
            AppLogger.shared.log(.warning, "microphone permission denied")
            analytics.track(.dictationBlocked(reason: .micDenied))
            playSoundFeedback(.error)
            showTransientIndicatorError("Microphone permission required")
            return
        }

        // Practice dictations never insert into another app, so Accessibility is
        // deliberately NOT required (or prompted for) — the whole point of the
        // Speak screen is a first dictation before the scary permission ask.
        if resolvedDestination.needsAccessibility {
            if !hasAccessibilityPermission {
                // Suppress the modal system prompt while the Permiso overlay is up:
                // two competing Accessibility grant UIs at once confuse the exact
                // moment the user is trying to grant.
                await refreshPermissions(promptAccessibility: !accessibilityOnboarding.isPresenting)
            }
            guard hasAccessibilityPermission else {
                lastError = "Accessibility permission not granted"
                statusText = "Accessibility required"
                AppLogger.shared.log(.warning, "accessibility permission denied before recording")
                analytics.track(.dictationBlocked(reason: .accessibilityDenied))
                playSoundFeedback(.error)
                showTransientIndicatorError("Enable Accessibility for dictation")
                return
            }
        }
        // Speculatively warm the local LLM while the user speaks, so cleanup runs
        // against an already-loaded model instead of paying the cold start on the
        // critical path. Fire-and-forget; idempotent and self-evicting. Edit Mode
        // sessions pass through here too, so the rewrite also starts warm.
        prewarmLocalLLMIfEligible()
        await startRecording(trigger: trigger, destination: resolvedDestination)
    }

    /// Warm the local Gemma runtime iff Magic Format is enabled and will actually
    /// resolve to the local provider. Provider resolution + config assembly live in
    /// the coordinator so this can never drift from the polish path. Returns the
    /// spawned probe task (for tests); nil when ineligible.
    @discardableResult
    func prewarmLocalLLMIfEligible() -> Task<Void, Never>? {
        guard llmEnabled else {
            return nil
        }
        return magicFormatCoordinator.prewarmLocalIfEligible(
            requestedProvider: llmProvider,
            settings: currentLLMSettings(),
            appleAvailability: appleMagicFormatAvailability,
            localGemmaAvailability: localGemmaMagicFormatAvailability
        )
    }

    private func startRecording(trigger: RecordingSource, destination: DictationDestination) async {
        guard phase == .ready else {
            return
        }

        let sessionID = UUID()
        dictationTiming = DictationTiming()
        dictationTiming.recordStart = .now()
        // Capture the target app before any Suniye UI can steal focus.
        textInsertionService.warmTargetAppAccessibility()
        let context = DictationSessionContext(
            id: sessionID,
            source: trigger,
            startedAt: Date(),
            destination: destination,
            frontmostAppBundleID: frontmostAppBundleIDProvider()
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
            emitAudioBackendUsed(session.route)
            dictationTiming.captureStarted = .now()
            startLivePreview(sessionID: sessionID)
            AppLogger.shared.log(.info, "recording started session=\(sessionID.uuidString) \(session.route.privacySafeLogValue)")
        } catch {
            guard activeAudioCaptureSessionID == sessionID else {
                return
            }
            AppLogger.shared.log(.error, "audio start failed: \(error.localizedDescription)")
            failDictationSession(
                sessionID: sessionID,
                lastErrorMessage: "Audio start failed: \(error.localizedDescription)",
                indicatorMessage: error.localizedDescription
            )
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

        stopLivePreview()
        activeDictationSession = .transcribing(context)
        phase = .transcribing
        statusText = "Transcribing..."
        setFloatingIndicatorState(Self.transcribingIndicatorState)

        let captured = await audioCaptureService.stopCapture(sessionID: sessionID)
        guard let context = activeDictationSession?.context, context.id == sessionID else {
            return
        }
        let samples = captured.samples
        let sampleRate = captured.sampleRate
        let duration = Date().timeIntervalSince(context.startedAt)
        dictationTiming.stopped = .now()
        let destination = context.destination
        AppLogger.shared.log(.info, "dictation stop samples=\(samples.count) sr=\(sampleRate) duration=\(String(format: "%.2f", duration))")

        guard captured.outcome == .complete else {
            handleAudioCaptureFailure(captured.outcome, destination: destination)
            return
        }

        do {
            dictationTiming.asrStart = .now()
            let text = try await transcriptionService.transcribe(samples: samples, sampleRate: sampleRate)
            dictationTiming.asrEnd = .now()
            let rawText = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

            switch destination {
            case let .editRewrite(selectedText):
                await finishEditModeSession(
                    instruction: rawText,
                    selectedText: selectedText,
                    sessionID: sessionID,
                    duration: duration
                )
            case .systemInsertion, .clipboardOnly:
                try await completeDictation(
                    rawText: rawText,
                    sessionID: sessionID,
                    duration: duration,
                    sampleCount: samples.count,
                    sampleRate: sampleRate,
                    frontmostAppBundleID: context.frontmostAppBundleID,
                    source: context.source,
                    destination: destination
                )
            case .onboardingPractice:
                await completeOnboardingPracticeDictation(
                    rawText: rawText,
                    sessionID: sessionID,
                    duration: duration,
                    source: context.source
                )
            }
        } catch {
            if destination == .onboardingPractice {
                onboardingPracticeText = ""
                onboardingPracticeResult = OnboardingPracticeResult(
                    message: error.localizedDescription,
                    severity: .error
                )
                recordOnboardingPracticeAttempt(outcome: .error)
            }
            AppLogger.shared.log(.error, "transcription failed: \(error.localizedDescription)")
            analytics.track(.error(type: .transcription, code: .unknown))
            failDictationSession(
                sessionID: sessionID,
                lastErrorMessage: "Transcription failed: \(error.localizedDescription)",
                indicatorMessage: "Transcription failed"
            )
        }
    }

    private func completeDictation(
        rawText: String,
        sessionID: UUID,
        duration: TimeInterval,
        sampleCount: Int,
        sampleRate: Int,
        frontmostAppBundleID: String?,
        source: RecordingSource,
        destination: DictationDestination
    ) async throws {
        let usesSystemInsertion = destination == .systemInsertion
        let rawParse = AppState.parseSubmitCommand(from: rawText)
        var shouldSubmit = usesSystemInsertion && rawParse.shouldSubmit
        var finalText = rawParse.text
        var llmOutcome: MagicFormatPolishOutcome?

        if !finalText.isEmpty {
            dictationTiming.llmStart = .now()
            let outcome = await polishOutcome(rawParse.text, frontmostAppBundleID: frontmostAppBundleID)
            dictationTiming.llmEnd = .now()
            llmOutcome = outcome
            let polishedParse = AppState.parseSubmitCommand(from: outcome.text)
            finalText = polishedParse.text
            shouldSubmit = shouldSubmit || (usesSystemInsertion && polishedParse.shouldSubmit)
        }

        if usesSystemInsertion && autoSubmitEnabled && !finalText.isEmpty {
            shouldSubmit = true
        }

        let wordCount = finalText.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        // "Polished" = a provider actually ran (not "the text changed") — the
        // honest Magic Format adoption signal.
        let wasLLMPolished = llmOutcome?.ran ?? false
        var didCompleteDictation = false
        var didFailInsertion = false
        var didInsertFinalText = finalText.isEmpty

        let result = RecentResult(
            id: UUID(),
            text: finalText,
            createdAt: Date(),
            durationSeconds: duration,
            wasLLMPolished: wasLLMPolished
        )

        // A completed system transcript must be recoverable even if insertion
        // fails because focus moved before transcription finished.
        if usesSystemInsertion && !finalText.isEmpty {
            recentResults.insert(result, at: 0)
        }

        if usesSystemInsertion && (!finalText.isEmpty || shouldSubmit) {
            try await requireAccessibilityForInsertion()
        }

        if !finalText.isEmpty {
            if usesSystemInsertion {
                editLearningService.finalizeActiveSession()
                let insertionText = DictationInsertionTextFormatter.textForInsertion(
                    finalText,
                    insertionContext: textInsertionService.captureInsertionContext()
                )
                do {
                    try await textInsertionService.insertText(insertionText)
                    didInsertFinalText = true
                    dictationTiming.inserted = .now()
                    beginEditLearningTracking(insertedText: insertionText)
                    AppLogger.shared.log(.info, "transcription complete words=\(wordCount)")
                    didCompleteDictation = true
                } catch {
                    didFailInsertion = true
                    AppLogger.shared.log(.warning, "text insertion failed: \(error.localizedDescription)")
                    playSoundFeedback(.error)
                }
            } else {
                try textInsertionService.copyTextToClipboard(finalText)
                dictationTiming.inserted = .now()
                recentResults.insert(result, at: 0)
                AppLogger.shared.log(.info, "transcription copied to clipboard words=\(wordCount)")
                didCompleteDictation = true
            }
        }

        if usesSystemInsertion && shouldSubmit && didInsertFinalText {
            if !finalText.isEmpty {
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
            try textInsertionService.submitActiveInput()
            AppLogger.shared.log(.info, "submit command executed")
            didCompleteDictation = true
        }

        if finalText.isEmpty && !shouldSubmit {
            AppLogger.shared.log(.warning, "transcription returned empty text samples=\(sampleCount) sr=\(sampleRate)")
            playSoundFeedback(.error)
            analytics.track(.dictationEmpty)
        }

        if didCompleteDictation {
            emitDictationCompleted(
                finalText: finalText,
                wordCount: wordCount,
                duration: duration,
                llmOutcome: llmOutcome,
                source: source,
                frontmostAppBundleID: frontmostAppBundleID,
                destination: destination.analyticsDestination
            )
        }

        completeDictationSession(sessionID: sessionID, playSuccessSound: didCompleteDictation)
        if didFailInsertion {
            showInsertionRecoveryWarning()
        } else {
            isShowingInsertionRecoveryWarning = false
        }
    }

    /// Records which audio-capture backend a session resolved to, whether it
    /// descended the fallback ladder, and how far (rung). Called once at capture
    /// start and again on any mid-session (async) descent.
    private func emitAudioBackendUsed(_ route: AudioRouteSnapshot) {
        analytics.track(Self.audioBackendUsedEvent(for: route))
    }

    /// The `audio_backend_used` event for a resolved capture route. Pure, so the
    /// rung / fallback derivation is unit-testable without driving live capture.
    nonisolated static func audioBackendUsedEvent(for route: AudioRouteSnapshot) -> AnalyticsEvent {
        .audioBackendUsed(
            backend: SafeLabel(route.backend.rawValue),
            // Only `.backendStartFailed` (→ standardEngine) is a real ladder
            // descent; `.bluetoothRoute` is an echo-cancellation degrade that
            // stays on the primary rung, so it must NOT count as a fallback.
            fallbackOccurred: route.fallbackReason == .backendStartFailed,
            rung: route.backend == .standardEngine ? 1 : 0
        )
    }

    private func emitDictationCompleted(
        finalText: String,
        wordCount: Int,
        duration: TimeInterval,
        llmOutcome: MagicFormatPolishOutcome?,
        source: RecordingSource,
        frontmostAppBundleID: String?,
        destination: SuniyeAnalytics.DictationDestination = .systemInsertion
    ) {
        // Pure function of the polish outcome — no live settings reads here (they
        // could have changed across the insertion suspension points, and the
        // outcome already knows what actually ran/was attempted and why).
        let cleanupProvider = llmOutcome?.provider.map { AnalyticsMapping.cleanupProvider(effective: $0) }
        let cleanupModel = llmOutcome?.model.map { SafeLabel($0) }

        let metrics = DictationMetrics(
            wordCount: wordCount,
            charCount: finalText.count,
            audioDurationMs: Int(duration * 1000),
            source: AnalyticsMapping.source(source),
            destination: destination,
            asrModel: SafeLabel(selectedASRModelID.rawValue),
            asrFamily: SafeLabel(ASRModelCatalog.entry(for: selectedASRModelID).family.rawValue),
            // The model's language coverage from the catalog (e.g. "english",
            // "multilingual") — the ASR layer doesn't return a detected language.
            language: SafeLabel(ASRModelCatalog.entry(for: selectedASRModelID).languageSummary),
            wasLLMPolished: llmOutcome?.ran ?? false,
            cleanupProvider: cleanupProvider,
            cleanupModel: cleanupModel,
            cleanupFallbackReason: llmOutcome?.fallbackReason,
            insertionMethod: .clipboard, // insertion is always clipboard+paste
            targetCategory: TargetCategoryMapper.category(for: frontmostAppBundleID),
            latency: dictationTiming.latency(),
            audio: audioRouteSnapshot.map { route in
                DictationMetrics.AudioQuality(
                    backend: SafeLabel(route.backend.rawValue),
                    fallbackReason: route.fallbackReason.map { SafeLabel($0.rawValue) },
                    inputTransport: SafeLabel(route.inputTransport.rawValue),
                    inputSampleRate: route.inputSampleRate,
                    inputChannels: route.inputChannelCount,
                    echoCancellationRequested: route.requestedEchoCancellation,
                    echoCancellationEffective: route.effectiveEchoCancellation
                )
            } ?? DictationMetrics.AudioQuality()
        )
        analytics.track(.dictationCompleted(metrics))
    }

    private func completeOnboardingPracticeDictation(
        rawText: String,
        sessionID: UUID,
        duration: TimeInterval,
        source: RecordingSource
    ) async {
        var finalText = rawText
        var llmOutcome: MagicFormatPolishOutcome?
        if !finalText.isEmpty {
            dictationTiming.llmStart = .now()
            let outcome = await polishOutcome(rawText)
            dictationTiming.llmEnd = .now()
            llmOutcome = outcome
            finalText = outcome.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        onboardingPracticeText = finalText
        var didCompleteDictation = false
        if finalText.isEmpty {
            let message = rawText.isEmpty
                ? "No speech detected. Try a short phrase."
                : "Practice mode captured audio, but there was no text to preview."
            onboardingPracticeResult = OnboardingPracticeResult(message: message, severity: .error)
            recordOnboardingPracticeAttempt(outcome: rawText.isEmpty ? .emptyAudio : .error)
            AppLogger.shared.log(.warning, "onboarding practice produced empty text")
            playSoundFeedback(.error)
        } else {
            onboardingPracticeSucceeded = true
            onboardingPracticeResult = OnboardingPracticeResult(
                message: "That's it — this works in any app.",
                severity: .success
            )
            let wordCount = finalText.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            recordOnboardingPracticeAttempt(outcome: .success)
            // The user's first-ever dictation now shows up in the funnel: same
            // dense metrics event as real dictations, with the practice
            // destination (numeric metrics only — never transcript content).
            emitDictationCompleted(
                finalText: finalText,
                wordCount: wordCount,
                duration: duration,
                llmOutcome: llmOutcome,
                source: source,
                frontmostAppBundleID: nil,
                destination: .onboardingPractice
            )
            AppLogger.shared.log(.info, "onboarding practice transcription complete words=\(wordCount)")
            didCompleteDictation = true
        }
        completeDictationSession(sessionID: sessionID, playSuccessSound: didCompleteDictation)
    }

    /// Counts a practice attempt and reports its outcome. Attempt numbers are
    /// capped so a pathological retry loop cannot inflate the metric.
    private func recordOnboardingPracticeAttempt(outcome: PracticeOutcome) {
        onboardingPracticeAttempts = min(onboardingPracticeAttempts + 1, 10)
        analytics.track(.onboardingPracticeResult(outcome: outcome, attempt: onboardingPracticeAttempts))
    }

    /// Runs the Edit Mode LLM step: rewrite the selection per the spoken instruction,
    /// or generate new text at the cursor when nothing was selected.
    private func finishEditModeSession(
        instruction: String,
        selectedText: String?,
        sessionID: UUID,
        duration: TimeInterval
    ) async {
        guard !instruction.isEmpty else {
            AppLogger.shared.log(.warning, "edit mode produced empty instruction")
            failDictationSession(sessionID: sessionID, lastErrorMessage: nil, indicatorMessage: "No instruction heard")
            return
        }

        statusText = "Rewriting..."
        setFloatingIndicatorState(.processing(message: "Rewriting..."))

        do {
            let rewritten = try await magicFormatCoordinator.rewrite(
                instructions: EditModePromptBuilder.systemPrompt(selectedText: selectedText),
                userText: EditModePromptBuilder.userText(instruction: instruction, selectedText: selectedText),
                request: makeMagicFormatRequest()
            )

            try await requireAccessibilityForInsertion()
            try await textInsertionService.insertText(rewritten)
            recentResults.insert(
                RecentResult(
                    id: UUID(),
                    text: rewritten,
                    createdAt: Date(),
                    durationSeconds: duration,
                    wasLLMPolished: true
                ),
                at: 0
            )
            AppLogger.shared.log(.info, "edit mode complete words=\(rewritten.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count)")
            completeDictationSession(sessionID: sessionID, playSuccessSound: true)
        } catch {
            AppLogger.shared.log(.error, "edit mode failed: \(error.localizedDescription)")
            failDictationSession(
                sessionID: sessionID,
                lastErrorMessage: "Edit Mode failed: \(error.localizedDescription)",
                indicatorMessage: "Rewrite failed"
            )
        }
    }

    /// Shared success epilogue for every dictation/edit session.
    private func completeDictationSession(sessionID: UUID, playSuccessSound: Bool) {
        if playSuccessSound {
            playSoundFeedback(.transcriptionSucceeded)
        }
        clearActiveDictationSession(sessionID: sessionID)
        lastError = nil
        phase = .ready
        statusText = "Ready"
        setFloatingIndicatorState(.idle)
    }

    /// Shared failure epilogue; pass nil to leave the current lastError untouched.
    private func failDictationSession(sessionID: UUID?, lastErrorMessage: String?, indicatorMessage: String) {
        clearActiveDictationSession(sessionID: sessionID)
        if let lastErrorMessage {
            lastError = lastErrorMessage
        }
        phase = .ready
        statusText = "Ready"
        playSoundFeedback(.error)
        showTransientIndicatorError(indicatorMessage)
    }

    private func requireAccessibilityForInsertion() async throws {
        if !hasAccessibilityPermission {
            // Same de-stacking rule as the recording path: never pop the modal
            // system prompt on top of an active Permiso overlay session.
            await refreshPermissions(promptAccessibility: !accessibilityOnboarding.isPresenting)
        }
        guard hasAccessibilityPermission else {
            throw NSError(domain: "Suniye", code: 1, userInfo: [NSLocalizedDescriptionKey: "Accessibility permission not granted"])
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
        analytics.track(.audioCaptureInterrupted(reason: AnalyticsMapping.interruptionReason(reason)))
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
        if destination == .onboardingPractice {
            onboardingPracticeText = ""
            onboardingPracticeResult = OnboardingPracticeResult(message: message, severity: .error)
            let audioOutcome = AnalyticsMapping.audioOutcome(outcome)
            recordOnboardingPracticeAttempt(
                outcome: audioOutcome == .silent || audioOutcome == .tooShort ? .emptyAudio : .error
            )
        }
        AppLogger.shared.log(.warning, "audio capture rejected outcome=\(String(describing: outcome))")
        analytics.track(.audioCaptureFailed(outcome: AnalyticsMapping.audioOutcome(outcome)))
        failDictationSession(
            sessionID: nil,
            lastErrorMessage: "Audio capture failed: \(message)",
            indicatorMessage: message
        )
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

    private static func normalizedPasteLastTranscriptHotkey(
        _ configuredHotkey: HotkeyConfiguration,
        dictationHotkey: HotkeyConfiguration,
        editModeHotkey: HotkeyConfiguration?
    ) -> HotkeyConfiguration {
        let fallbackModifiers: [UInt32] = [
            UInt32(controlKey | cmdKey),
            UInt32(controlKey | optionKey | cmdKey),
            UInt32(controlKey | shiftKey | cmdKey),
            UInt32(controlKey | optionKey | shiftKey | cmdKey),
        ]
        let candidates = [configuredHotkey] + fallbackModifiers.map {
            HotkeyConfiguration.keyCombo(keyCode: UInt32(kVK_ANSI_V), carbonModifiers: $0)
        }

        return candidates.first { candidate in
            candidate.isModifiedKeyCombo
                && candidate != dictationHotkey
                && candidate != editModeHotkey
        } ?? .pasteLastTranscriptDefault
    }

    private func loadGeneralSettings() {
        isHydratingGeneralSettings = true
        let settings = generalSettingsStore.load()
        let normalizedPasteLastTranscriptHotkey = Self.normalizedPasteLastTranscriptHotkey(
            settings.pasteLastTranscriptHotkeyConfiguration,
            dictationHotkey: settings.hotkeyConfiguration,
            editModeHotkey: settings.editModeHotkeyConfiguration
        )
        let normalizedEditModeHotkey = settings.editModeHotkeyConfiguration == settings.hotkeyConfiguration
            || settings.editModeHotkeyConfiguration == normalizedPasteLastTranscriptHotkey
            ? nil
            : settings.editModeHotkeyConfiguration
        let didNormalizeHotkeys = normalizedPasteLastTranscriptHotkey != settings.pasteLastTranscriptHotkeyConfiguration
            || normalizedEditModeHotkey != settings.editModeHotkeyConfiguration
        selectedInputDeviceID = settings.preferredInputDeviceID
        preferredInputDeviceName = settings.preferredInputDeviceName
        autoSubmitEnabled = settings.autoSubmitEnabled
        hotkeyConfiguration = settings.hotkeyConfiguration
        pasteLastTranscriptHotkeyConfiguration = normalizedPasteLastTranscriptHotkey
        editModeHotkeyConfiguration = normalizedEditModeHotkey
        echoCancellationEnabled = settings.echoCancellationEnabled
        soundFeedbackEnabled = settings.soundFeedbackEnabled
        hideFloatingIndicatorWhenIdle = settings.hideFloatingIndicatorWhenIdle
        liveTranscriptionPreviewEnabled = settings.liveTranscriptionPreviewEnabled
        floatingIndicatorPlacement = settings.floatingIndicatorPlacement
        selectedASRModelID = settings.selectedASRModelID
        updateChannel = settings.updateChannel
        accessibilityDragHelperEnabled = settings.accessibilityDragHelperEnabled
        shareAnalyticsEnabled = settings.shareAnalyticsEnabled
        let legacyUserHasUsage = legacyUserShowsUsage(settings: settings)
        let needsFirstLaunchMigration = settings.onboardingProgress == nil
            && (settings.hasSeenOnboardingWelcome == true
                || settings.hasCompletedCoreOnboarding == true
                || legacyUserHasUsage)
        firstLaunchRecorded = settings.firstLaunchRecorded || needsFirstLaunchMigration
        lastKnownAccessibilityGranted = settings.lastKnownAccessibilityGranted
        magicFormatNudgeDismissed = settings.magicFormatNudgeDismissed
        localGemmaDownloadCancelled = settings.localGemmaDownloadCancelled

        let needsProgressMigration = settings.onboardingProgress == nil
        onboardingProgress = settings.onboardingProgress ?? OnboardingProgress.migrating(
            hasSeenOnboardingWelcome: settings.hasSeenOnboardingWelcome,
            hasCompletedCoreOnboarding: settings.hasCompletedCoreOnboarding,
            legacyUserShowsUsage: legacyUserHasUsage
        )
        isHydratingGeneralSettings = false
        applyUpdateChannelToController()
        if needsProgressMigration || needsFirstLaunchMigration || didNormalizeHotkeys {
            persistGeneralSettings()
        }
    }

    /// The legacy auto-complete heuristic for installs that predate the
    /// onboarding flags: only real usage signals count. The old version also
    /// keyed on `autoSubmitEnabled`/`echoCancellationEnabled`, which meant a
    /// future default flip could have silently skipped onboarding for every
    /// fresh install.
    private func legacyUserShowsUsage(settings: GeneralSettings) -> Bool {
        isModelInstalled
            || !recentResults.isEmpty
            || settings.preferredInputDeviceID != nil
            || settings.hotkeyConfiguration != .globe
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
            pasteLastTranscriptHotkeyConfiguration: pasteLastTranscriptHotkeyConfiguration,
            editModeHotkeyConfiguration: editModeHotkeyConfiguration,
            echoCancellationEnabled: echoCancellationEnabled,
            soundFeedbackEnabled: soundFeedbackEnabled,
            hideFloatingIndicatorWhenIdle: hideFloatingIndicatorWhenIdle,
            liveTranscriptionPreviewEnabled: liveTranscriptionPreviewEnabled,
            floatingIndicatorPlacement: floatingIndicatorPlacement,
            // Legacy Bools still written (derived) so a downgraded build keeps
            // working; `onboardingProgress` wins on load in this build.
            hasSeenOnboardingWelcome: hasSeenOnboardingWelcome,
            hasCompletedCoreOnboarding: hasCompletedCoreOnboarding,
            onboardingProgress: onboardingProgress,
            firstLaunchRecorded: firstLaunchRecorded,
            lastKnownAccessibilityGranted: lastKnownAccessibilityGranted,
            magicFormatNudgeDismissed: magicFormatNudgeDismissed,
            localGemmaDownloadCancelled: localGemmaDownloadCancelled,
            selectedASRModelID: selectedASRModelID,
            updateChannel: updateChannel,
            accessibilityDragHelperEnabled: accessibilityDragHelperEnabled,
            shareAnalyticsEnabled: shareAnalyticsEnabled
        )
    }

    private func loadLLMSettings() {
        let settings = llmSettingsStore.load()
        let migration = settings.normalizedForCurrentPromptSchema()
        let syncedSettings = magicFormatPromptFileStore.syncPrompts(settings: migration.settings)
        applyLLMSettings(syncedSettings)

        if migration.shouldPersist || syncedSettings != settings {
            persistLLMSettings()
        }
    }

    private func persistLLMSettings() {
        guard !isHydratingLLMSettings else {
            return
        }
        clearMagicFormatSetupTestResult()
        let settings = currentLLMSettings()
        llmSettingsStore.save(settings)
        onStateChange?()
    }

    private func saveProviderPromptFile(_ prompt: MagicFormatProviderPromptFile, content: String) {
        guard !isHydratingLLMSettings else {
            return
        }
        magicFormatPromptFileStore.saveProviderPrompt(prompt, content: content)
    }

    private func applyLLMSettings(_ settings: LLMSettings) {
        isHydratingLLMSettings = true
        llmEnabled = settings.isEnabled
        llmProvider = settings.provider
        llmSelectedModelPreset = settings.selectedModelPreset
        localModelKeepAlive = settings.localModelKeepAlive
        llmCustomModelId = settings.customModelId
        llmEndpointURLString = settings.endpointURLString
        llmBaseSystemPrompt = settings.baseSystemPrompt
        llmAppleSystemPrompt = settings.appleSystemPrompt
        llmGemmaSystemPrompt = settings.gemmaSystemPrompt
        llmSystemPrompt = ""
        llmKeywordsRaw = settings.keywordsRaw
        llmAutoLearnedKeywordsRaw = settings.autoLearnedKeywordsRaw
        learnFromEditsEnabled = settings.learnFromEditsEnabled
        llmAppPromptBindings = settings.appPromptBindings
        llmTimeoutSeconds = LLMDefaults.defaultTimeoutSeconds
        llmMaxTokens = LLMDefaults.defaultMaxTokens
        isHydratingLLMSettings = false
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
            autoLearnedKeywordsRaw: llmAutoLearnedKeywordsRaw,
            learnFromEditsEnabled: learnFromEditsEnabled,
            timeoutSeconds: LLMDefaults.defaultTimeoutSeconds,
            maxTokens: LLMDefaults.defaultMaxTokens,
            localModelKeepAlive: localModelKeepAlive,
            appPromptBindings: llmAppPromptBindings
        )
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

    private var insertionRecoveryMessage: String {
        "Couldn't insert text. Focus a text field, then press \(pasteLastTranscriptHotkeyConfiguration.compactDisplayString)."
    }

    private func showInsertionRecoveryWarning() {
        let restoreState = blockedStartRestoreIndicatorState()
        isShowingInsertionRecoveryWarning = true
        lastError = insertionRecoveryMessage
        showTransientIndicatorError(insertionRecoveryMessage, restoreState: restoreState, duration: 3.5)
    }

    private func clearInsertionRecoveryWarning() {
        guard isShowingInsertionRecoveryWarning else {
            return
        }

        isShowingInsertionRecoveryWarning = false
        lastError = nil
        overlayErrorResetTask?.cancel()
        overlayErrorResetTask = nil
        if case .error = floatingIndicatorState {
            setFloatingIndicatorState(blockedStartRestoreIndicatorState())
        }
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
            if case let .listening(levels, source, preview) = floatingIndicatorState {
                return .listening(levels: levels, source: source, preview: preview)
            }
            return .listening(
                levels: Self.defaultIndicatorLevels(level: 0.72),
                source: activeRecordingSource ?? .manual
            )
        case .transcribing:
            // Preserve whatever processing stage the pill has advanced to
            // ("Starting local model...", "Polishing..."); the phase stays
            // .transcribing through the whole post-stop pipeline.
            if case .processing = floatingIndicatorState {
                return floatingIndicatorState
            }
            return Self.transcribingIndicatorState
        case .needsModel, .downloadingModel, .loading, .ready, .error:
            return .idle
        }
    }

    private var currentDictationDestination: DictationDestination {
        if activeOnboardingStep == .speak {
            return .onboardingPractice
        }
        return hasAccessibilityPermission ? .systemInsertion : .clipboardOnly
    }

    private func clearActiveDictationSession(sessionID: UUID? = nil) {
        guard sessionID == nil || activeAudioCaptureSessionID == sessionID else {
            return
        }
        activeDictationSession = nil
        stopLivePreview()
    }

    private func startLivePreview(sessionID: UUID) {
        guard liveTranscriptionPreviewEnabled, phase == .recording, activeAudioCaptureSessionID == sessionID else {
            return
        }
        // Partial decodes queue ahead of the final decode on the TranscriptionService
        // actor, so live preview is limited to families whose decode cost scales with
        // the audio window instead of a fixed full-window pass.
        let activeModelID = loadedASRModelID ?? selectedASRModelID
        guard ASRModelCatalog.entry(for: activeModelID).family.supportsLivePreview else {
            AppLogger.shared.log(.debug, "live preview disabled for model family id=\(activeModelID.rawValue)")
            return
        }
        let audioCaptureService = audioCaptureService
        let transcriptionService = transcriptionService
        lastPublishedPartialTranscript = ""
        // Reserve the bubble's panel space now (`.pending`), before the first
        // partial lands — the panel must never resize mid-recording.
        if case let .listening(levels, source, _) = floatingIndicatorState {
            setFloatingIndicatorState(.listening(levels: levels, source: source, preview: .pending))
        }
        partialTranscriptionScheduler.start(
            snapshotProvider: {
                await audioCaptureService.snapshotSamples(
                    sessionID: sessionID,
                    maxDurationSeconds: PartialTranscriptionScheduler.maxWindowSeconds
                )
            },
            decode: { samples, sampleRate in
                do {
                    return try await transcriptionService.transcribe(samples: samples, sampleRate: sampleRate, purpose: .partial)
                } catch {
                    // Partial decodes skip TranscriptionService's per-decode logging;
                    // failures are the one thing worth a line.
                    AppLogger.shared.log(.warning, "partial decode failed: \(error.localizedDescription)")
                    throw error
                }
            },
            onPartial: { [weak self] text in
                self?.publishLivePartialTranscript(text, sessionID: sessionID)
            }
        )
    }

    private func stopLivePreview() {
        partialTranscriptionScheduler.stop()
        livePartialTranscript = nil
        lastPublishedPartialTranscript = ""
        // Strip a preview that is still visible (e.g. toggled off mid-recording);
        // level updates would otherwise keep carrying it forward.
        if case let .listening(levels, source, preview) = floatingIndicatorState, preview != .off {
            setFloatingIndicatorState(.listening(levels: levels, source: source, preview: .off))
        }
    }

    private func publishLivePartialTranscript(_ text: String, sessionID: UUID) {
        // Belt-and-braces: the scheduler's generation guard already suppresses late
        // partials (every path that leaves .recording stops the preview first); this
        // re-check additionally protects any future path that forgets to.
        guard phase == .recording, activeAudioCaptureSessionID == sessionID else {
            return
        }
        // Keep already-shown words stable across re-decodes; only the tail may change.
        let stabilized = PartialTranscriptStabilizer.stabilize(
            previous: lastPublishedPartialTranscript,
            current: text
        )
        lastPublishedPartialTranscript = stabilized
        let preview = FloatingIndicatorMetrics.previewTail(stabilized)
        livePartialTranscript = preview.isEmpty ? nil : preview
        if case let .listening(levels, source, _) = floatingIndicatorState {
            // An empty decode keeps `.pending` (space stays reserved), it does
            // not fall back to `.off`.
            setFloatingIndicatorState(.listening(
                levels: levels,
                source: source,
                preview: preview.isEmpty ? .pending : .text(preview)
            ))
        }
    }

    /// Derived rule, not an enumerated step list: only the welcome screen blocks
    /// the hotkey. The Speak screen hosts the practice dictation and the
    /// Accessibility screen allows real dictation (e.g. the Notes demo).
    private var isOnboardingBlockingRecordingStart: Bool {
        activeOnboardingStep == .welcome
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

    private func handleAudioLevelsUpdate(_ levels: [Float]) {
        guard case let .listening(_, source, preview) = floatingIndicatorState else {
            return
        }
        setFloatingIndicatorState(.listening(levels: levels, source: source, preview: preview))
    }

    private static func defaultIndicatorLevels(level: Float, count: Int = AudioLevelMeter.bandCount) -> [Float] {
        Array(repeating: max(0, min(level, 1)), count: count)
    }

    /// Single source for the pill's transcribing state so the transcribe transition
    /// and the blocked-start restore path can never render it differently.
    private static let transcribingIndicatorState: FloatingIndicatorState = .processing(message: "Transcribing...")

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
