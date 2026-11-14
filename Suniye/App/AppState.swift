import AppKit
import AVFoundation
import Foundation
import Observation
import SuniyeAnalytics

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
                AppLogger.shared.log(.info, "phase changed: \(oldValue.rawValue) -> \(phase.rawValue)")
            }
            if (oldValue == .recording) != (phase == .recording) {
                hotkeyService.setCancelShortcutEnabled(phase == .recording)
            }
        }
    }
    var lastError: String?

    /// Every change goes through `updateGeneralSettings`, which saves it and
    /// applies its effects in `generalSettingsDidChange(from:)`.
    private(set) var generalSettings = GeneralSettings()

    var autoSubmitEnabled: Bool {
        get { generalSettings.autoSubmitEnabled }
        set { updateGeneralSettings { $0.autoSubmitEnabled = newValue } }
    }
    var echoCancellationEnabled: Bool {
        get { generalSettings.echoCancellationEnabled }
        set { updateGeneralSettings { $0.echoCancellationEnabled = newValue } }
    }
    var soundFeedbackEnabled: Bool {
        get { generalSettings.soundFeedbackEnabled }
        set { updateGeneralSettings { $0.soundFeedbackEnabled = newValue } }
    }
    /// Opt-out toggle for anonymous usage analytics (default on).
    var shareAnalyticsEnabled: Bool {
        get { generalSettings.shareAnalyticsEnabled }
        set { updateGeneralSettings { $0.shareAnalyticsEnabled = newValue } }
    }
    var hideFloatingIndicatorWhenIdle: Bool {
        get { generalSettings.hideFloatingIndicatorWhenIdle }
        set { updateGeneralSettings { $0.hideFloatingIndicatorWhenIdle = newValue } }
    }
    var liveTranscriptionPreviewEnabled: Bool {
        get { generalSettings.liveTranscriptionPreviewEnabled }
        set { updateGeneralSettings { $0.liveTranscriptionPreviewEnabled = newValue } }
    }
    /// Kill switch for the Permiso drag-to-grant Accessibility overlay.
    /// When false, the Accessibility buttons fall back to the System Settings deep-link.
    var accessibilityDragHelperEnabled: Bool {
        get { generalSettings.accessibilityDragHelperEnabled }
        set { updateGeneralSettings { $0.accessibilityDragHelperEnabled = newValue } }
    }
    var floatingIndicatorPlacement: FloatingIndicatorPlacement? {
        get { generalSettings.floatingIndicatorPlacement }
        set { updateGeneralSettings { $0.floatingIndicatorPlacement = newValue } }
    }
    var selectedASRModelID: ASRModelID {
        get { generalSettings.selectedASRModelID }
        set { updateGeneralSettings { $0.selectedASRModelID = newValue } }
    }
    var updateChannel: UpdateChannel {
        get { generalSettings.updateChannel }
        set { updateGeneralSettings { $0.updateChannel = newValue } }
    }
    var hotkeyConfiguration: HotkeyConfiguration {
        get { generalSettings.hotkeyConfiguration }
        set { changeHotkeys(generalSettings.hotkeys.settingDictation(newValue)) }
    }
    var pasteLastTranscriptHotkeyConfiguration: HotkeyConfiguration {
        generalSettings.pasteLastTranscriptHotkeyConfiguration
    }
    var editModeHotkeyConfiguration: HotkeyConfiguration? {
        get { generalSettings.editModeHotkeyConfiguration }
        set { changeHotkeys(generalSettings.hotkeys.settingEditMode(newValue)) }
    }
    var hotkeyValidationMessage: String?
    /// Every transition goes through the onboarding functions, so that
    /// persistence, analytics and the active step agree.
    var onboardingProgress: OnboardingProgress {
        generalSettings.onboardingProgress ?? .notStarted
    }
    var hasSeenOnboardingWelcome: Bool { onboardingProgress != .notStarted }
    var hasCompletedCoreOnboarding: Bool { onboardingProgress.isFinished }

    var canCheckForUpdates = false
    var isUpdateReadyToInstall = false
    var canRestartToUpdate: Bool {
        isUpdateReadyToInstall && !isCapturing
    }
    var automaticallyChecksForUpdates = false
    var appVersionText: String {
        currentAppVersionProvider()?.displayString ?? "Unknown"
    }

    var downloadProgress: Double = 0
    /// The model that downloads to become the meeting transcript model.
    private(set) var meetingTranscriptModelDownload: ASRModelID?
    /// Counts the transcript model choices, so an older one never wins.
    @ObservationIgnored private var meetingTranscriptModelChoice = 0
    var modelDownloadStartedAt: Date?
    /// One model operation at a time. Downloads and loads were split into
    /// separate slots so an installed model could be selected mid-download; the
    /// resulting concurrent phase/progress state proved to be a source of races
    /// (stranded captures, progress reset by unrelated operations, deferrals
    /// reported as failures), so operations are serialised again. Reintroducing
    /// concurrency needs a real per-operation model, not a second slot.
    var activeASRModelOperationID: ASRModelID?

    var loadedASRModelID: ASRModelID? {
        didSet {
            if oldValue != loadedASRModelID {
                meetings.speechModelChanged(loadedASRModelID)
            }
        }
    }
    var lastFailedASRModelID: ASRModelID?
    var lastFailedASRModelError: String?
    let library: DictationLibrary
    var recentResults: [RecentResult] {
        get { library.results }
        set { library.replaceResults(newValue) }
    }
    var dictationStats: DictationStats { library.stats }

    @ObservationIgnored private(set) lazy var microphone = MicrophoneChoice(
        audioCaptureService: audioCaptureService,
        settings: { [unowned self] in generalSettings },
        updateSettings: { [unowned self] change in updateGeneralSettings(change) },
        echoCancellationEnabled: { [unowned self] in dictationEchoCancellationEnabled },
        isDictating: { [unowned self] in activeDictationSession != nil }
    )
    /// Echo cancellation (voice processing) lowers the volume of other audio
    /// while it runs; during a meeting that would lower the call.
    private var dictationEchoCancellationEnabled: Bool {
        echoCancellationEnabled && meetings.live == nil
    }


    var activeOnboardingStep: OnboardingStep? {
        didSet {
            guard oldValue != activeOnboardingStep else {
                return
            }
            if activeOnboardingStep != .speak {
                onboardingPracticeResult = nil
            }
            trackOnboardingStepShownIfNeeded()
        }
    }
    var onboardingPracticeText = ""
    var onboardingPracticeResult: OnboardingPracticeResult?
    private(set) var onboardingRun = OnboardingRun()
    /// User-facing reason the Get Started preflight refused to start (disk space).
    var onboardingDiskSpaceMessage: String?
    /// The Permiso overlay timed out with no grant — surface a visible hint
    /// instead of the old silent disappearance.
    private(set) var accessibilityAssistTimedOut = false
    /// macOS reset a previously-working Accessibility grant (signing-identity
    /// change / TCC reset). Suniye is still listed in System Settings, so the
    /// drag overlay would mislead; the UI shows remove-and-re-add copy instead.
    private(set) var accessibilityGrantLikelyStale = false

    /// A stale entry stays switched on in System Settings while macOS ignores
    /// it, so toggling it is not reliable. Removing it drops the old code
    /// requirement; adding it back records the current one.
    var staleAccessibilityGrantInstruction: String {
        let name = AppIdentity.current.displayName
        return "macOS reset this permission after an update. In the Accessibility list, select \(name), remove it with −, then add it back with +."
    }

    /// A start still waiting on a permission prompt; a key release clears it.
    @ObservationIgnored private var pendingRecordingStart: RecordingSource?
    @ObservationIgnored private var dictationShortcutGesture = DictationShortcutGesture()
    @ObservationIgnored private var secondTapWindowTask: Task<Void, Never>?
    @ObservationIgnored private var previousTapWithDoubleTapOff: Date?
    private(set) var systemGlobeKeyAction: SystemGlobeKeyAction = .doNothing
    @ObservationIgnored private var hasTrackedMagicFormatNudgeShown = false

    var hasMicPermission = false
    /// True when the mic authorization is `.denied`/`.restricted` — the system
    /// prompt can never re-appear, so Enable buttons must become Open Settings.
    var hasMicPermissionBeenDenied = false
    var hasAccessibilityPermission = false

    @ObservationIgnored private(set) lazy var issueReport = IssueReportForm(
        uploadService: issueReportUploadService,
        diagnosticBundleService: diagnosticBundleService,
        context: { [unowned self] in issueReportContext() },
        nowProvider: nowProvider,
        fileOpener: fileOpener,
        temporaryFileCleanupScheduler: temporaryFileCleanupScheduler,
        diagnosticsDestinationPicker: issueReportDiagnosticsDestinationPicker
    )

    /// Every change goes through `updateLLMSettings`, which saves it and
    /// applies its effects in `llmSettingsDidChange(from:)`.
    private(set) var llmSettings = LLMSettings()

    var llmEnabled: Bool {
        get { llmSettings.isEnabled }
        set { updateLLMSettings { $0.isEnabled = newValue } }
    }
    var llmProvider: MagicFormatProvider {
        get { llmSettings.provider }
        set { updateLLMSettings { $0.provider = newValue } }
    }
    var llmSelectedModelPreset: LLMModelPreset {
        get { llmSettings.selectedModelPreset }
        set { updateLLMSettings { $0.selectedModelPreset = newValue } }
    }
    var localModelKeepAlive: LocalLLMKeepAlive {
        get { llmSettings.localModelKeepAlive }
        set { updateLLMSettings { $0.localModelKeepAlive = newValue } }
    }
    var llmCustomModelId: String {
        get { llmSettings.customModelId }
        set { updateLLMSettings { $0.customModelId = newValue } }
    }
    var llmEndpointURLString: String {
        get { llmSettings.endpointURLString }
        set { updateLLMSettings { $0.endpointURLString = newValue } }
    }
    var llmBaseSystemPrompt: String {
        get { llmSettings.baseSystemPrompt }
        set { updateLLMSettings { $0.baseSystemPrompt = newValue } }
    }
    var llmAppleSystemPrompt: String {
        get { llmSettings.appleSystemPrompt }
        set { updateLLMSettings { $0.appleSystemPrompt = newValue } }
    }
    var llmGemmaSystemPrompt: String {
        get { llmSettings.gemmaSystemPrompt }
        set { updateLLMSettings { $0.gemmaSystemPrompt = newValue } }
    }
    var llmKeywordsRaw: String {
        get { llmSettings.keywordsRaw }
        set { updateLLMSettings { $0.keywordsRaw = newValue } }
    }
    var llmAutoLearnedKeywordsRaw: String {
        get { llmSettings.autoLearnedKeywordsRaw }
        set { updateLLMSettings { $0.autoLearnedKeywordsRaw = newValue } }
    }
    var learnFromEditsEnabled: Bool {
        get { llmSettings.learnFromEditsEnabled }
        set { updateLLMSettings { $0.learnFromEditsEnabled = newValue } }
    }
    var llmAppPromptBindings: [AppPromptBinding] {
        get { llmSettings.appPromptBindings }
        set { updateLLMSettings { $0.appPromptBindings = newValue } }
    }
    var hasLLMAPIKey = false
    var llmKeyOperationError: String?
    var isMagicFormatSetupTestInProgress = false
    /// Which engine the running test belongs to. The engine chooser lets you test
    /// a row before switching to it, so "a test is running" is not enough — the
    /// UI needs to know whose.
    var magicFormatTestingProvider: MagicFormatProvider?
    /// Which engine produced the standing result. A success from one engine must
    /// not be read as certifying another.
    private(set) var magicFormatLastTestedProvider: MagicFormatProvider?
    /// The configuration the standing API result was produced with: key,
    /// endpoint and model together. Editing any of them after a success means
    /// the success no longer describes what would run.
    private(set) var magicFormatLastTestedAPIFingerprint: Int?
    var magicFormatSetupTestResult: MagicFormatSetupTestResult? {
        didSet {
            if magicFormatSetupTestResult == nil {
                magicFormatLastTestedProvider = nil
                magicFormatLastTestedAPIFingerprint = nil
            }
        }
    }
    private var magicFormatSetupTestRequestID = 0
    var localGemmaInstallState: LocalLLMInstallState = .notInstalled {
        didSet {
            if oldValue != localGemmaInstallState {
                meetings.summaries.availabilityChanged()
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

    var isModelInstalled: Bool {
        modelManager.isInstalled(selectedASRModelID)
    }

    /// Masked stand-in for a stored key: enough to recognise which key is saved,
    /// never enough to use it. Without it the field reads "Paste API key" while
    /// the status says Connected, which looks like nothing is stored.
    private(set) var llmAPIKeyHint: String?
    private(set) var currentLLMAPIKeyFingerprint: Int?

    /// Whether the *API endpoint* specifically has been verified. Testing Local
    /// Gemma or Apple Intelligence sets the shared result too, and that must not
    /// certify an endpoint the user has never tested — nor may a success against
    /// an unsaved draft key certify whatever key is actually stored.
    var isAPIMagicFormatSetupVerified: Bool {
        guard magicFormatSetupTestResult?.severity == .success,
              magicFormatLastTestedProvider == .openAICompatible,
              let testedFingerprint = magicFormatLastTestedAPIFingerprint,
              let keyFingerprint = currentLLMAPIKeyFingerprint
        else {
            return false
        }
        return testedFingerprint == Self.apiConfigurationFingerprint(
            keyFingerprint: keyFingerprint,
            settings: llmSettings
        )
    }

    /// One value for "the API configuration that would run right now", so a
    /// test result can be tied to it and invalidated by any edit.
    private static func apiConfigurationFingerprint(keyFingerprint: Int, settings: LLMSettings) -> Int {
        var hasher = Hasher()
        hasher.combine(keyFingerprint)
        hasher.combine(settings.endpointURLString)
        hasher.combine(settings.validatedModelId ?? "")
        return hasher.finalize()
    }



    /// Deliberately does not require the API engine to be the one in use: the
    /// set-up sheet exists so an endpoint can be configured and tested *before*
    /// switching to it.
    func canTestMagicFormatSetup(apiKeyDraft: String) -> Bool {
        guard llmEnabled, !isMagicFormatSetupTestInProgress else {
            return false
        }
        guard apiEndpointDraftValidationError == nil, apiModelDraftValidationError == nil else {
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
        return llmSettings.endpointValidationError
    }

    /// Validity of the API settings themselves, whatever engine is active. The
    /// scoped properties above answer "should the page complain right now";
    /// these answer "is this endpoint usable", which is what the set-up sheet
    /// and its Test button need before the API engine is ever selected.
    var apiEndpointDraftValidationError: String? {
        llmSettings.endpointValidationError
    }

    var apiModelDraftValidationError: String? {
        llmSettings.modelValidationError
    }

    var llmModelValidationError: String? {
        guard needsAPIConfigurationForMagicFormat else {
            return nil
        }
        return llmSettings.modelValidationError
    }

    var vocabularyTerms: [String] {
        llmSettings.keywords
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

    /// The engine whose settings the Magic Format page shows and edits.
    var activeMagicFormatEngine: MagicFormatEngine {
        llmProvider.engine(
            appleAvailable: appleMagicFormatAvailability.isAvailable,
            localGemmaAvailable: localGemmaMagicFormatAvailability.isAvailable
        )
    }

    var usesAppleMagicFormatSettings: Bool {
        activeMagicFormatEngine == .appleFoundationModels
    }

    var usesLocalGemmaMagicFormatSettings: Bool {
        activeMagicFormatEngine == .localGemma
    }

    var usesLocalMagicFormatSettings: Bool {
        activeMagicFormatEngine != .openAICompatible
    }

    var needsAPIConfigurationForMagicFormat: Bool {
        activeMagicFormatEngine == .openAICompatible
    }

    /// The prompt of the active engine, for the instructions editor.
    var activeMagicFormatPrompt: String {
        get { llmSettings[keyPath: activeMagicFormatEngine.promptKeyPath] }
        set {
            let keyPath = activeMagicFormatEngine.promptKeyPath
            updateLLMSettings { $0[keyPath: keyPath] = newValue }
        }
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

    var lastTranscriptText: String? {
        library.lastTranscriptText
    }

    var modelExpectedByteCount: Int64 {
        modelManager.expectedDownloadSizeBytes(for: activeASRModelOperationID ?? selectedASRModelID)
    }

    var modelExpectedSizeText: String {
        "~" + ByteCountFormatter.string(fromByteCount: modelExpectedByteCount, countStyle: .file)
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

    func asrModelCanPerformPrimaryAction(for modelID: ASRModelID) -> Bool {
        guard activeASRModelOperationID == nil else {
            return false
        }

        guard phase != .recording && phase != .transcribing else {
            return false
        }

        return !(loadedASRModelID == modelID && selectedASRModelID == modelID)
    }

    /// Whether the model's files are on disk. System-managed models answer
    /// `false` here because their asset is owned by macOS, not by us.
    func isASRModelDownloaded(_ modelID: ASRModelID) -> Bool {
        modelManager.isInstalled(modelID)
    }

    /// Whether a system-managed model's OS asset is actually cached. Only
    /// answerable asynchronously, which is why callers cannot simply treat
    /// "system-managed" as "installed" — an uncached asset means a large
    /// OS-managed download.
    func isSystemManagedASRAssetInstalled(_ modelID: ASRModelID) async -> Bool {
        await modelManager.isSystemManagedAssetInstalled(modelID)
    }

    func asrModelSecondaryActionsEnabled(for modelID: ASRModelID) -> Bool {
        // System-managed models (Apple Speech) have no on-disk folder to open and can't
        // be deleted by us, so hide the folder/trash actions for them.
        guard !ASRModelCatalog.entry(for: modelID).isSystemManaged else {
            return false
        }
        return modelManager.isInstalled(modelID)
            && activeASRModelOperationID == nil
            && phase != .recording
            && phase != .transcribing
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

    /// On and off need no explanation \u{2014} the switch says which it is. Only the
    /// states where the switch does not tell the whole truth are worth surfacing.
    var launchAtLoginWarningText: String? {
        switch launchAtLoginStatus {
        case .requiresApproval, .unsupported:
            return launchAtLoginStatus.detailText
        case .enabled, .disabled:
            return nil
        }
    }

    var launchAtLoginEnabledForUI: Bool {
        launchAtLoginStatus.isEnabledForUI
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
            && !generalSettings.magicFormatNudgeDismissed
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
        updateGeneralSettings { $0.magicFormatNudgeDismissed = true }
    }

    /// The nudge's CTA: records the open, retires the card, and hands the
    /// caller the section to navigate to (the existing Magic Format settings
    /// page, which already handles provider choice, unavailability, and repair).
    func openMagicFormatSetupFromNudge() -> MainWindowSection {
        analytics.track(.mfNudge(action: .opened))
        updateGeneralSettings { $0.magicFormatNudgeDismissed = true }
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
                    detail: accessibilityGrantLikelyStale
                        ? staleAccessibilityGrantInstruction
                        : "Grant accessibility access so transcribed text can be inserted.",
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
    let meetings: MeetingCoordinator
    /// A section that code outside the main window asked to show. The window
    /// shows it and clears the request.
    var requestedSection: MainWindowSection?
    @ObservationIgnored private var callCardPresenter: MeetingCallCardPresenter?
    private let localLLMModelManager: LocalLLMModelManagerProtocol
    private let llmSettingsStore: LLMSettingsStoreProtocol
    private let magicFormatPromptFileStore: MagicFormatPromptFileStoreProtocol
    private let generalSettingsStore: GeneralSettingsStoreProtocol
    private let keychainService: KeychainServiceProtocol
    private let appUpdateController: AppUpdateControllerProtocol
    private let launchAtLoginService: LaunchAtLoginServiceProtocol
    private let diagnosticBundleService: DiagnosticBundleServiceProtocol
    private let issueReportUploadService: IssueReportUploadServiceProtocol
    private let analytics: Analytics
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
    /// Same trust read, but macOS shows its "allow Accessibility" dialog when the
    /// process is not trusted.
    private let accessibilityTrustPrompter: () -> Bool
    private let systemGlobeKeyActionProvider: () -> SystemGlobeKeyAction
    /// Injectable free-disk probe for the onboarding download preflight.
    private let availableDiskCapacityProvider: () async -> Int64?
    private let issueReportDiagnosticsDestinationPicker: @MainActor (String) -> URL?
    private let temporaryFileCleanupScheduler: (URL) -> Void
    private let magicFormatSlowWarningDelaySeconds: TimeInterval
    private let runtimeServicesEnabled: Bool
    private let floatingIndicatorEnabled: Bool

    /// One dictation, from the start of capture to the end of its text. While
    /// it runs, `microphone.audioRouteSnapshot` is the route it records from.
    private struct DictationSession {
        let id: UUID
        let source: RecordingSource
        let startedAt: Date
        let destination: DictationDestination
        /// The app the user was in when recording started, for per-app prompts.
        let frontmostAppBundleID: String?
        var timing = DictationTiming()
        var lockedByDoubleTap = false
    }

    /// How a session ends. Every end goes through `endSession`.
    private enum SessionEnd {
        case completed(playSound: Bool)
        /// A nil `lastError` keeps the current one.
        case failed(lastError: String?, notice: String)
        case discarded(notice: String?)
    }

    private var activeDictationSession: DictationSession? {
        didSet {
            if (oldValue == nil) != (activeDictationSession == nil) {
                meetings.dictationChanged(active: activeDictationSession != nil)
            }
        }
    }
    private var activeAudioCaptureSessionID: UUID? { activeDictationSession?.id }
    private var activeRecordingSource: RecordingSource? { activeDictationSession?.source }
    private var overlayErrorResetTask: Task<Void, Never>?
    private var isShowingInsertionRecoveryWarning = false
    /// A dictation without Accessibility still runs, to the clipboard only. The
    /// system Accessibility dialog is raised for the first such dictation per
    /// launch; later ones get the not-pasted notice without the dialog.
    @ObservationIgnored private var hasPromptedAccessibilityForClipboardDictation = false
    private var asrDownloadTask: Task<Void, Never>?
    private var localGemmaDownloadTask: Task<Void, Never>?
    private var localGemmaDownloadID: UUID?
    private var localGemmaDownloadStartedAt: Date?
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
        statsStore: DictationStatsStoring = DictationStatsStore.makeDefault(),
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
        accessibilityTrustPrompter: @escaping () -> Bool = {
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        },
        systemGlobeKeyActionProvider: @escaping () -> SystemGlobeKeyAction = SystemGlobeKeyAction.current,
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
        meetingCoordinator: MeetingCoordinator? = nil,
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
        // One client, so Magic Format and meeting summaries share one llama-server.
        let localGemmaClient = LocalGemmaLlamaCppClient(
            locator: LocalGemmaRuntimeLocator(modelManager: localLLMModelManager),
            server: LlamaServer(
                onModelLoad: { model, loadMs in
                    analytics.track(.modelLoad(model: SafeLabel(model), loadMs: loadMs, evictedByKeepAlive: false))
                },
                onKeepAliveEvicted: { model in
                    analytics.track(.modelLoad(model: SafeLabel(model), loadMs: 0, evictedByKeepAlive: true))
                }
            )
        )
        let resolvedLocalGemmaPostProcessor = localGemmaMagicFormatPostProcessor ?? LocalGemmaPostProcessor(
            client: localGemmaClient,
            onGeneration: { timings in
                analytics.track(.llmGeneration(
                    model: SafeLabel(LocalGemmaDefaults.modelDisplayName),
                    promptTokens: timings.promptTokens,
                    cachedTokens: timings.cachedTokens,
                    predictedTokens: timings.predictedTokens,
                    prefillMs: timings.prefillMs,
                    decodeMs: timings.decodeMs
                ))
            }
        )
        self.localGemmaMagicFormatPostProcessor = resolvedLocalGemmaPostProcessor
        self.magicFormatCoordinator = MagicFormatCoordinator(
            apiPostProcessor: llmPostProcessor,
            applePostProcessor: appleMagicFormatPostProcessor,
            localGemmaPostProcessor: resolvedLocalGemmaPostProcessor
        )
        self.meetings = meetingCoordinator ?? AppState.makeMeetingCoordinator(
            transcriptionService: transcriptionService,
            modelManager: modelManager,
            appleSummaryAvailability: { appleMagicFormatPostProcessor.availability },
            localSummaryAvailability: { resolvedLocalGemmaPostProcessor.availability },
            localGemmaClient: localGemmaClient,
            analytics: analytics
        )
        self.llmSettingsStore = llmSettingsStore
        self.magicFormatPromptFileStore = magicFormatPromptFileStore
        self.generalSettingsStore = generalSettingsStore
        self.library = DictationLibrary(historyStore: historyStore, statsStore: statsStore)
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
        self.accessibilityTrustPrompter = accessibilityTrustPrompter
        self.systemGlobeKeyActionProvider = systemGlobeKeyActionProvider
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
        self.meetings.host = self
        self.meetings.onNotice = { [weak self] notice in
            self?.showMeetingNotice(notice)
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
                    microphone.applyInputDevices(devices)
                    microphone.refreshAudioRouteSnapshot()
                case let .routeChanged(sessionID, route):
                    guard activeAudioCaptureSessionID == sessionID else { return }
                    microphone.adoptSessionRoute(route)
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
        loadGeneralSettings()
        loadLLMSettings()
        analytics.setEnabled(shareAnalyticsEnabled)
        refreshUpdateControllerState()
        microphone.refreshInputDevices()
        refreshLaunchAtLoginStatus()
        refreshLLMKeyStatus()
        refreshLocalGemmaInstallState()
        refreshSystemGlobeKeyAction()

        if floatingIndicatorEnabled {
            floatingIndicatorController.onAction = { [weak self] in
                self?.toggleFloatingIndicatorRecording()
            }
            floatingIndicatorController.onMeetingAction = { [weak self] action in
                self?.handleMeetingPillAction(action)
            }
            meetings.onLiveChange = { [weak self] session in
                self?.floatingIndicatorController.updateMeeting(session)
            }
            let callCardPresenter = MeetingCallCardPresenter(meetings: meetings) { [weak self] in
                self?.openMainWindow(at: .general)
            }
            self.callCardPresenter = callCardPresenter
            meetings.onCallCardChange = { card in
                callCardPresenter.show(card)
            }
            floatingIndicatorController.onPlacementChanged = { [weak self] placement in
                self?.handleFloatingIndicatorPlacementChanged(placement)
            }
            syncFloatingIndicatorPreferences()
        }

        if startServices {
            analytics.start()
            stopMeetingAtSleep()
            emitAppLaunchEvent()
            presentOnboardingIfNeeded()
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
            firstLaunch: !generalSettings.firstLaunchRecorded
        ))
        if !generalSettings.firstLaunchRecorded {
            // Dedicated flag (not the onboarding position): quitting on the
            // welcome screen must not re-count as a new install next launch.
            updateGeneralSettings { $0.firstLaunchRecorded = true }
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
            "double_tap": .label(AnalyticsMapping.doubleTapAvailability(conflict: globeDoubleTapConflict)),
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
        await meetings.start()
        await refreshPermissions()

        var bootstrapCandidates = orderedInstalledASRModelIDs()
        // A chosen system-managed model (Apple Speech) has no files, so the
        // installed list never contains it; without this it was silently replaced
        // by whichever downloaded model came first on every launch.
        if ASRModelCatalog.entry(for: selectedASRModelID).isSystemManaged,
           modelManager.isInstalled(selectedASRModelID) {
            bootstrapCandidates.insert(selectedASRModelID, at: 0)
        }
        if bootstrapCandidates.isEmpty, !onboardingProgress.isFinished {
            phase = .loading
            if await adoptSystemDefaultModel() {
                phase = .ready
                lastError = nil
            } else {
                phase = .needsModel
            }
        } else if !bootstrapCandidates.isEmpty {
            phase = .loading
            do {
                let bootstrapModelID = try await loadFirstAvailableASRModel(from: bootstrapCandidates)
                if bootstrapModelID != selectedASRModelID {
                    selectedASRModelID = bootstrapModelID
                }
                phase = .ready
                lastError = nil
            } catch {
                phase = .error
                lastError = "Model load failed: \(error.localizedDescription)"
            }
            activeASRModelOperationID = nil
        } else {
            phase = .needsModel
        }
        startOnboardingIfNeeded()
        resumeInterruptedLocalGemmaDownloadIfNeeded()
        setFloatingIndicatorState(.idle)
        AppLogger.shared.log(.info, "bootstrap done")
    }

    /// A fresh install starts on the built-in model when it really works here, so
    /// the first dictation needs no download. Every failed step falls back to the
    /// downloaded default; the outcome and reason go to the log and analytics.
    private func adoptSystemDefaultModel() async -> Bool {
        let startedAt = nowProvider()
        func report(_ outcome: SystemDefaultModelOutcome, _ reason: SystemDefaultModelReason?, _ modelID: ASRModelID?) {
            analytics.track(.systemDefaultModel(
                outcome: outcome,
                reason: reason,
                model: modelID.map { SafeLabel($0.rawValue) },
                durationMs: Int(nowProvider().timeIntervalSince(startedAt) * 1000)
            ))
        }

        let check = await modelManager.systemDefaultModelCheck()
        guard case let .ready(modelID) = check else {
            if case let .unavailable(reason, detail) = check {
                AppLogger.shared.log(.info, "system default model unavailable: \(detail)")
                report(.unavailable, reason, nil)
            }
            return false
        }
        activeASRModelOperationID = modelID
        defer { activeASRModelOperationID = nil }
        do {
            try await loadRecognizer(for: modelID)
        } catch {
            AppLogger.shared.log(.warning, "system default model load failed id=\(modelID.rawValue) error=\(error.localizedDescription)")
            report(.failed, .loadFailed, modelID)
            return false
        }
        do {
            // One silent decode proves the engine runs, not just that it loads.
            _ = try await transcriptionService.transcribe(
                samples: [Float](repeating: 0, count: 16_000),
                sampleRate: 16_000,
                purpose: .probe
            )
        } catch {
            AppLogger.shared.log(.warning, "system default model decode failed id=\(modelID.rawValue) error=\(error.localizedDescription)")
            await transcriptionService.unloadModel()
            loadedASRModelID = nil
            report(.failed, .decodeFailed, modelID)
            return false
        }
        selectedASRModelID = modelID
        AppLogger.shared.log(.info, "system default model adopted id=\(modelID.rawValue)")
        report(.adopted, nil, modelID)
        return true
    }

    // MARK: - Onboarding state machine

    /// Resumes onboarding at the persisted position (or dismisses it once
    /// finished). Steps re-shown by resume carry `resumed=true` in analytics.
    func startOnboardingIfNeeded() {
        presentOnboardingIfNeeded()
        guard activeOnboardingStep != nil else {
            return
        }
        // Any step, not just Welcome: a relaunch that resumes mid-flow must not
        // wait on a download that nothing restarts.
        startOnboardingModelDownloadIfNeeded()
    }

    /// Shows the persisted step without touching the model, so the window opens
    /// on onboarding instead of flashing the main page while bootstrap runs.
    func presentOnboardingIfNeeded() {
        guard let step = onboardingProgress.resumeStep else {
            activeOnboardingStep = nil
            return
        }
        guard activeOnboardingStep == nil else {
            return
        }
        onboardingRun.begin(at: nowProvider(), resumed: onboardingProgress != .notStarted)
        activeOnboardingStep = step
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
            return
        }
        setOnboardingProgress(.speakReached)
        onboardingRun.pendingAdvance = .button
        activeOnboardingStep = .speak
        if !isModelInstalled, activeASRModelOperationID == nil {
            startModelDownload()
        }
        // Ask now, as the answer to this click, so the first fn hold records
        // instead of opening a system prompt mid-hold.
        if !hasMicPermission, !hasMicPermissionBeenDenied {
            await refreshPermissions(requestMicrophone: true, askSurface: .onboarding)
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
        }
    }

    /// Accessibility is settled (or skipped by closing): name what else exists
    /// before handing off. Not persisted as its own position: a relaunch resumes
    /// on the Accessibility screen, which leads straight back here.
    func advanceOnboardingFromTypeAnywhere(by advance: OnboardingAdvance = .button) {
        guard activeOnboardingStep == .typeAnywhere else {
            return
        }
        onboardingRun.pendingAdvance = advance
        activeOnboardingStep = .more
    }

    func advanceOnboardingFromSpeak() {
        guard activeOnboardingStep == .speak else {
            return
        }
        onboardingRun.leaveSpeak(withText: onboardingPracticeText)
        onboardingRun.pendingAdvance = .button
        setOnboardingProgress(.typeAnywhereReached)
        activeOnboardingStep = .typeAnywhere
    }

    /// Terminal transition (Finish on the closing screen, or closing the window on
    /// the last two screens). This is where completion is persisted and the
    /// `completed` + `onboarding_outcome` events fire — after the flow actually
    /// ends, not before the practice step as the old wizard did.
    func finishOnboarding(endedBy: OnboardingEnd = .finishButton) {
        guard activeOnboardingStep != nil else {
            return
        }
        let durationMs = onboardingElapsedMs
        analytics.track(.onboardingStep(step: .completed, granted: nil, resumed: nil, elapsedMs: durationMs))
        analytics.track(.onboardingOutcome(
            durationMs: durationMs,
            practiced: onboardingRun.practiceSucceeded,
            micGranted: hasMicPermission,
            axGranted: hasAccessibilityPermission,
            modelReady: asrModelReady,
            endedBy: endedBy,
            practiceEdited: onboardingRun.practiceSucceeded ? onboardingRun.practiceEdited : nil
        ))
        setOnboardingProgress(.finished)
        onboardingPracticeText = ""
        onboardingPracticeResult = nil
        onboardingRun.end()
        activeOnboardingStep = nil
        NotificationCenter.default.post(name: .suniyeOnboardingDidFinish, object: self)
    }

    /// Returns true when the app goes back to a menu-bar app. The Dock icon
    /// stays while onboarding is unfinished, as a second way back to it.
    func mainWindowWillClose() -> Bool {
        if let step = activeOnboardingStep {
            if step.closingTheWindowFinishesOnboarding {
                finishOnboarding(endedBy: .windowClosed)
            } else {
                recordOnboardingWindowClosed()
            }
        }
        return onboardingProgress.isFinished
    }

    /// The window was closed on a step that does not finish onboarding (Welcome
    /// or the practice screen): where people walk away.
    func recordOnboardingWindowClosed() {
        guard let step = activeOnboardingStep else {
            return
        }
        analytics.track(.onboardingWindowClosed(step: step.analyticsName, elapsedMs: onboardingElapsedMs))
    }

    private var onboardingElapsedMs: Int? {
        onboardingRun.elapsedMs(at: nowProvider())
    }

    /// A dictation that really lands in another app proves the Accessibility
    /// step, so the window moves on by itself to the closing screen.
    private func advanceOnboardingAfterFirstInsertionIfNeeded(appBundleID: String?) {
        guard activeOnboardingStep == .typeAnywhere,
              let appBundleID,
              appBundleID != Bundle.main.bundleIdentifier else {
            return
        }
        AppLogger.shared.log(.info, "onboarding advanced by first insertion app=\(appBundleID)")
        advanceOnboardingFromTypeAnywhere(by: .insertion)
    }

    private func setOnboardingProgress(_ progress: OnboardingProgress) {
        updateGeneralSettings { $0.setOnboardingProgress(progress) }
    }

    /// The one emission point for onboarding_step, once per step and run, so
    /// that a resume and navigation cannot count a step twice.
    private func trackOnboardingStepShownIfNeeded() {
        guard let shown = onboardingRun.stepShown(activeOnboardingStep), let step = activeOnboardingStep else {
            return
        }
        analytics.track(.onboardingStep(
            step: step.analyticsName,
            granted: nil,
            resumed: shown.resumed ? true : nil,
            elapsedMs: onboardingElapsedMs,
            advancedBy: shown.advancedBy
        ))
    }

    /// True while dictation prerequisites for the Speak screen's practice box
    /// are met: installed model that is loaded or actively usable.
    var asrModelReady: Bool {
        isModelInstalled && (phase == .ready || phase == .recording || phase == .transcribing)
    }

    /// Download + staged copy coexist on disk, hence twice the download size.
    private func modelDownloadDiskSpaceMessage(for modelID: ASRModelID? = nil) async -> String? {
        let neededBytes = modelManager.expectedDownloadSizeBytes(for: modelID ?? selectedASRModelID) * 2
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
        let accessibilityGranted = promptAccessibility ? accessibilityTrustPrompter() : accessibilityTrustProvider()

        if !priorMic, hasMicPermission {
            analytics.track(.permissionTransition(kind: .microphone, granted: true))
        }
        setAccessibilityPermission(accessibilityGranted)

        AppLogger.shared.log(.info, "permissions: mic=\(hasMicPermission) ax=\(hasAccessibilityPermission)")
    }

    /// Re-reads Accessibility without changing microphone state. This matters when
    /// the user grants access in System Settings while Suniye is not active.
    private func refreshAccessibilityPermission() {
        setAccessibilityPermission(accessibilityTrustProvider())
    }

    private enum AccessibilityGrantSource {
        case trustCheck
        /// The overlay grant does not send `permission_transition` today. The
        /// gap is kept so that the analytics data does not change in a refactor.
        case permisoOverlay
    }

    /// The one writer of `hasAccessibilityPermission`. It also records the last
    /// observed trust, so that a later `false` reads as a stale grant (app
    /// update, TCC reset) and not as a grant that never happened: the two need
    /// different recovery text.
    private func setAccessibilityPermission(_ granted: Bool, source: AccessibilityGrantSource = .trustCheck) {
        let wasGranted = hasAccessibilityPermission
        hasAccessibilityPermission = granted
        if source == .trustCheck, !wasGranted, granted {
            analytics.track(.permissionTransition(kind: .accessibility, granted: true))
        }
        if granted {
            accessibilityGrantLikelyStale = false
            accessibilityAssistTimedOut = false
            updateGeneralSettings { $0.lastKnownAccessibilityGranted = true }
        } else {
            accessibilityGrantLikelyStale = generalSettings.lastKnownAccessibilityGranted
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
        // instruction would mislead; deep-link with remove-and-re-add copy instead.
        if generalSettings.lastKnownAccessibilityGranted, !hasAccessibilityPermission {
            accessibilityGrantLikelyStale = true
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
                self.setAccessibilityPermission(true, source: .permisoOverlay)
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

    func refreshSystemGlobeKeyAction() {
        let action = systemGlobeKeyActionProvider()
        if action != systemGlobeKeyAction {
            systemGlobeKeyAction = action
        }
    }

    func openKeyboardSettings() {
        openSystemSettings(urlCandidates: [
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.keyboard",
        ])
    }

    func openAppleIntelligenceSettings() {
        openSystemSettings(urlCandidates: [
            "x-apple.systempreferences:com.apple.Siri-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.speech",
            "x-apple.systempreferences:",
        ])
    }

    func handleSystemWillSleep() async {
        await audioCaptureService.handleSystemSleep()
    }

    func handleSystemDidWake() {
        audioCaptureService.handleSystemWake()
        microphone.refreshInputDevices()
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
    }

    func refreshLLMKeyStatus() {
        hasLLMAPIKey = keychainService.hasLLMKey()
        refreshLLMKeyDerivedState()
    }

    /// The masked hint and the fingerprint are read once per key change rather
    /// than per SwiftUI body evaluation: both derive from the keychain, and a
    /// synchronous credential read does not belong on the render path.
    private func refreshLLMKeyDerivedState() {
        guard let key = try? keychainService.getLLMKey()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty
        else {
            llmAPIKeyHint = nil
            currentLLMAPIKeyFingerprint = nil
            return
        }
        currentLLMAPIKeyFingerprint = key.hashValue
        let dots = "\u{2022}\u{2022}\u{2022}\u{2022}"
        // The hint must stay a hint: a prefix plus a tail recovers most of a
        // short key, so anything that short is masked outright.
        llmAPIKeyHint = key.count >= 24
            ? "\(key.prefix(4)) \(dots) \(dots) \(key.suffix(4))"
            : "\(dots) \(dots)"
    }

    func saveLLMAPIKey(_ key: String) {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            llmKeyOperationError = "API key can't be empty."
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
        }
    }

    func clearMagicFormatSetupTestResult() {
        magicFormatSetupTestRequestID += 1
        isMagicFormatSetupTestInProgress = false
        magicFormatTestingProvider = nil
        magicFormatSetupTestResult = nil
    }

    func testMagicFormatSetup(apiKeyDraft: String) async {
        clearMagicFormatSetupTestResult()
        guard llmEnabled,
              let endpointURL = llmSettings.validatedEndpointURL,
              let modelId = llmSettings.validatedModelId,
              let apiKey = effectiveMagicFormatTestAPIKey(apiKeyDraft: apiKeyDraft) else {
            return
        }
        // The configuration this run used, so that a success against an unsaved
        // draft key, or against an endpoint or model edited later, cannot
        // certify what is stored now.
        let fingerprint = Self.apiConfigurationFingerprint(keyFingerprint: apiKey.hashValue, settings: llmSettings)
        let config = MagicFormatCoordinator.makeAPIConfig(
            settings: llmSettings,
            apiKey: apiKey,
            endpointURL: endpointURL,
            modelId: modelId
        )
        await runMagicFormatSetupTest(
            .openAICompatible,
            logName: "magic format",
            logDetail: " model=\(config.modelId)",
            successMessage: "Connection works.",
            testedAPIFingerprint: fingerprint,
            failure: { error in
                guard let error = error as? LLMPostProcessorError else {
                    return ("Couldn't reach that service URL.", " reason=unknown")
                }
                return (magicFormatSetupTestMessage(for: error), " reason=\(error.logValue)")
            }
        ) { [llmPostProcessor] in
            try await llmPostProcessor.testSetup(config: config)
        }
    }

    /// Runs one engine's setup test. Only the newest test may write the result.
    private func runMagicFormatSetupTest(
        _ engine: MagicFormatEngine,
        logName: String,
        logDetail: String = "",
        successMessage: String,
        testedAPIFingerprint: Int? = nil,
        failure: (Error) -> (message: String, logDetail: String),
        test: () async throws -> Void
    ) async {
        let requestID = magicFormatSetupTestRequestID
        isMagicFormatSetupTestInProgress = true
        magicFormatTestingProvider = MagicFormatProvider(engine)
        magicFormatLastTestedProvider = MagicFormatProvider(engine)
        magicFormatLastTestedAPIFingerprint = testedAPIFingerprint
        let startTime = Date()
        defer {
            if requestID == magicFormatSetupTestRequestID {
                isMagicFormatSetupTestInProgress = false
                magicFormatTestingProvider = nil
            }
        }

        do {
            try await test()
            guard requestID == magicFormatSetupTestRequestID else {
                AppLogger.shared.log(.info, "ignored stale \(logName) setup test success")
                return
            }
            let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
            magicFormatSetupTestResult = MagicFormatSetupTestResult(message: successMessage, severity: .success, latencyMs: latencyMs)
            AppLogger.shared.log(.info, "\(logName) setup test success\(logDetail) latency_ms=\(latencyMs)")
        } catch {
            let (message, failureLogDetail) = failure(error)
            guard requestID == magicFormatSetupTestRequestID else {
                AppLogger.shared.log(.info, "ignored stale \(logName) setup test failure\(failureLogDetail)")
                return
            }
            magicFormatSetupTestResult = MagicFormatSetupTestResult(message: message, severity: .error)
            let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
            AppLogger.shared.log(.warning, "\(logName) setup test failed\(failureLogDetail)\(logDetail) latency_ms=\(latencyMs)")
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
        llmSettings.autoLearnedKeywords
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

    func openCurrentMagicFormatPromptInEditor() {
        _ = fileOpener(currentMagicFormatPromptURL)
    }

    var currentMagicFormatPromptURL: URL {
        magicFormatPromptFileStore.providerPromptURL(activeMagicFormatEngine)
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
        updateGeneralSettings { $0.localGemmaDownloadCancelled = false }
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
              !generalSettings.localGemmaDownloadCancelled,
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
        updateGeneralSettings { $0.localGemmaDownloadCancelled = true }
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

    /// Same shape as the local model test: run the engine once and report how
    /// long it took, so "is this fast enough to sit in my dictation path?" is
    /// answerable before committing to it.
    func testAppleMagicFormatSetup() async {
        clearMagicFormatSetupTestResult()
        guard llmEnabled else {
            return
        }
        guard appleMagicFormatAvailability.isAvailable else {
            magicFormatSetupTestResult = MagicFormatSetupTestResult(message: appleMagicFormatAvailability.statusText, severity: .error)
            return
        }
        let config = MagicFormatCoordinator.makeAppleConfig(settings: llmSettings)
        await runMagicFormatSetupTest(
            .appleFoundationModels,
            logName: "apple",
            successMessage: "Apple Intelligence works.",
            failure: { error in (error.localizedDescription, "") }
        ) { [appleMagicFormatPostProcessor] in
            try await appleMagicFormatPostProcessor.testSetup(config: config)
        }
    }

    func testLocalGemmaSetup() async {
        clearMagicFormatSetupTestResult()
        guard llmEnabled else {
            return
        }
        guard localGemmaInstallState.isInstalled else {
            magicFormatSetupTestResult = MagicFormatSetupTestResult(message: "Download the local model first.", severity: .error)
            return
        }
        let config = MagicFormatCoordinator.makeLocalGemmaConfig(settings: llmSettings)
        await runMagicFormatSetupTest(
            .localGemma,
            logName: "local gemma",
            successMessage: "Local model works.",
            failure: { error in
                (localGemmaSetupTestMessage(for: error), " error=\(error.localizedDescription)")
            }
        ) { [localGemmaMagicFormatPostProcessor] in
            try await localGemmaMagicFormatPostProcessor.testSetup(config: config)
        }
    }

    /// Reports whether the pasteboard took the text, so that a caller does not
    /// confirm a copy that left the clipboard empty.
    func copyText(_ text: String) -> Bool {
        (try? textInsertionService.copyTextToClipboard(text)) != nil
    }

    func copyOriginalTranscript(_ text: String) -> Bool {
        guard copyText(text) else {
            return false
        }
        analytics.track(.rawTranscript(action: .copied))
        return true
    }

    func originalTranscriptOpened() {
        analytics.track(.rawTranscript(action: .opened))
    }

    @discardableResult
    func copyLastTranscript() -> Bool {
        guard let text = lastTranscriptText else {
            return false
        }
        return copyText(text)
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

    func startModelDownload() {
        downloadASRModel(selectedASRModelID, autoSelect: true)
    }

    func deleteModel() {
        deleteASRModel(selectedASRModelID)
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
        guard phase != .recording && phase != .transcribing else {
            return
        }
        guard activeASRModelOperationID == nil else {
            return
        }

        let hadLoadedModel = loadedASRModelID != nil
        activeASRModelOperationID = modelID
        phase = .loading
        lastError = nil
        lastFailedASRModelID = nil
        lastFailedASRModelError = nil

        // Held in the same handle the file-based downloads use, so an OS asset
        // fetch is cancellable too — it was running in an unassigned Task, which
        // left the Cancel action hidden for a download of the same size.
        asrDownloadTask = Task {
            do {
                let assetInstalled = await modelManager.isSystemManagedAssetInstalled(modelID)
                if !assetInstalled {
                    phase = .downloadingModel
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
                }

                try await loadRecognizer(for: modelID)
                selectedASRModelID = modelID
                phase = .ready
                lastError = nil
                lastFailedASRModelID = nil
                lastFailedASRModelError = nil
                AppLogger.shared.log(.info, "system-managed model ready id=\(modelID.rawValue)")
            } catch {
                if Self.isCancellation(error) {
                    if modelDownloadStartedAt != nil {
                        trackModelDownload(kind: .asr, model: modelID.rawValue, outcome: .canceled, startedAt: modelDownloadStartedAt)
                    }
                    downloadProgress = 0
                    if hadLoadedModel {
                        setPhaseUnlessCapturing(.ready)
                    } else {
                        setPhaseUnlessCapturing(.needsModel)
                    }
                    lastError = nil
                    AppLogger.shared.log(.info, "system-managed asset download canceled id=\(modelID.rawValue)")
                } else {
                    if modelDownloadStartedAt != nil {
                        trackModelDownload(kind: .asr, model: modelID.rawValue, outcome: .failed, startedAt: modelDownloadStartedAt)
                    }
                    handleASRModelOperationFailure(
                        for: modelID,
                        error: error,
                        fallbackToReadyState: hadLoadedModel
                    )
                }
            }

            activeASRModelOperationID = nil
            modelDownloadStartedAt = nil
            asrDownloadTask = nil
        }
    }

    func downloadASRModel(_ modelID: ASRModelID, autoSelect: Bool) {
        guard phase != .recording && phase != .transcribing else {
            return
        }
        guard activeASRModelOperationID == nil else {
            return
        }

        let hadLoadedModel = loadedASRModelID != nil
        activeASRModelOperationID = modelID
        phase = .downloadingModel
        lastError = nil
        lastFailedASRModelID = nil
        lastFailedASRModelError = nil
        downloadProgress = 0
        modelDownloadStartedAt = nowProvider()
        trackModelDownload(kind: .asr, model: modelID.rawValue, outcome: .started)

        asrDownloadTask = Task {
            do {
                if let message = await modelDownloadDiskSpaceMessage(for: modelID) {
                    throw AppStateError.insufficientDiskSpace(message)
                }
                AppLogger.shared.log(.info, "model download started id=\(modelID.rawValue)")
                try await modelManager.downloadAndExtractModel(modelID) { [weak self] progress in
                    Task { @MainActor in
                        self?.downloadProgress = progress
                    }
                }

                setPhaseUnlessCapturing(.loading)

                guard await modelManager.isSystemManagedAssetInstalled(modelID) else {
                    throw AppStateError.modelValidationFailed
                }

                trackModelDownload(kind: .asr, model: modelID.rawValue, outcome: .completed, startedAt: modelDownloadStartedAt)
                modelDownloadStartedAt = nil

                if autoSelect {
                    do {
                        try await loadRecognizer(for: modelID)
                        selectedASRModelID = modelID
                        setPhaseUnlessCapturing(.ready)
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
                        setPhaseUnlessCapturing(.ready)
                    } else {
                        setPhaseUnlessCapturing(.needsModel)
                    }
                    lastFailedASRModelID = nil
                    lastFailedASRModelError = nil
                }
            } catch {
                if Self.isCancellation(error) {
                    trackModelDownload(kind: .asr, model: modelID.rawValue, outcome: .canceled, startedAt: modelDownloadStartedAt)
                    downloadProgress = 0
                    if hadLoadedModel {
                        setPhaseUnlessCapturing(.ready)
                    } else {
                        setPhaseUnlessCapturing(.needsModel)
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
        guard phase != .recording && phase != .transcribing else {
            return
        }
        guard activeASRModelOperationID == nil else {
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
        lastError = nil
        lastFailedASRModelID = nil
        lastFailedASRModelError = nil

        Task {
            do {
                try await loadRecognizer(for: modelID)
                selectedASRModelID = modelID
                phase = .ready
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
        guard phase != .recording && phase != .transcribing else {
            return
        }
        guard activeASRModelOperationID == nil else {
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
                    do {
                        let fallbackModelID = try await loadFirstAvailableASRModel(from: fallbackCandidates)
                        selectedASRModelID = fallbackModelID
                        phase = .ready
                        lastError = nil
                    } catch {
                        phase = .error
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
                setPhaseUnlessCapturing(.error)
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

    func openMainWindow(at section: MainWindowSection? = nil) {
        if let section {
            requestedSection = section
        }
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

    func openIssueReportWindow() {
        issueReport.windowWillOpen()
        IssueReportWindowController.shared.show(form: issueReport)
    }

    func toggleFloatingIndicatorRecording() {
        Task { @MainActor in
            switch phase {
            case .ready:
                await beginRecordingFlow(trigger: .manual)
            case .recording where activeRecordingSource == .manual:
                await stopRecordingAndTranscribe(trigger: .manual)
            case .recording where activeRecordingSource == .hotkey && activeDictationSession?.lockedByDoubleTap == true:
                resetDictationShortcutGesture()
                await stopRecordingAndTranscribe(trigger: .hotkey)
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
        changeHotkeys(generalSettings.hotkeys.settingPasteLastTranscript(configuration))
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

    func restartToUpdate() {
        guard canRestartToUpdate else {
            AppLogger.shared.log(.info, "sparkle restart to update refused ready=\(isUpdateReadyToInstall) phase=\(phase.rawValue)")
            return
        }
        AppLogger.shared.log(.info, "sparkle restart to update")
        analytics.track(.updateAction(kind: .restartToUpdate, fromVersion: nil, toVersion: nil))
        appUpdateController.installUpdateAndRelaunch()
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
        isUpdateReadyToInstall = appUpdateController.isUpdateReadyToInstall
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

        var settings = llmSettings
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
            settings: settings ?? llmSettings,
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

    private func wireHotkey() {
        hotkeyService.onHotkeyDown = { [weak self] in
            AppLogger.shared.log(.debug, "hotkey callback: down")
            Task { @MainActor in
                await self?.handleDictationShortcutPress()
            }
        }

        hotkeyService.onHotkeyUp = { [weak self] in
            AppLogger.shared.log(.debug, "hotkey callback: up")
            Task { @MainActor in
                await self?.handleDictationShortcutRelease()
            }
        }

        hotkeyService.onHotkeyChord = { [weak self] in
            Task { @MainActor in
                self?.dictationShortcutGesture.markChord()
            }
        }

        hotkeyService.onCancel = { [weak self] in
            AppLogger.shared.log(.debug, "cancel shortcut callback")
            Task { @MainActor in
                await self?.cancelRecording()
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

    /// The model that would take over if `modelID` were deleted — the same
    /// candidate list `deleteASRModel` falls back through, so the confirmation
    /// cannot name a different model than the one that actually loads.
    func asrModelFallbackAfterDeleting(_ modelID: ASRModelID) -> ASRModelCatalogEntry? {
        orderedInstalledASRModelIDs(excluding: [modelID]).first.map { ASRModelCatalog.entry(for: $0) }
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

    /// Phase belongs to the dictation pipeline. A background download must never
    /// move it out from under an active capture: `stopRecording` guards on
    /// `phase == .recording`, so clobbering it mid-dictation strands the capture
    /// and the hotkey release silently does nothing.
    private var isCapturing: Bool {
        phase == .recording || phase == .transcribing
    }

    private func setPhaseUnlessCapturing(_ newPhase: Phase) {
        guard !isCapturing else {
            return
        }
        phase = newPhase
    }

    private func handleASRModelOperationFailure(for modelID: ASRModelID, error: Error, fallbackToReadyState: Bool) {
        let message = Self.friendlyModelDownloadMessage(for: error) ?? error.localizedDescription
        downloadProgress = 0
        lastFailedASRModelID = modelID
        lastFailedASRModelError = message

        if fallbackToReadyState, loadedASRModelID != nil {
            setPhaseUnlessCapturing(.ready)
            lastError = nil
            return
        }

        setPhaseUnlessCapturing(.error)
        lastError = message
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
            AppLogger.shared.log(.warning, "edit mode blocked: magic format not ready")
            playSoundFeedback(.error)
            showTransientIndicatorError("Set up Magic Format to use Edit Mode", restoreState: blockedStartRestoreIndicatorState())
            return
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

    private var isRecordingFromDictationShortcut: Bool {
        phase == .recording && activeRecordingSource == .hotkey
    }

    /// The macOS action that a Globe tap also runs, when it keeps double-tap off.
    var globeDoubleTapConflict: SystemGlobeKeyAction? {
        guard hotkeyConfiguration.kind == .globe, systemGlobeKeyAction != .doNothing else {
            return nil
        }
        return systemGlobeKeyAction
    }

    private func handleDictationShortcutPress() async {
        if isRecordingFromDictationShortcut {
            cancelSecondTapWindow()
        } else {
            resetDictationShortcutGesture()
        }
        if dictationShortcutGesture.press(at: nowProvider()) {
            await beginRecordingFlow(trigger: .hotkey)
        }
    }

    private func handleDictationShortcutRelease() async {
        guard isRecordingFromDictationShortcut else {
            resetDictationShortcutGesture()
            // Also cancels a start that a permission prompt still holds open.
            await stopRecordingAndTranscribe(trigger: .hotkey)
            return
        }
        let releasedAt = nowProvider()
        var tapCouldNotLock = false
        let command = dictationShortcutGesture.release(at: releasedAt) {
            // The user can change the macOS setting while Suniye is in the background.
            if hotkeyConfiguration.kind == .globe {
                refreshSystemGlobeKeyAction()
            }
            tapCouldNotLock = globeDoubleTapConflict != nil
            return !tapCouldNotLock
        }
        switch command {
        case .finish:
            await stopRecordingAndTranscribe(trigger: .hotkey)
        case .discard where tapCouldNotLock:
            AppLogger.shared.log(.info, "recording discarded: tap with double-tap off")
            await discardTapWithDoubleTapOff(releasedAt: releasedAt)
        case .discard:
            AppLogger.shared.log(.info, "recording discarded: short press")
            await discardShortPress()
        case .waitForSecondTap:
            startSecondTapWindow()
        case .lock:
            lockDictationRecording()
        case nil:
            break
        }
    }

    private func startSecondTapWindow() {
        let sessionID = activeAudioCaptureSessionID
        secondTapWindowTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(DictationShortcutGesture.tapInterval))
            guard let self, !Task.isCancelled, activeAudioCaptureSessionID == sessionID else {
                return
            }
            secondTapWindowTask = nil
            if dictationShortcutGesture.secondTapWindowEnded() {
                AppLogger.shared.log(.info, "recording discarded: single tap")
                await discardShortPress()
            }
        }
    }

    /// A locked recording is hands-free, like one started from the pill, so the
    /// pill takes the same look and a click on it finishes the recording.
    private func lockDictationRecording() {
        AppLogger.shared.log(.info, "recording locked by double tap")
        activeDictationSession?.lockedByDoubleTap = true
        if case let .listening(levels, _, preview) = floatingIndicatorState {
            setFloatingIndicatorState(.listening(levels: levels, source: .manual, preview: preview))
        }
    }

    private func resetDictationShortcutGesture() {
        dictationShortcutGesture.reset()
        cancelSecondTapWindow()
    }

    private func cancelSecondTapWindow() {
        secondTapWindowTask?.cancel()
        secondTapWindowTask = nil
    }

    /// A second quick tap means the user tried to double-tap. The Settings
    /// notice alone went unnoticed, so the pill says why nothing happened.
    private func discardTapWithDoubleTapOff(releasedAt: Date) async {
        let isSecondTap = previousTapWithDoubleTapOff.map {
            releasedAt.timeIntervalSince($0) < DictationShortcutGesture.tapInterval * 2
        } ?? false
        previousTapWithDoubleTapOff = isSecondTap ? nil : releasedAt
        guard isSecondTap else {
            await discardShortPress()
            return
        }
        await discardRecording(message: "Double-tap is off. See Settings.")
    }

    /// Onboarding practice still tells a new user to hold the key, as it did
    /// when such a press was rejected as too short.
    private func discardShortPress() async {
        if activeDictationSession?.destination == .onboardingPractice,
           let message = AudioCaptureOutcome.tooShort.userMessage {
            reportFailedPractice(message: message, outcome: Self.practiceOutcome(for: .tooShort))
        }
        await discardRecording(message: nil)
    }

    private func cancelRecording() async {
        AppLogger.shared.log(.info, "recording canceled with Esc")
        // A key release that ran first already sent the recording to
        // transcription; that dictation is not a cancel.
        if await discardRecording(message: "Dictation canceled") {
            analytics.track(.dictationCancelled(stage: .recording))
        }
    }

    /// Ends the recording with no transcription, no paste and no error sound.
    /// Returns false when no recording was there to end.
    @discardableResult
    private func discardRecording(message: String?) async -> Bool {
        guard phase == .recording, let sessionID = activeAudioCaptureSessionID else {
            return false
        }
        resetDictationShortcutGesture()
        endSession(sessionID, .discarded(notice: message))
        await audioCaptureService.cancelCapture(sessionID: sessionID, reason: nil)
        return true
    }

    private func beginRecordingFlow(trigger: RecordingSource, destination: DictationDestination? = nil) async {
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
        // Permission prompts below can hold this start open for as long as a
        // system dialog is up; a release in that window must cancel it, or
        // recording begins after the key is already up and nothing ends it.
        pendingRecordingStart = trigger
        defer {
            if pendingRecordingStart == trigger {
                pendingRecordingStart = nil
            }
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
                AppLogger.shared.log(.warning, "accessibility permission denied before recording")
                analytics.track(.dictationBlocked(reason: .accessibilityDenied))
                playSoundFeedback(.error)
                showTransientIndicatorError("Enable Accessibility for dictation")
                return
            }
        }
        // The Permiso overlay already asks for the grant; a system dialog on top
        // of it would compete, and would use up this launch's one prompt.
        if resolvedDestination == .clipboardOnly,
           !hasPromptedAccessibilityForClipboardDictation,
           !accessibilityOnboarding.isPresenting {
            hasPromptedAccessibilityForClipboardDictation = true
            AppLogger.shared.log(.warning, "accessibility not granted; prompting, dictation will be copied, not pasted")
            await refreshPermissions(promptAccessibility: true)
        }
        guard pendingRecordingStart == trigger else {
            AppLogger.shared.log(.info, "recording start canceled: key released during a permission prompt")
            analytics.track(.dictationBlocked(reason: .releasedDuringPrompt))
            showTransientIndicatorError("Hold again to dictate", restoreState: .idle, duration: 1.6)
            return
        }
        pendingRecordingStart = nil
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
            settings: llmSettings,
            appleAvailability: appleMagicFormatAvailability,
            localGemmaAvailability: localGemmaMagicFormatAvailability
        )
    }

    private func startRecording(trigger: RecordingSource, destination: DictationDestination) async {
        guard phase == .ready else {
            return
        }

        let sessionID = UUID()
        let recordStart = DispatchTime.now()
        // Capture the target app before any Suniye UI can steal focus.
        if destination.needsAccessibility {
            textInsertionService.warmTargetAppAccessibility()
        }
        var session = DictationSession(
            id: sessionID,
            source: trigger,
            startedAt: Date(),
            destination: destination,
            frontmostAppBundleID: frontmostAppBundleIDProvider()
        )
        session.timing.recordStart = recordStart
        activeDictationSession = session
        phase = .recording
        overlayErrorResetTask?.cancel()
        overlayErrorResetTask = nil
        if destination == .onboardingPractice {
            onboardingPracticeText = ""
            onboardingPracticeResult = nil
        }
        setFloatingIndicatorState(.listening(levels: Self.defaultIndicatorLevels(level: 0), source: trigger))

        do {
            let capture = try await audioCaptureService.startCapture(
                sessionID: sessionID,
                preferredInputDeviceID: microphone.selectedInputDeviceID,
                echoCancellationEnabled: dictationEchoCancellationEnabled
            )
            guard activeAudioCaptureSessionID == sessionID else {
                await audioCaptureService.cancelCapture(sessionID: sessionID, reason: nil)
                return
            }
            microphone.adoptSessionRoute(capture.route)
            emitAudioBackendUsed(capture.route)
            activeDictationSession?.timing.captureStarted = .now()
            startLivePreview(sessionID: sessionID)
            AppLogger.shared.log(.info, "recording started session=\(sessionID.uuidString) \(capture.route.privacySafeLogValue)")
        } catch {
            guard activeAudioCaptureSessionID == sessionID else {
                return
            }
            AppLogger.shared.log(.error, "audio start failed: \(error.localizedDescription)")
            endSession(sessionID, .failed(
                lastError: "Audio start failed: \(error.localizedDescription)",
                notice: error.localizedDescription
            ))
        }
    }

    private func stopRecordingAndTranscribe(trigger: RecordingSource) async {
        if phase != .recording, pendingRecordingStart == trigger {
            pendingRecordingStart = nil
            return
        }
        guard phase == .recording else {
            return
        }
        guard let context = activeDictationSession, context.source == trigger else {
            return
        }
        let sessionID = context.id

        stopLivePreview()
        phase = .transcribing
        setFloatingIndicatorState(Self.transcribingIndicatorState)
        let duration = Date().timeIntervalSince(context.startedAt)
        activeDictationSession?.timing.stopped = .now()

        let captured = await audioCaptureService.stopCapture(sessionID: sessionID)
        meetings.dictationCaptureEnded()
        guard let context = activeDictationSession, context.id == sessionID else {
            return
        }
        let samples = captured.samples
        let sampleRate = captured.sampleRate
        let destination = context.destination
        AppLogger.shared.log(.info, "dictation stop samples=\(samples.count) sr=\(sampleRate) duration=\(String(format: "%.2f", duration))")

        guard captured.outcome == .complete else {
            handleAudioCaptureFailure(captured.outcome, sessionID: sessionID, destination: destination)
            return
        }

        do {
            activeDictationSession?.timing.asrStart = .now()
            let text: String
            var emptyReason = DictationEmptyReason.emptyTranscript
            do {
                text = try await transcriptionService.transcribe(samples: samples, sampleRate: sampleRate) { [weak self] progress in
                    Task { @MainActor in
                        self?.showTranscriptionProgress(progress, sessionID: sessionID)
                    }
                }
            } catch is NoSpeechDetected {
                text = ""
                emptyReason = .noSpeech
            }
            activeDictationSession?.timing.asrEnd = .now()
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
                    destination: destination,
                    emptyReason: emptyReason
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
                reportFailedPractice(message: error.localizedDescription, outcome: .error)
            }
            AppLogger.shared.log(.error, "transcription failed: \(error.localizedDescription)")
            analytics.track(.error(type: .transcription, code: .unknown))
            endSession(sessionID, .failed(
                lastError: "Transcription failed: \(error.localizedDescription)",
                notice: "Transcription failed"
            ))
        }
    }

    /// What happened to the text of a finished dictation.
    private enum DictationDelivery {
        case empty(DictationEmptyReason)
        case inserted(submitFailed: Bool)
        /// The text stays in the history, so Paste Last Transcript recovers it.
        case insertionFailed
        case copiedWithoutPaste
    }

    private func completeDictation(
        rawText: String,
        sessionID: UUID,
        duration: TimeInterval,
        sampleCount: Int,
        sampleRate: Int,
        frontmostAppBundleID: String?,
        source: RecordingSource,
        destination: DictationDestination,
        emptyReason: DictationEmptyReason
    ) async throws {
        var finalText = rawText
        var llmOutcome: MagicFormatPolishOutcome?
        if !rawText.isEmpty {
            activeDictationSession?.timing.llmStart = .now()
            let outcome = await polishOutcome(rawText, frontmostAppBundleID: frontmostAppBundleID)
            activeDictationSession?.timing.llmEnd = .now()
            llmOutcome = outcome
            finalText = outcome.text
        }

        // Attribution is applied after insertion succeeds: the record is
        // stored before insertion is attempted so a failure is still
        // recoverable, and a clipboard-only or failed session never reached the
        // app the ranking would otherwise credit.
        let result = RecentResult(
            id: UUID(),
            text: finalText,
            createdAt: Date(),
            durationSeconds: duration,
            wasLLMPolished: llmOutcome?.ran ?? false,
            appBundleID: nil,
            rawText: finalText == rawText ? nil : rawText
        )
        let delivery: DictationDelivery
        if finalText.isEmpty {
            delivery = .empty(emptyReason)
        } else if destination == .systemInsertion {
            delivery = try await insertDictation(result, frontmostAppBundleID: frontmostAppBundleID)
        } else {
            try textInsertionService.copyTextToClipboard(finalText)
            activeDictationSession?.timing.inserted = .now()
            library.insert(result)
            AppLogger.shared.log(.info, "transcription copied to clipboard words=\(finalText.dictationWordCount)")
            delivery = .copiedWithoutPaste
        }

        switch delivery {
        case let .empty(reason):
            AppLogger.shared.log(.warning, "transcription returned empty text samples=\(sampleCount) sr=\(sampleRate)")
            playSoundFeedback(.error)
            analytics.track(.dictationEmpty(reason: reason))
        case .inserted, .copiedWithoutPaste:
            // Audio length, not hold time: the seconds the user actually spoke
            // is the honest denominator for pace and time saved.
            let audioSeconds = sampleRate > 0 ? Double(sampleCount) / Double(sampleRate) : duration
            let wordCount = finalText.dictationWordCount
            library.recordDictation(words: wordCount, seconds: audioSeconds, at: Date())
            emitDictationCompleted(
                finalText: finalText,
                wordCount: wordCount,
                duration: duration,
                llmOutcome: llmOutcome,
                source: source,
                lockedByDoubleTap: activeDictationSession?.lockedByDoubleTap ?? false,
                frontmostAppBundleID: frontmostAppBundleID,
                destination: destination.analyticsDestination
            )
        case .insertionFailed:
            break
        }

        // A clipboard-only session did its job, but the user held the hotkey to
        // paste; a success chime and an idle pill would hide that nothing landed.
        if case .inserted = delivery {
            endSession(sessionID, .completed(playSound: true))
        } else {
            endSession(sessionID, .completed(playSound: false))
        }
        switch delivery {
        case .insertionFailed:
            showInsertionRecoveryWarning()
        case .inserted(submitFailed: true):
            isShowingInsertionRecoveryWarning = false
            showSubmitKeyFailureNotice()
        case .copiedWithoutPaste:
            isShowingInsertionRecoveryWarning = false
            showClipboardOnlyNotice()
        case .inserted(submitFailed: false), .empty:
            isShowingInsertionRecoveryWarning = false
        }
    }

    /// Inserts into the focused field of the app the user is in. Throws only
    /// when Accessibility is missing.
    private func insertDictation(_ result: RecentResult, frontmostAppBundleID: String?) async throws -> DictationDelivery {
        // A completed transcript must be recoverable even if insertion fails
        // because focus moved before transcription finished.
        library.insert(result)
        try await requireAccessibilityForInsertion()
        editLearningService.finalizeActiveSession()
        let insertionText = DictationInsertionTextFormatter.textForInsertion(
            result.text,
            insertionContext: textInsertionService.captureInsertionContext()
        )
        let insertion: InsertionOutcome
        do {
            insertion = try await textInsertionService.insertText(insertionText)
        } catch {
            AppLogger.shared.log(
                .warning,
                "text insertion failed app=\(frontmostAppBundleIDProvider() ?? "unknown") error=\(error.localizedDescription)"
            )
            playSoundFeedback(.error)
            return .insertionFailed
        }
        let insertionWasVerified = insertion == .intoFocusedElement
        if !insertionWasVerified {
            AppLogger.shared.log(.info, "text inserted without a visible focus target app=\(frontmostAppBundleIDProvider() ?? "unknown")")
        }
        // Read after the insertion returns: the service retries for around a
        // second while a focused element hydrates, so anything captured earlier
        // can name the app the user has since left.
        library.attribute(result.id, to: frontmostAppBundleIDProvider() ?? frontmostAppBundleID)
        activeDictationSession?.timing.inserted = .now()
        beginEditLearningTracking(insertedText: insertionText)
        AppLogger.shared.log(.info, "transcription complete words=\(result.text.dictationWordCount)")
        if insertionWasVerified {
            advanceOnboardingAfterFirstInsertionIfNeeded(appBundleID: frontmostAppBundleIDProvider() ?? frontmostAppBundleID)
        }

        // An unverified paste went out without any idea of what holds focus, so
        // Return could land anywhere; it is withheld rather than guessed.
        guard autoSubmitEnabled, insertionWasVerified else {
            return .inserted(submitFailed: false)
        }
        try? await Task.sleep(nanoseconds: 120_000_000)
        do {
            try textInsertionService.submitActiveInput()
            AppLogger.shared.log(.info, "submit key posted")
            return .inserted(submitFailed: false)
        } catch {
            // The text is in and in history; only Return did not land, and the
            // notice says exactly that.
            AppLogger.shared.log(.error, "submit key failed error=\(error.localizedDescription)")
            analytics.track(.error(type: .insertion, code: .unknown))
            return .inserted(submitFailed: true)
        }
    }

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
            rung: route.backend == .standardEngine ? 1 : 0,
            inputStandIn: route.standIn.map(AnalyticsMapping.inputStandIn)
        )
    }

    private func emitDictationCompleted(
        finalText: String,
        wordCount: Int,
        duration: TimeInterval,
        llmOutcome: MagicFormatPolishOutcome?,
        source: RecordingSource,
        lockedByDoubleTap: Bool,
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
            source: AnalyticsMapping.source(source, lockedByDoubleTap: lockedByDoubleTap),
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
            latency: (activeDictationSession?.timing ?? DictationTiming()).latency(),
            audio: microphone.audioRouteSnapshot.map { route in
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
            activeDictationSession?.timing.llmStart = .now()
            let outcome = await polishOutcome(rawText)
            activeDictationSession?.timing.llmEnd = .now()
            llmOutcome = outcome
            finalText = outcome.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var didCompleteDictation = false
        if finalText.isEmpty {
            reportFailedPractice(
                message: rawText.isEmpty
                    ? "No speech detected. Try a short phrase."
                    : "Practice mode captured audio, but there was no text to preview.",
                outcome: rawText.isEmpty ? .emptyAudio : .error
            )
            AppLogger.shared.log(.warning, "onboarding practice produced empty text")
            playSoundFeedback(.error)
        } else {
            onboardingPracticeText = finalText
            onboardingRun.practiceDidSucceed(transcript: finalText)
            onboardingPracticeResult = OnboardingPracticeResult(
                message: "That's it — this works in any app.",
                severity: .success
            )
            let wordCount = finalText.dictationWordCount
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
                lockedByDoubleTap: activeDictationSession?.lockedByDoubleTap ?? false,
                frontmostAppBundleID: nil,
                destination: .onboardingPractice
            )
            AppLogger.shared.log(.info, "onboarding practice transcription complete words=\(wordCount)")
            didCompleteDictation = true
        }
        endSession(sessionID, .completed(playSound: didCompleteDictation))
    }

    private func recordOnboardingPracticeAttempt(outcome: PracticeOutcome) {
        analytics.track(.onboardingPracticeResult(outcome: outcome, attempt: onboardingRun.countPracticeAttempt()))
    }

    private func reportFailedPractice(message: String, outcome: PracticeOutcome) {
        onboardingPracticeText = ""
        onboardingPracticeResult = OnboardingPracticeResult(message: message, severity: .error)
        recordOnboardingPracticeAttempt(outcome: outcome)
    }

    /// No usable audio counts as an empty attempt; anything else as an error.
    private static func practiceOutcome(for capture: AudioCaptureOutcome) -> PracticeOutcome {
        let audioOutcome = AnalyticsMapping.audioOutcome(capture)
        return audioOutcome == .silent || audioOutcome == .tooShort ? .emptyAudio : .error
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
            endSession(sessionID, .failed(lastError: nil, notice: "No instruction heard"))
            return
        }

        setFloatingIndicatorState(.processing(message: "Rewriting..."))

        do {
            let rewritten = try await magicFormatCoordinator.rewrite(
                instructions: EditModePromptBuilder.systemPrompt(selectedText: selectedText),
                userText: EditModePromptBuilder.userText(instruction: instruction, selectedText: selectedText),
                request: makeMagicFormatRequest()
            )

            try await requireAccessibilityForInsertion()
            try await textInsertionService.insertText(rewritten)
            // Read after the insertion returns: the rewrite is asynchronous and
            // the service retries while a focused element hydrates, so the
            // session's app — or anything read before the call — can be stale.
            let destinationApp = frontmostAppBundleIDProvider()
                ?? activeDictationSession?.frontmostAppBundleID
            library.insert(
                RecentResult(
                    id: UUID(),
                    text: rewritten,
                    createdAt: Date(),
                    durationSeconds: duration,
                    wasLLMPolished: true,
                    appBundleID: destinationApp
                )
            )
            AppLogger.shared.log(.info, "edit mode complete words=\(rewritten.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count)")
            endSession(sessionID, .completed(playSound: true))
        } catch {
            AppLogger.shared.log(.error, "edit mode failed: \(error.localizedDescription)")
            endSession(sessionID, .failed(
                lastError: "Edit Mode failed: \(error.localizedDescription)",
                notice: "Rewrite failed"
            ))
        }
    }

    private func endSession(_ sessionID: UUID, _ end: SessionEnd) {
        if case .completed(playSound: true) = end {
            playSoundFeedback(.transcriptionSucceeded)
        }
        clearActiveDictationSession(sessionID: sessionID)
        switch end {
        case .completed:
            lastError = nil
        case let .failed(lastError?, _):
            self.lastError = lastError
        case .failed, .discarded:
            break
        }
        phase = .ready
        switch end {
        case .completed:
            setFloatingIndicatorState(.idle)
        case let .failed(_, notice):
            playSoundFeedback(.error)
            showTransientIndicatorError(notice)
        case let .discarded(notice?):
            showTransientIndicatorError(notice, duration: 1.2)
        case .discarded(nil):
            setFloatingIndicatorState(.idle)
        }
    }

    private func requireAccessibilityForInsertion() async throws {
        if !hasAccessibilityPermission {
            // Same de-stacking rule as the recording path: never pop the modal
            // system prompt on top of an active Permiso overlay session.
            await refreshPermissions(promptAccessibility: !accessibilityOnboarding.isPresenting)
        }
        guard hasAccessibilityPermission else {
            throw AppStateError.accessibilityNotGranted
        }
    }

    private func handleAudioCaptureInterruption(
        sessionID: UUID,
        reason: AudioCaptureInterruption
    ) async {
        guard let context = activeDictationSession, context.id == sessionID else {
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
        handleAudioCaptureFailure(.interrupted(reason), sessionID: sessionID, destination: context.destination)
    }

    private func handleAudioCaptureFailure(
        _ outcome: AudioCaptureOutcome,
        sessionID: UUID,
        destination: DictationDestination
    ) {
        let message = outcome.userMessage ?? "Audio capture was interrupted. Try again."
        if destination == .onboardingPractice {
            reportFailedPractice(message: message, outcome: Self.practiceOutcome(for: outcome))
        }
        AppLogger.shared.log(.warning, "audio capture rejected outcome=\(String(describing: outcome))")
        analytics.track(.audioCaptureFailed(outcome: AnalyticsMapping.audioOutcome(outcome)))
        endSession(sessionID, .failed(lastError: "Audio capture failed: \(message)", notice: message))
    }

    /// Called on termination: see `DictationStatsStore.flush()`.
    func flushDictationStats() {
        library.flush()
    }

    private func loadGeneralSettings() {
        let stored = generalSettingsStore.load()
        let (settings, needsSave) = stored.normalized(legacyUserShowsUsage: legacyUserShowsUsage(settings: stored))
        generalSettings = settings
        applyUpdateChannelToController()
        if needsSave {
            generalSettingsStore.save(settings)
        }
    }

    /// The legacy auto-complete heuristic for installs that predate the
    /// onboarding flags: only real usage signals count.
    private func legacyUserShowsUsage(settings: GeneralSettings) -> Bool {
        modelManager.isInstalled(settings.selectedASRModelID)
            || !recentResults.isEmpty
            || settings.preferredInputDeviceID != nil
            || settings.hotkeyConfiguration != .globe
    }

    /// A call that changes nothing does not save and does not notify observers.
    private func updateGeneralSettings(_ change: (inout GeneralSettings) -> Void) {
        var updated = generalSettings
        change(&updated)
        guard updated != generalSettings else {
            return
        }
        let previous = generalSettings
        generalSettings = updated
        generalSettingsStore.save(updated)
        generalSettingsDidChange(from: previous)
    }

    private func generalSettingsDidChange(from old: GeneralSettings) {
        let new = generalSettings
        if new.autoSubmitEnabled != old.autoSubmitEnabled {
            analytics.track(.featureToggled(feature: .autoSubmit, enabled: new.autoSubmitEnabled))
        }
        if new.echoCancellationEnabled != old.echoCancellationEnabled {
            analytics.track(.featureToggled(feature: .echoCancellation, enabled: new.echoCancellationEnabled))
        }
        if new.soundFeedbackEnabled != old.soundFeedbackEnabled {
            analytics.track(.featureToggled(feature: .soundFeedback, enabled: new.soundFeedbackEnabled))
        }
        if new.shareAnalyticsEnabled != old.shareAnalyticsEnabled {
            analytics.setEnabled(new.shareAnalyticsEnabled)
        }
        if old.liveTranscriptionPreviewEnabled, !new.liveTranscriptionPreviewEnabled {
            // Re-enabling applies from the next recording.
            stopLivePreview()
        }
        if new.hideFloatingIndicatorWhenIdle != old.hideFloatingIndicatorWhenIdle
            || new.floatingIndicatorPlacement != old.floatingIndicatorPlacement {
            syncFloatingIndicatorPreferences()
        }
        microphone.settingsDidChange(from: old, to: new)
        if new.hotkeys != old.hotkeys {
            if runtimeServicesEnabled {
                wireHotkey()
            }
            if new.pasteLastTranscriptHotkeyConfiguration != old.pasteLastTranscriptHotkeyConfiguration,
               isShowingInsertionRecoveryWarning {
                showInsertionRecoveryWarning()
            }
        }
        if new.updateChannel != old.updateChannel {
            applyUpdateChannelToController()
        }
    }

    private func changeHotkeys(_ result: Result<HotkeyBindings, HotkeyBindings.Rejection>) {
        let current = generalSettings.hotkeys
        switch result {
        case let .success(bindings):
            guard bindings != current else {
                return
            }
            hotkeyValidationMessage = nil
            if bindings.dictation != current.dictation, current.editMode == bindings.dictation {
                AppLogger.shared.log(.warning, "edit mode hotkey cleared: matched new dictation hotkey")
                showTransientIndicatorError("Edit Mode shortcut cleared: it matched dictation")
            }
            updateGeneralSettings { $0.hotkeys = bindings }
        case .failure(.dictationMatchesPasteLastTranscript), .failure(.pasteLastTranscriptMatchesDictation):
            hotkeyValidationMessage = "Hold to Dictate and Paste Last Transcript must use different shortcuts."
        case .failure(.pasteLastTranscriptNeedsModifier):
            hotkeyValidationMessage = "Paste Last Transcript requires at least one modifier key."
        case .failure(.pasteLastTranscriptMatchesEditMode):
            hotkeyValidationMessage = "Paste Last Transcript and Edit Mode must use different shortcuts."
        case .failure(.editModeMatchesDictation):
            AppLogger.shared.log(.warning, "edit mode hotkey rejected: matches dictation hotkey")
            showTransientIndicatorError("Edit Mode shortcut must differ from dictation")
        case .failure(.editModeMatchesPasteLastTranscript):
            hotkeyValidationMessage = "Paste Last Transcript and Edit Mode must use different shortcuts."
            AppLogger.shared.log(.warning, "edit mode hotkey rejected: matches paste last transcript hotkey")
            showTransientIndicatorError("Edit Mode shortcut must differ from Paste Last Transcript")
        }
    }

    private func loadLLMSettings() {
        let stored = llmSettingsStore.load()
        let migration = stored.normalizedForCurrentPromptSchema()
        let settings = magicFormatPromptFileStore.syncPrompts(settings: migration.settings)
        llmSettings = settings
        if migration.shouldPersist || settings != stored {
            llmSettingsStore.save(settings)
        }
    }

    /// A call that changes nothing does not save and does not notify observers.
    private func updateLLMSettings(_ change: (inout LLMSettings) -> Void) {
        var updated = llmSettings
        change(&updated)
        guard updated != llmSettings else {
            return
        }
        let previous = llmSettings
        llmSettings = updated
        llmSettingsStore.save(updated)
        llmSettingsDidChange(from: previous)
    }

    private func llmSettingsDidChange(from old: LLMSettings) {
        let new = llmSettings
        clearMagicFormatSetupTestResult()
        if new.isEnabled != old.isEnabled {
            analytics.track(.featureToggled(feature: .magicFormat, enabled: new.isEnabled))
        }
        for engine in MagicFormatEngine.allCases where new[keyPath: engine.promptKeyPath] != old[keyPath: engine.promptKeyPath] {
            magicFormatPromptFileStore.saveProviderPrompt(engine, content: new[keyPath: engine.promptKeyPath])
        }
    }

    private func localGemmaCatalogEntry(for modelID: LocalLLMModelID) -> LocalLLMModelCatalogEntry {
        localLLMModelManager.catalog.first { $0.id == modelID } ?? LocalLLMModelCatalog.entry(for: modelID)
    }

    private func issueReportContext() -> IssueReportContext {
        let version = currentAppVersionProvider()
        return IssueReportContext(
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
                selectedModelName: currentASRModelEntry.displayName,
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
        case .malformedResponse, .emptyOutput, .outputTruncated, .invalidConfiguration:
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
            case .provider, .malformedResponse, .emptyOutput, .outputTruncated:
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

    /// The text is in; only the Enter after it did not post. Says so, rather
    /// than the recovery warning's "couldn't insert" — which would send the
    /// user to re-paste text that is already there.
    private func showSubmitKeyFailureNotice() {
        let message = "Text inserted, but Enter couldn't be sent. Press it yourself."
        lastError = message
        showTransientIndicatorError(message, restoreState: blockedStartRestoreIndicatorState(), duration: 3.0)
    }

    var clipboardOnlyNoticeMessage: String {
        "Not pasted: Accessibility is off. Press ⌘V, then open \(AppIdentity.current.displayName) to fix."
    }

    private func showClipboardOnlyNotice() {
        playSoundFeedback(.error)
        showTransientIndicatorError(clipboardOnlyNoticeMessage, duration: 3.5)
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

    private func clearActiveDictationSession(sessionID: UUID) {
        guard activeAudioCaptureSessionID == sessionID else {
            return
        }
        activeDictationSession = nil
        stopLivePreview()
        microphone.refreshAudioRouteSnapshot()
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

    /// Long dictations on a chunked engine (Cohere) take seconds per chunk, so
    /// the pill counts chunks instead of sitting on a bare spinner.
    private func showTranscriptionProgress(_ progress: TranscriptionProgress, sessionID: UUID) {
        guard progress.totalChunks > 1,
              phase == .transcribing,
              activeDictationSession?.id == sessionID else {
            return
        }
        let message = "Transcribing \(progress.chunk) of \(progress.totalChunks)..."
        setFloatingIndicatorState(.processing(message: message))
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
    case insufficientDiskSpace(String)
    case accessibilityNotGranted

    var errorDescription: String? {
        switch self {
        case .accessibilityNotGranted:
            return "Accessibility permission not granted"
        case .modelValidationFailed:
            return "Model files are missing after extraction."
        case let .insufficientDiskSpace(message):
            return message
        }
    }
}

extension AppState {
    /// Makes `model` the meeting transcript model; nil is the dictation
    /// model. A model that is not on the Mac downloads first, without
    /// becoming the dictation model, and becomes the transcript model when
    /// the download succeeds.
    func useForMeetingTranscripts(_ model: ASRModelID?) {
        meetingTranscriptModelChoice += 1
        let choice = meetingTranscriptModelChoice
        guard let model else {
            meetings.updateSettings { $0.transcriptModel = nil }
            return
        }
        Task {
            if await !modelManager.isSystemManagedAssetInstalled(model) {
                guard choice == meetingTranscriptModelChoice, asrModelCanPerformPrimaryAction(for: model) else { return }
                meetingTranscriptModelDownload = model
                downloadASRModel(model, autoSelect: false)
                await asrDownloadTask?.value
                meetingTranscriptModelDownload = nil
                guard await modelManager.isSystemManagedAssetInstalled(model) else { return }
            }
            guard choice == meetingTranscriptModelChoice else { return }
            meetings.updateSettings { $0.transcriptModel = model }
        }
    }
}

extension AppState: MeetingHost {
    /// Opens the main window at a meeting's page, or at the list for nil.
    func openMeeting(_ id: UUID?) {
        meetings.openMeetingID = id
        openMainWindow(at: .meetings)
    }

    var meetingInputDeviceID: String? {
        microphone.selectedInputDeviceID
    }

    func requestMeetingMicrophoneAccess() async -> Bool {
        if !hasMicPermission {
            await refreshPermissions(requestMicrophone: true, askSurface: .meetingStart)
        }
        return hasMicPermission
    }

    func meetingSummaryModelIsIdle() {
        prewarmLocalLLMIfEligible()
    }

    /// A recording meeting stops and saves before the app quits, and its
    /// transcript finishes at the next launch. A quit from the user asks
    /// first; a logout, restart or shutdown does not, so it never blocks one.
    func terminateReplyForMeeting() -> NSApplication.TerminateReply {
        guard meetings.live != nil else { return .terminateNow }
        if !Self.systemIsQuittingApps() {
            NSApp.activate(ignoringOtherApps: true)
            guard MeetingQuitAlert.make().runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        }
        Task {
            await meetings.stopForQuit()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private static func systemIsQuittingApps() -> Bool {
        guard let reason = NSAppleEventManager.shared().currentAppleEvent?
            .attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason))?
            .typeCodeValue
        else { return false }
        let systemReasons = [kAELogOut, kAEReallyLogOut, kAEShowRestartDialog, kAERestart, kAEShowShutdownDialog, kAEShutDown]
        return systemReasons.map { OSType($0) }.contains(reason)
    }

    func startMeetingFromMenu() {
        Task {
            do {
                try await meetings.startMeeting(source: .manual)
            } catch {
                meetingCouldNotStart(error)
            }
        }
    }

    func meetingCouldNotStart(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Couldn’t start the recording"
        alert.informativeText = error.localizedDescription
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    func pauseOrResumeMeeting() {
        guard let live = meetings.live else { return }
        handleMeetingPillAction(live.isPaused ? .resume : .pause)
    }

    func handleMeetingPillAction(_ action: MeetingPillAction) {
        guard let live = meetings.live else { return }
        switch action {
        case .open:
            openMeeting(live.id)
        case .pause:
            Task { await meetings.pause() }
        case .resume:
            Task {
                do {
                    try await meetings.resume()
                } catch {
                    learningToastPresenter.show(message: "Couldn’t resume the recording", detail: nil, actionTitle: nil, action: nil)
                }
            }
        case .stop:
            Task { await meetings.stop() }
        }
    }

    /// A meeting notice becomes a toast. A notice that the meeting's page
    /// shows itself is skipped while that page is on screen in the active app.
    func showMeetingNotice(_ notice: MeetingNotice) {
        let pageOnScreen = NSApp.isActive ? meetings.pageOnScreen : nil
        let live = meetings.live.flatMap { $0.id == pageOnScreen ? nil : $0 }
        let time = live.map { MeetingTranscript.clock($0.elapsed(at: Date())) }
        switch notice {
        case .callAudioStopped:
            guard live != nil else { return }
            learningToastPresenter.show(message: "Call audio stopped", detail: time, actionTitle: "Restart Call Audio") { [weak self] in
                self?.meetings.restartCallAudio()
            }
        case .callAudioNeverHeard:
            guard let live else { return }
            learningToastPresenter.show(message: "No sound from the call", detail: time, actionTitle: "Open Meeting") { [weak self] in
                self?.openMeeting(live.id)
            }
        case let .microphoneChanged(name):
            guard live != nil else { return }
            learningToastPresenter.show(message: "Recording with \(name)", detail: time, actionTitle: nil, action: nil)
        case let .trackFailed(track):
            guard let live else { return }
            learningToastPresenter.show(
                message: track == .you ? "The microphone stopped" : "Call audio stopped",
                detail: time,
                actionTitle: "Open Meeting"
            ) { [weak self] in
                self?.openMeeting(live.id)
            }
        case let .stoppedAtTimeLimit(id, limit):
            showMeetingStopped(id, message: "Recording stopped after \(MeetingDurationText.spelledOut(limit))")
        case let .stoppedWithoutSpeech(id, limit):
            showMeetingStopped(id, message: "Recording stopped after \(MeetingDurationText.spelledOut(limit)) without speech")
        case let .stoppedByDiskFull(id):
            // The meeting page shows its own banner for it.
            guard id != pageOnScreen else { return }
            showMeetingStopped(id, message: "Recording stopped because the disk is full")
        case let .stoppedByWriteError(id):
            guard id != pageOnScreen else { return }
            showMeetingStopped(id, message: "Recording stopped because the audio could not be saved")
        case let .summaryReady(id):
            guard id != pageOnScreen else { return }
            learningToastPresenter.show(message: "Summary ready", detail: nil, actionTitle: "Open") { [weak self] in
                self?.openMeeting(id)
            }
        }
    }

    private func showMeetingStopped(_ id: UUID, message: String) {
        learningToastPresenter.show(message: message, detail: nil, actionTitle: "Open Meeting") { [weak self] in
            self?.openMeeting(id)
        }
    }

    /// Capture stops while the Mac sleeps, so sleep, and a closed lid that
    /// puts the Mac to sleep, stop the recording and save it.
    fileprivate func stopMeetingAtSleep() {
        _ = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.meetings.stop(.sleep) }
            }
        }
    }

    fileprivate static func makeMeetingCoordinator(
        transcriptionService: TranscriptionServiceProtocol,
        modelManager: ModelManagerProtocol,
        appleSummaryAvailability: @escaping () -> AppleFoundationModelsAvailability,
        localSummaryAvailability: @escaping () -> LocalGemmaAvailability,
        localGemmaClient: LocalGemmaClient,
        analytics: Analytics
    ) -> MeetingCoordinator {
        MeetingCoordinator(
            store: MeetingStore(),
            templates: MeetingTemplateStore(),
            settingsStore: MeetingSettingsStore(),
            engine: transcriptionService,
            makeTranscriptEngine: { model in
                guard await modelManager.isSystemManagedAssetInstalled(model) else {
                    throw MeetingTranscriptModelError.notDownloaded(ASRModelCatalog.entry(for: model).displayName)
                }
                let engine = RoutingTranscriptionService()
                try await engine.loadModel(config: modelManager.makeRecognizerConfig(for: model))
                return engine
            },
            environment: .live(),
            summaryAvailability: {
                MeetingSummaryAvailability(apple: appleSummaryAvailability(), localModel: localSummaryAvailability())
            },
            makeSummaryModel: { engine in
                switch engine {
                case .localModel:
                    return LocalGemmaMeetingSummaryModel(client: localGemmaClient)
                case .appleIntelligence:
                    #if canImport(FoundationModels)
                    if #available(macOS 26.0, *) {
                        return AppleMeetingSummaryModel()
                    }
                    #endif
                    return nil
                }
            },
            analytics: analytics
        )
    }
}
