import AppKit
import Carbon
import Foundation

extension String {
    /// Word count that also works for scripts written without spaces. A
    /// whitespace split counts a whole Japanese or Chinese sentence as one word
    /// (measured: 1 vs 17 and 1 vs 9), and Suniye ships multilingual recognizers.
    /// `.byWords` segments by the locale's rules and is faster than splitting.
    var dictationWordCount: Int {
        var count = 0
        enumerateSubstrings(in: startIndex..., options: [.byWords, .localized]) { _, _, _, _ in
            count += 1
        }
        return count
    }
}

struct RecentResult: Identifiable, Equatable, Codable {
    let id: UUID
    let text: String
    let createdAt: Date
    let durationSeconds: TimeInterval
    let wasLLMPolished: Bool
    /// Where the dictation was inserted. Optional because history written before
    /// this existed has no source app — those rows decode with nil rather than
    /// failing, and simply show no app.
    var appBundleID: String?

    var wordCount: Int {
        text.dictationWordCount
    }

    init(
        id: UUID,
        text: String,
        createdAt: Date,
        durationSeconds: TimeInterval,
        wasLLMPolished: Bool,
        appBundleID: String? = nil
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.durationSeconds = durationSeconds
        self.wasLLMPolished = wasLLMPolished
        self.appBundleID = appBundleID
    }
}

enum AudioDeviceTransport: String, Equatable, Codable, Sendable {
    case builtIn
    case usb
    case bluetooth
    case bluetoothLE
    case continuity
    case aggregate
    case virtual
    case other

    var title: String {
        switch self {
        case .builtIn: return "Built-in"
        case .usb: return "USB"
        case .bluetooth: return "Bluetooth"
        case .bluetoothLE: return "Bluetooth LE"
        case .continuity: return "Continuity"
        case .aggregate: return "Aggregate"
        case .virtual: return "Virtual"
        case .other: return "Other"
        }
    }

    var isBluetooth: Bool {
        self == .bluetooth || self == .bluetoothLE
    }

    var isRecommendedPhysicalInput: Bool {
        self == .builtIn || self == .usb
    }
}

struct AudioInputDevice: Identifiable, Equatable, Codable, Sendable {
    let id: String
    let name: String
    let isDefault: Bool
    let transport: AudioDeviceTransport
    let isAvailable: Bool

    init(
        id: String,
        name: String,
        isDefault: Bool,
        transport: AudioDeviceTransport = .other,
        isAvailable: Bool = true
    ) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
        self.transport = transport
        self.isAvailable = isAvailable
    }
}

struct HotkeyConfiguration: Codable, Equatable {
    enum Kind: String, Codable {
        case globe
        case keyCombo
    }

    var kind: Kind
    var keyCode: UInt32
    var carbonModifiers: UInt32

    static let globe = HotkeyConfiguration(kind: .globe, keyCode: UInt32(kVK_Function), carbonModifiers: 0)
    static let pasteLastTranscriptDefault = HotkeyConfiguration.keyCombo(
        keyCode: UInt32(kVK_ANSI_V),
        carbonModifiers: UInt32(controlKey | cmdKey)
    )

    static func keyCombo(keyCode: UInt32, carbonModifiers: UInt32) -> HotkeyConfiguration {
        HotkeyConfiguration(kind: .keyCombo, keyCode: keyCode, carbonModifiers: carbonModifiers)
    }

    var displayString: String {
        switch kind {
        case .globe:
            return "Globe"
        case .keyCombo:
            let parts = modifierLabels + [Self.keyName(for: keyCode)]
            return parts.joined(separator: " + ")
        }
    }

    var compactDisplayString: String {
        switch kind {
        case .globe:
            return "Globe"
        case .keyCombo:
            return compactModifierLabels.joined() + Self.keyName(for: keyCode)
        }
    }

    var isModifiedKeyCombo: Bool {
        kind == .keyCombo && carbonModifiers != 0
    }

    var exampleDescription: String {
        switch kind {
        case .globe:
            return "Fn/Globe key (macOS dictation key)"
        case .keyCombo:
            return displayString
        }
    }

    var modifierLabels: [String] {
        guard kind == .keyCombo else {
            return []
        }

        var labels: [String] = []
        if carbonModifiers & UInt32(controlKey) != 0 {
            labels.append("Control")
        }
        if carbonModifiers & UInt32(optionKey) != 0 {
            labels.append("Option")
        }
        if carbonModifiers & UInt32(shiftKey) != 0 {
            labels.append("Shift")
        }
        if carbonModifiers & UInt32(cmdKey) != 0 {
            labels.append("Command")
        }
        return labels
    }

    private var compactModifierLabels: [String] {
        guard kind == .keyCombo else {
            return []
        }

        var labels: [String] = []
        if carbonModifiers & UInt32(controlKey) != 0 {
            labels.append("⌃")
        }
        if carbonModifiers & UInt32(optionKey) != 0 {
            labels.append("⌥")
        }
        if carbonModifiers & UInt32(shiftKey) != 0 {
            labels.append("⇧")
        }
        if carbonModifiers & UInt32(cmdKey) != 0 {
            labels.append("⌘")
        }
        return labels
    }

    static func from(event: NSEvent) -> HotkeyConfiguration? {
        let modifiers = carbonModifiers(from: event.modifierFlags)

        if event.type == .flagsChanged,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .function {
            return .globe
        }

        guard event.type == .keyDown else {
            return nil
        }

        switch Int(event.keyCode) {
        case kVK_Command, kVK_Shift, kVK_RightShift, kVK_Option, kVK_RightOption,
             kVK_Control, kVK_RightControl, kVK_CapsLock, kVK_Function:
            return nil
        default:
            return .keyCombo(keyCode: UInt32(event.keyCode), carbonModifiers: modifiers)
        }
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        let mask = flags.intersection(.deviceIndependentFlagsMask)
        var carbon: UInt32 = 0

        if mask.contains(.control) {
            carbon |= UInt32(controlKey)
        }
        if mask.contains(.option) {
            carbon |= UInt32(optionKey)
        }
        if mask.contains(.shift) {
            carbon |= UInt32(shiftKey)
        }
        if mask.contains(.command) {
            carbon |= UInt32(cmdKey)
        }

        return carbon
    }

    static func keyName(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_Space:
            return "Space"
        case kVK_Return:
            return "Return"
        case kVK_Escape:
            return "Escape"
        case kVK_Tab:
            return "Tab"
        case kVK_Delete:
            return "Delete"
        case kVK_ANSI_Grave:
            return "`"
        case kVK_ANSI_Comma:
            return ","
        case kVK_ANSI_Period:
            return "."
        case kVK_ANSI_Slash:
            return "/"
        case kVK_ANSI_Semicolon:
            return ";"
        case kVK_ANSI_Quote:
            return "'"
        case kVK_ANSI_LeftBracket:
            return "["
        case kVK_ANSI_RightBracket:
            return "]"
        case kVK_ANSI_Backslash:
            return "\\"
        case kVK_ANSI_Minus:
            return "-"
        case kVK_ANSI_Equal:
            return "="
        case kVK_ANSI_0:
            return "0"
        case kVK_ANSI_1:
            return "1"
        case kVK_ANSI_2:
            return "2"
        case kVK_ANSI_3:
            return "3"
        case kVK_ANSI_4:
            return "4"
        case kVK_ANSI_5:
            return "5"
        case kVK_ANSI_6:
            return "6"
        case kVK_ANSI_7:
            return "7"
        case kVK_ANSI_8:
            return "8"
        case kVK_ANSI_9:
            return "9"
        case kVK_ANSI_A:
            return "A"
        case kVK_ANSI_B:
            return "B"
        case kVK_ANSI_C:
            return "C"
        case kVK_ANSI_D:
            return "D"
        case kVK_ANSI_E:
            return "E"
        case kVK_ANSI_F:
            return "F"
        case kVK_ANSI_G:
            return "G"
        case kVK_ANSI_H:
            return "H"
        case kVK_ANSI_I:
            return "I"
        case kVK_ANSI_J:
            return "J"
        case kVK_ANSI_K:
            return "K"
        case kVK_ANSI_L:
            return "L"
        case kVK_ANSI_M:
            return "M"
        case kVK_ANSI_N:
            return "N"
        case kVK_ANSI_O:
            return "O"
        case kVK_ANSI_P:
            return "P"
        case kVK_ANSI_Q:
            return "Q"
        case kVK_ANSI_R:
            return "R"
        case kVK_ANSI_S:
            return "S"
        case kVK_ANSI_T:
            return "T"
        case kVK_ANSI_U:
            return "U"
        case kVK_ANSI_V:
            return "V"
        case kVK_ANSI_W:
            return "W"
        case kVK_ANSI_X:
            return "X"
        case kVK_ANSI_Y:
            return "Y"
        case kVK_ANSI_Z:
            return "Z"
        default:
            return "Key \(keyCode)"
        }
    }
}

enum UpdateChannel: String, Codable, CaseIterable, Identifiable {
    case stable
    case tip

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stable:
            return "Stable"
        case .tip:
            return "Tip"
        }
    }

    var detail: String {
        switch self {
        case .stable:
            return "Stable releases only."
        case .tip:
            return "Latest main-branch builds."
        }
    }

    var appcastURLString: String {
        switch self {
        case .stable:
            return "https://suniye.kishans.in/appcast.xml"
        case .tip:
            return "https://suniye.kishans.in/appcast-tip.xml"
        }
    }

    var sparkleChannelName: String? {
        switch self {
        case .stable:
            return nil
        case .tip:
            return rawValue
        }
    }

    var sparkleAllowedChannels: Set<String> {
        switch self {
        case .stable:
            return []
        case .tip:
            return [rawValue]
        }
    }
}

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
    /// Legacy onboarding flags. Read-only: decoded so installs written by the
    /// Bool-era builds migrate onto `onboardingProgress`; never written again.
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
    /// The system Accessibility prompt has been shown at least once. macOS adds
    /// the app to the Accessibility list (switched off) the moment that prompt
    /// appears, after which the "drag the app into the list" helper is wrong.
    var accessibilityPromptShown: Bool = false
    /// The user finished onboarding with "Later" on the Accessibility screen.
    /// The dashboard explains clipboard mode instead of re-asking at once.
    var accessibilityDeferred: Bool = false
    /// The post-onboarding Magic Format nudge card was dismissed; never re-nag.
    var magicFormatNudgeDismissed: Bool = false
    /// The user canceled the local model download. Bootstrap must not restart it
    /// until the user chooses Download again.
    var localGemmaDownloadCancelled: Bool = false
    var selectedASRModelID: ASRModelID = .parakeetV3
    var updateChannel: UpdateChannel = .stable
    /// Opt-out toggle for anonymous usage analytics. Default on; disclosed in
    /// onboarding and controllable in Settings. When false, nothing is emitted.
    var shareAnalyticsEnabled: Bool = true

    init(
        preferredInputDeviceID: String? = nil,
        preferredInputDeviceName: String? = nil,
        autoSubmitEnabled: Bool = false,
        hotkeyConfiguration: HotkeyConfiguration = .globe,
        pasteLastTranscriptHotkeyConfiguration: HotkeyConfiguration = .pasteLastTranscriptDefault,
        editModeHotkeyConfiguration: HotkeyConfiguration? = nil,
        echoCancellationEnabled: Bool = false,
        soundFeedbackEnabled: Bool = false,
        hideFloatingIndicatorWhenIdle: Bool = false,
        liveTranscriptionPreviewEnabled: Bool = false,
        floatingIndicatorPlacement: FloatingIndicatorPlacement? = nil,
        hasSeenOnboardingWelcome: Bool? = nil,
        hasCompletedCoreOnboarding: Bool? = nil,
        onboardingProgress: OnboardingProgress? = nil,
        firstLaunchRecorded: Bool = false,
        lastKnownAccessibilityGranted: Bool = false,
        accessibilityPromptShown: Bool = false,
        accessibilityDeferred: Bool = false,
        magicFormatNudgeDismissed: Bool = false,
        localGemmaDownloadCancelled: Bool = false,
        selectedASRModelID: ASRModelID = .parakeetV3,
        updateChannel: UpdateChannel = .stable,
        shareAnalyticsEnabled: Bool = true
    ) {
        self.preferredInputDeviceID = preferredInputDeviceID
        self.preferredInputDeviceName = preferredInputDeviceName
        self.autoSubmitEnabled = autoSubmitEnabled
        self.hotkeyConfiguration = hotkeyConfiguration
        self.pasteLastTranscriptHotkeyConfiguration = pasteLastTranscriptHotkeyConfiguration
        self.editModeHotkeyConfiguration = editModeHotkeyConfiguration
        self.echoCancellationEnabled = echoCancellationEnabled
        self.soundFeedbackEnabled = soundFeedbackEnabled
        self.hideFloatingIndicatorWhenIdle = hideFloatingIndicatorWhenIdle
        self.liveTranscriptionPreviewEnabled = liveTranscriptionPreviewEnabled
        self.floatingIndicatorPlacement = floatingIndicatorPlacement
        self.hasSeenOnboardingWelcome = hasSeenOnboardingWelcome
        self.hasCompletedCoreOnboarding = hasCompletedCoreOnboarding
        self.onboardingProgress = onboardingProgress
        self.firstLaunchRecorded = firstLaunchRecorded
        self.lastKnownAccessibilityGranted = lastKnownAccessibilityGranted
        self.accessibilityPromptShown = accessibilityPromptShown
        self.accessibilityDeferred = accessibilityDeferred
        self.magicFormatNudgeDismissed = magicFormatNudgeDismissed
        self.localGemmaDownloadCancelled = localGemmaDownloadCancelled
        self.selectedASRModelID = selectedASRModelID
        self.updateChannel = updateChannel
        self.shareAnalyticsEnabled = shareAnalyticsEnabled
    }

    enum CodingKeys: String, CodingKey {
        case preferredInputDeviceID
        case preferredInputDeviceName
        case autoSubmitEnabled
        case hotkeyConfiguration
        case pasteLastTranscriptHotkeyConfiguration
        case editModeHotkeyConfiguration
        case echoCancellationEnabled
        case soundFeedbackEnabled
        case hideFloatingIndicatorWhenIdle
        case liveTranscriptionPreviewEnabled
        case floatingIndicatorPlacement
        case hasSeenOnboardingWelcome
        case hasCompletedCoreOnboarding
        case onboardingProgress
        case firstLaunchRecorded
        case lastKnownAccessibilityGranted
        case accessibilityPromptShown
        case accessibilityDeferred
        case magicFormatNudgeDismissed
        case localGemmaDownloadCancelled
        case selectedASRModelID
        case updateChannel
        case shareAnalyticsEnabled
    }

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
        accessibilityPromptShown = try container.decodeIfPresent(Bool.self, forKey: .accessibilityPromptShown) ?? false
        accessibilityDeferred = try container.decodeIfPresent(Bool.self, forKey: .accessibilityDeferred) ?? false
        magicFormatNudgeDismissed = try container.decodeIfPresent(Bool.self, forKey: .magicFormatNudgeDismissed) ?? false
        localGemmaDownloadCancelled = try container.decodeIfPresent(Bool.self, forKey: .localGemmaDownloadCancelled) ?? false
        let storedASRModelID = try container.decodeIfPresent(String.self, forKey: .selectedASRModelID)
        selectedASRModelID = storedASRModelID.flatMap(ASRModelID.init(rawValue:)) ?? .parakeetV3
        let storedUpdateChannel = try container.decodeIfPresent(String.self, forKey: .updateChannel)
        updateChannel = storedUpdateChannel.flatMap(UpdateChannel.init(rawValue:)) ?? .stable
        shareAnalyticsEnabled = try container.decodeIfPresent(Bool.self, forKey: .shareAnalyticsEnabled) ?? true
    }
}

struct FloatingIndicatorPlacement: Codable, Equatable {
    var centerXRatio: Double
    var bottomYRatio: Double
}


/// One app's share of dictation history, for the Transcripts header. The name is
/// resolved once when the ranking is built, not per read: an uninstalled app has
/// no honest name to show and has to be dropped *before* the ranking is cut to
/// three, or an installed app ranked fourth is lost with it.
struct DictationAppUsage: Identifiable, Equatable {
    let bundleID: String
    let count: Int
    let name: String

    var id: String { bundleID }

    static func resolvedName(for bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }
}
