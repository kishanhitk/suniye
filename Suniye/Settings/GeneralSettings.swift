import Foundation

struct GeneralSettings: Codable, Equatable {
    var preferredInputDeviceID: String?
    var preferredInputDeviceName: String?
    var autoSubmitEnabled: Bool = false
    var hotkeyConfiguration: HotkeyConfiguration = .globe
    var pasteLastTranscriptHotkeyConfiguration: HotkeyConfiguration = .pasteLastTranscriptDefault
    /// Edit Mode shortcut; nil means Edit Mode is disabled.
    var editModeHotkeyConfiguration: HotkeyConfiguration? = nil
    var echoCancellationEnabled: Bool = false
    var soundFeedbackEnabled: Bool = false
    var hideFloatingIndicatorWhenIdle: Bool = false
    var liveTranscriptionPreviewEnabled: Bool = false
    var floatingIndicatorPlacement: FloatingIndicatorPlacement? = nil
    /// Legacy onboarding flags. Still written (derived from `onboardingProgress`)
    /// so a downgraded build keeps working; `onboardingProgress` wins on load.
    var hasSeenOnboardingWelcome: Bool? = nil
    var hasCompletedCoreOnboarding: Bool? = nil
    /// Single persisted onboarding position; nil only for settings written by
    /// older builds (migrated on load from the two legacy Bools above).
    var onboardingProgress: OnboardingProgress? = nil
    /// Set the first time an `app_launch` event ships, so `first_launch` counts
    /// each install exactly once (quitting on the welcome screen used to
    /// re-count as a new install on every relaunch).
    var firstLaunchRecorded: Bool = false
    /// Last observed Accessibility trust state. When this is true but
    /// AXIsProcessTrusted() is false, the grant went stale (app update / TCC
    /// reset) and the drag overlay would mislead — we show toggle-off/on copy.
    var lastKnownAccessibilityGranted: Bool = false
    /// The post-onboarding Magic Format nudge card was dismissed; never re-nag.
    var magicFormatNudgeDismissed: Bool = false
    /// The user canceled the local model download. Bootstrap must not restart it
    /// until the user chooses Download again.
    var localGemmaDownloadCancelled: Bool = false
    var selectedASRModelID: ASRModelID = .parakeetV3
    var updateChannel: UpdateChannel = .stable
    /// Gates the Permiso drag-to-grant overlay for Accessibility onboarding.
    /// Kill switch: when false, the Accessibility buttons fall back to the plain
    /// System Settings deep-link.
    var accessibilityDragHelperEnabled: Bool = true
    /// Opt-out toggle for anonymous usage analytics. Default on; disclosed in
    /// onboarding and controllable in Settings. When false, nothing is emitted.
    var shareAnalyticsEnabled: Bool = true
}

extension GeneralSettings {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preferredInputDeviceID = try container.decodeIfPresent(String.self, forKey: .preferredInputDeviceID)
        preferredInputDeviceName = try container.decodeIfPresent(String.self, forKey: .preferredInputDeviceName)
        autoSubmitEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoSubmitEnabled) ?? false
        hotkeyConfiguration = try container.decodeIfPresent(HotkeyConfiguration.self, forKey: .hotkeyConfiguration) ?? .globe
        pasteLastTranscriptHotkeyConfiguration = try container.decodeIfPresent(
            HotkeyConfiguration.self,
            forKey: .pasteLastTranscriptHotkeyConfiguration
        ) ?? .pasteLastTranscriptDefault
        editModeHotkeyConfiguration = try container.decodeIfPresent(HotkeyConfiguration.self, forKey: .editModeHotkeyConfiguration)
        echoCancellationEnabled = try container.decodeIfPresent(Bool.self, forKey: .echoCancellationEnabled) ?? false
        soundFeedbackEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundFeedbackEnabled) ?? false
        hideFloatingIndicatorWhenIdle = try container.decodeIfPresent(Bool.self, forKey: .hideFloatingIndicatorWhenIdle) ?? false
        liveTranscriptionPreviewEnabled = try container.decodeIfPresent(Bool.self, forKey: .liveTranscriptionPreviewEnabled) ?? false
        floatingIndicatorPlacement = try container.decodeIfPresent(FloatingIndicatorPlacement.self, forKey: .floatingIndicatorPlacement)
        hasSeenOnboardingWelcome = try container.decodeIfPresent(Bool.self, forKey: .hasSeenOnboardingWelcome)
        hasCompletedCoreOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedCoreOnboarding)
        // Raw-string decode so an unknown future case degrades to nil (legacy
        // migration) instead of failing the whole settings blob.
        let storedOnboardingProgress = try container.decodeIfPresent(String.self, forKey: .onboardingProgress)
        onboardingProgress = storedOnboardingProgress.flatMap(OnboardingProgress.init(rawValue:))
        firstLaunchRecorded = try container.decodeIfPresent(Bool.self, forKey: .firstLaunchRecorded) ?? false
        lastKnownAccessibilityGranted = try container.decodeIfPresent(Bool.self, forKey: .lastKnownAccessibilityGranted) ?? false
        magicFormatNudgeDismissed = try container.decodeIfPresent(Bool.self, forKey: .magicFormatNudgeDismissed) ?? false
        localGemmaDownloadCancelled = try container.decodeIfPresent(Bool.self, forKey: .localGemmaDownloadCancelled) ?? false
        let storedASRModelID = try container.decodeIfPresent(String.self, forKey: .selectedASRModelID)
        selectedASRModelID = storedASRModelID.flatMap(ASRModelID.init(rawValue:)) ?? .parakeetV3
        let storedUpdateChannel = try container.decodeIfPresent(String.self, forKey: .updateChannel)
        updateChannel = storedUpdateChannel.flatMap(UpdateChannel.init(rawValue:)) ?? .stable
        accessibilityDragHelperEnabled = try container.decodeIfPresent(Bool.self, forKey: .accessibilityDragHelperEnabled) ?? true
        shareAnalyticsEnabled = try container.decodeIfPresent(Bool.self, forKey: .shareAnalyticsEnabled) ?? true
    }
}

extension GeneralSettings {
    var hotkeys: HotkeyBindings {
        get {
            HotkeyBindings(
                dictation: hotkeyConfiguration,
                pasteLastTranscript: pasteLastTranscriptHotkeyConfiguration,
                editMode: editModeHotkeyConfiguration
            )
        }
        set {
            hotkeyConfiguration = newValue.dictation
            pasteLastTranscriptHotkeyConfiguration = newValue.pasteLastTranscript
            editModeHotkeyConfiguration = newValue.editMode
        }
    }

    /// The legacy Bools are still written so that a downgraded build keeps working.
    mutating func setOnboardingProgress(_ progress: OnboardingProgress) {
        onboardingProgress = progress
        hasSeenOnboardingWelcome = progress != .notStarted
        hasCompletedCoreOnboarding = progress.isFinished
    }

    /// The settings as this build uses them: onboarding migrated from the legacy
    /// flags, and the three shortcuts made distinct. `needsSave` is true when
    /// the stored value is out of date.
    func normalized(legacyUserShowsUsage: Bool) -> (settings: GeneralSettings, needsSave: Bool) {
        var settings = self
        settings.hotkeys = hotkeys.normalized()
        let needsFirstLaunchMigration = onboardingProgress == nil
            && (hasSeenOnboardingWelcome == true || hasCompletedCoreOnboarding == true || legacyUserShowsUsage)
        settings.firstLaunchRecorded = firstLaunchRecorded || needsFirstLaunchMigration
        settings.setOnboardingProgress(onboardingProgress ?? .migrating(
            hasSeenOnboardingWelcome: hasSeenOnboardingWelcome,
            hasCompletedCoreOnboarding: hasCompletedCoreOnboarding,
            legacyUserShowsUsage: legacyUserShowsUsage
        ))
        let needsSave = onboardingProgress == nil || needsFirstLaunchMigration || settings.hotkeys != hotkeys
        return (settings, needsSave)
    }
}
