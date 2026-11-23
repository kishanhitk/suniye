import Carbon
import AppKit
import SwiftUI

/// The pane that Settings shows next to its sidebar.
struct SettingsPaneView: View {
    @Bindable var appState: AppState
    let pane: SettingsPane

    var body: some View {
        switch pane {
        case .permissions:
            PermissionsPane(appState: appState)
        case .microphone:
            MicrophonePane(appState: appState)
        case .shortcuts:
            ShortcutsPane(appState: appState)
        case .indicator:
            IndicatorPane(appState: appState)
        case .speechModel:
            SpeechModelPage(appState: appState)
        case .meetings:
            MeetingsSettingsPane(appState: appState)
        case .general:
            GeneralSettingsPane(appState: appState)
        }
    }
}

// MARK: - Permissions

/// Listed only while something is missing, so it never becomes a page of green
/// ticks reporting that nothing is wrong.
struct PermissionsPane: View {
    @Bindable var appState: AppState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SettingsForm(title: SettingsPane.permissions.title, subtitle: subtitle) {
            SettingsSection {
                if SettingsRowID.microphonePermission.isAvailable(in: appState) {
                    ControlSettingRow(.microphonePermission, in: appState) {
                        grantButtons(
                            // After a denial macOS never asks again: Grant would
                            // only open System Settings too.
                            canAsk: !appState.hasMicPermissionBeenDenied,
                            grant: { appState.requestMicrophonePermission() },
                            openSettings: { appState.openMicrophonePrivacySettings() }
                        )
                    }
                }

                if SettingsRowID.accessibilityPermission.isAvailable(in: appState) {
                    ControlSettingRow(.accessibilityPermission, in: appState) {
                        grantButtons(
                            // A stale grant is fixed in System Settings only.
                            canAsk: !appState.accessibilityGrantLikelyStale,
                            grant: { appState.beginAccessibilityOnboarding() },
                            openSettings: { appState.openAccessibilityPrivacySettings() }
                        )
                    }
                }
            }
        }
        // Granting one permission removes its row and pulls the other one up.
        .animation(SettingsMotion.curve(reduceMotion: reduceMotion), value: appState.hasMicPermission)
        .animation(SettingsMotion.curve(reduceMotion: reduceMotion), value: appState.hasAccessibilityPermission)
    }

    private var subtitle: String {
        let missing = [appState.hasMicPermission, appState.hasAccessibilityPermission].filter { !$0 }.count
        let what = missing == 1 ? "this is" : "these are"
        return "\(AppIdentity.current.displayName) cannot dictate until \(what) granted."
    }

    @ViewBuilder
    private func grantButtons(canAsk: Bool, grant: @escaping () -> Void, openSettings: @escaping () -> Void) -> some View {
        if canAsk {
            HStack(spacing: 8) {
                Button("Open System Settings", action: openSettings)
                Button("Grant", action: grant)
                    .buttonStyle(.borderedProminent)
            }
        } else {
            Button("Open System Settings", action: openSettings)
                .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Microphone

struct MicrophonePane: View {
    @Bindable var appState: AppState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SettingsForm(title: SettingsPane.microphone.title) {
            SettingsSection {
                ControlSettingRow(.inputDevice, in: appState) {
                    // A menu picker is as wide as its longest device name; 200
                    // keeps the hint on one line. A cut name shows in full in
                    // the tooltip.
                    CappedWidth(maxWidth: 200) {
                        InputDevicePicker(title: SettingsRowID.inputDevice.title, microphone: appState.microphone)
                            .pickerStyle(.menu)
                            .help(selectedInputDeviceTitle)
                    }
                }

                if let warning = inputWarning {
                    SettingsWarningRow(warning: warning) {
                        if let recommended = appState.microphone.recommendedInputDevice {
                            Button("Use \(recommended.name)") {
                                appState.microphone.useRecommendedInputDevice()
                            }
                        }
                    }
                }
            } footer: {
                if let note = appState.microphone.inputStandInNote {
                    // Not a warning: skipping a Bluetooth or switched-off
                    // microphone is the intended behavior.
                    Text(note)
                        .transition(SettingsMotion.notice)
                }
            }

            SettingsSection {
                ToggleSettingRow(.echoCancellation, in: appState, isOn: $appState.echoCancellationEnabled)
                ToggleSettingRow(.soundFeedback, in: appState, isOn: $appState.soundFeedbackEnabled)
            }
        }
        .animation(SettingsMotion.curve(reduceMotion: reduceMotion), value: inputWarning)
        .animation(SettingsMotion.curve(reduceMotion: reduceMotion), value: appState.microphone.inputStandInNote)
    }

    /// A microphone problem is worth interrupting the list for; a working
    /// microphone is not.
    private var inputWarning: String? {
        if appState.microphone.audioRouteSnapshot == nil {
            return appState.microphone.audioRouteWarningText ?? appState.microphone.effectiveInputDeviceStatusText
        }
        return appState.microphone.audioRouteWarningText
    }

    private var selectedInputDeviceTitle: String {
        appState.microphone.menuChoices.first { $0.id == appState.microphone.selectedInputDeviceID }?.title ?? "System Default"
    }
}

// MARK: - Shortcuts

struct ShortcutsPane: View {
    @Bindable var appState: AppState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SettingsForm(title: SettingsPane.shortcuts.title) {
            SettingsSection {
                ControlSettingRow(.holdToDictate, in: appState) {
                    HotkeyRecorderButton(
                        configuration: Binding(
                            get: { appState.hotkeyConfiguration },
                            set: { newValue in
                                if let newValue {
                                    appState.updateDictationHotkey(newValue)
                                }
                            }
                        )
                    )
                }

                if let notice = globeNotice {
                    SettingsWarningRow(warning: notice) {
                        Button("Open System Settings") {
                            appState.openKeyboardSettings()
                        }
                    }
                }

                ControlSettingRow(.pasteLastTranscript, in: appState) {
                    HotkeyRecorderButton(
                        configuration: Binding(
                            get: { appState.pasteLastTranscriptHotkeyConfiguration },
                            set: { newValue in
                                if let newValue {
                                    appState.updatePasteLastTranscriptHotkey(newValue)
                                }
                            }
                        )
                    )
                }

                ControlSettingRow(.holdToEditSelection, in: appState) {
                    HotkeyRecorderButton(
                        configuration: $appState.editModeHotkeyConfiguration,
                        allowsClear: true,
                        clearHelp: "Remove the Edit Mode shortcut"
                    )
                }
            } footer: {
                if let message = appState.hotkeyValidationMessage {
                    SettingsProblemLine(message: message, tint: MainWindowPalette.errorText)
                }
            }

            SettingsSection {
                ToggleSettingRow(.pressEnterAfterPasting, in: appState, isOn: $appState.autoSubmitEnabled)
            }
        }
        .animation(SettingsMotion.curve(reduceMotion: reduceMotion), value: appState.hotkeyValidationMessage)
        .animation(SettingsMotion.curve(reduceMotion: reduceMotion), value: appState.globeDoubleTapConflict)
    }

    private var globeNotice: String? {
        appState.globeDoubleTapConflict.flatMap(Self.globeDoubleTapNotice)
    }

    private static func globeDoubleTapNotice(_ conflict: SystemGlobeKeyAction) -> String? {
        let action: String
        switch conflict {
        case .doNothing:
            return nil
        case .startDictation:
            action = "pressing Globe twice starts macOS Dictation"
        case .showEmojiAndSymbols:
            action = "Globe opens Emoji & Symbols"
        case .changeInputSource:
            action = "Globe changes the input source"
        }
        return "Double-tap is off: \(action). In Keyboard settings, choose Do Nothing for \u{201C}Press \u{1F310} key to\u{201D}."
    }
}

// MARK: - Indicator

struct IndicatorPane: View {
    @Bindable var appState: AppState

    var body: some View {
        SettingsForm(title: SettingsPane.indicator.title) {
            SettingsSection {
                ToggleSettingRow(.liveTranscriptionPreview, in: appState, isOn: $appState.liveTranscriptionPreviewEnabled)
                ToggleSettingRow(.hideWhileIdle, in: appState, isOn: $appState.hideFloatingIndicatorWhenIdle)
                ToggleSettingRow(.showMeetingTime, in: appState, isOn: $appState.showsMeetingTime)
            }

            SettingsSection {
                ControlSettingRow(.indicatorPosition, in: appState) {
                    HStack(spacing: 10) {
                        Text(appState.floatingIndicatorPlacement == nil ? "Default" : "Moved")
                            .foregroundStyle(MainWindowPalette.settingsSecondaryText)

                        Button("Reset") {
                            appState.resetFloatingIndicatorPlacement()
                        }
                        .disabled(appState.floatingIndicatorPlacement == nil)
                    }
                }
            }
        }
    }
}

// MARK: - General

/// What belongs to the app rather than to a feature: startup, privacy and
/// updates.
struct GeneralSettingsPane: View {
    @Bindable var appState: AppState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SettingsForm(title: SettingsPane.general.title) {
            appearanceSection
            startup
            privacy
            about
        }
        .animation(SettingsMotion.curve(reduceMotion: reduceMotion), value: launchAtLoginNotice?.message)
    }

    /// A failure to change the login item is an error; a login item that
    /// macOS holds for approval is a warning.
    private var launchAtLoginNotice: (message: String, tint: Color)? {
        if let error = appState.launchAtLoginError {
            return (error, MainWindowPalette.errorText)
        }
        return appState.launchAtLoginWarningText.map { ($0, MainWindowPalette.warningText) }
    }

    private var appearanceSection: some View {
        SettingsSection("Appearance") {
            ControlSettingRow(.theme, in: appState) {
                Picker("Theme", selection: $appState.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
    }

    private var startup: some View {
        SettingsSection("Startup") {
            ToggleSettingRow(
                .launchAtLogin,
                in: appState,
                isOn: Binding(
                    get: { appState.launchAtLoginEnabledForUI },
                    set: { appState.setLaunchAtLoginEnabled($0) }
                )
            )
        } footer: {
            if let notice = launchAtLoginNotice {
                SettingsProblemLine(message: notice.message, tint: notice.tint)
            }
        }
    }

    private var privacy: some View {
        SettingsSection("Privacy") {
            ToggleSettingRow(
                .shareAnonymousAnalytics,
                in: appState,
                isOn: Binding(
                    get: { appState.shareAnalyticsEnabled },
                    set: { appState.shareAnalyticsEnabled = $0 }
                )
            )
            DisclosureSettingRow(.whatWeCollect, in: appState, value: "", opensOutside: true) {
                appState.openAnalyticsPrivacyInfo()
            }
        }
    }

    private var about: some View {
        SettingsSection("About") {
            ControlSettingRow(.version, in: appState) {
                HStack(spacing: 10) {
                    Text(numbers: appState.appVersionText)
                        .foregroundStyle(MainWindowPalette.settingsSecondaryText)

                    if appState.isUpdateReadyToInstall {
                        Button("Restart to Update") {
                            appState.restartToUpdate()
                        }
                        .disabled(!appState.canRestartToUpdate)
                    } else if appState.updatesEnabled {
                        Button("Check for Updates") {
                            appState.checkForUpdates()
                        }
                        .disabled(!appState.canCheckForUpdates)
                    }
                }
            }

            // A build without updates (Preview) hides the controls that would
            // do nothing; the Version hint says why.
            if SettingsRowID.updateChannel.isAvailable(in: appState) {
                ControlSettingRow(.updateChannel, in: appState) {
                    Picker(
                        "Update channel",
                        selection: Binding(
                            get: { appState.updateChannel },
                            set: { appState.setUpdateChannel($0) }
                        )
                    ) {
                        ForEach(UpdateChannel.allCases) { channel in
                            Text(channel.title)
                                .tag(channel)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }

            if SettingsRowID.checkAutomatically.isAvailable(in: appState) {
                ToggleSettingRow(
                    .checkAutomatically,
                    in: appState,
                    isOn: Binding(
                        get: { appState.automaticallyChecksForUpdates },
                        set: { appState.setAutomaticallyChecksForUpdates($0) }
                    )
                )
            }

            DisclosureSettingRow(.reportAProblem, in: appState, value: "", opensOutside: true) {
                appState.openIssueReportWindow()
            }
        }
    }
}

// MARK: - Shared pieces

/// A problem in a section, with the action that fixes it.
private struct SettingsWarningRow<Action: View>: View {
    let warning: String
    @ViewBuilder let action: Action

    /// It belongs to the row above it, so it draws no hairline and starts on
    /// the row text's edge.
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Label {
                Text(numbers: warning).foregroundStyle(MainWindowPalette.settingsText)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .frame(width: 18)
                    .foregroundStyle(MainWindowPalette.warningText)
            }
            .font(AppTypography.subheadline)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 12)

            action
        }
        .padding(.horizontal, AppMetrics.settingsRowInset)
        .padding(.bottom, AppMetrics.settingsRowVerticalPadding + 2)
        .transition(SettingsMotion.notice)
    }
}

/// A section footer that says what went wrong, in the color of how bad it is.
private struct SettingsProblemLine: View {
    let message: String
    let tint: Color

    var body: some View {
        Label {
            Text(numbers: message)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(AppTypography.subheadline)
        .foregroundStyle(tint)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(SettingsMotion.notice)
    }
}

/// A key drawn as a keyboard key: a raised face with a darker lower edge. The
/// face has the fill of the native buttons around it, so a cap does not read
/// as an empty field. Modifiers are symbols, which sit centered in the cap
/// where the text glyphs ⌃ and ⌥ sit high.
private struct KeyCap: View {
    let label: String
    var showsGlobe = false

    private static let modifierSymbols = ["⌃": "control", "⌥": "option", "⇧": "shift", "⌘": "command"]

    var body: some View {
        HStack(spacing: 4) {
            if showsGlobe {
                Image(systemName: "globe")
                    .font(AppTypography.caption.weight(.medium))
            }
            if let symbol = Self.modifierSymbols[label] {
                Image(systemName: symbol)
                    .font(AppTypography.caption.weight(.semibold))
                    .accessibilityLabel(label)
            } else {
                Text(label)
                    .font(AppTypography.calloutMedium)
            }
        }
        .foregroundStyle(MainWindowPalette.settingsText)
        .padding(.horizontal, 7)
        .frame(minWidth: 24, minHeight: 24)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(MainWindowPalette.selectedFill)
                .shadow(color: .black.opacity(0.18), radius: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(MainWindowPalette.cardStroke, lineWidth: 1)
        )
    }
}

private struct HotkeyRecorderButton: View {
    @Binding var configuration: HotkeyConfiguration?
    var allowsClear = false
    var clearHelp = "Remove the shortcut"
    @State private var isCapturing = false
    @State private var isHovered = false
    @State private var localMonitor: Any?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            Button {
                toggleCapture()
            } label: {
                // Listening, a new shortcut and a cleared one each replace the
                // label: a short cross-fade shows that the recorder heard the
                // keys. Recording a shortcut is rare, so the motion is cheap.
                ZStack(alignment: .trailing) {
                    recorderLabel
                        .id(labelState)
                        .transition(labelTransition)
                }
                .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.16), value: labelState)
                // Minimum, not fixed: a hard height clips at larger text sizes.
                .frame(minHeight: 32)
                // The surface reaches 6 pt past the caps, so the caps end on
                // the same edge as the switches and menus in other rows.
                .background(recorderSurface.padding(.horizontal, -6))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle(pressedScale: 0.98))
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .accessibilityLabel(isCapturing ? "Press shortcut" : (configuration?.displayString ?? "Not Set"))

            if allowsClear && configuration != nil && !isCapturing {
                Button {
                    configuration = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(MainWindowPalette.secondaryText)
                }
                .buttonStyle(PressableButtonStyle(pressedScale: 0.9))
                .help(clearHelp)
            }
        }
        .onDisappear {
            stopCapturing()
        }
    }

    private var labelState: String {
        isCapturing ? "listening" : (configuration?.displayString ?? "not set")
    }

    /// Grows from the trailing edge, where the control sits. Reduce Motion
    /// keeps the fade and drops the scale.
    private var labelTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96, anchor: .trailing))
    }

    /// One cap per key while a shortcut is set; text while there is none or
    /// while it listens.
    @ViewBuilder
    private var recorderLabel: some View {
        if isCapturing {
            Text("Press shortcut")
                .font(AppTypography.callout)
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 6)
        } else if let configuration {
            HStack(spacing: 4) {
                ForEach(Array(configuration.keyCapLabels.enumerated()), id: \.offset) { _, label in
                    KeyCap(label: label, showsGlobe: configuration.kind == .globe)
                }
            }
        } else {
            Text("Not Set")
                .font(AppTypography.callout)
                .foregroundStyle(MainWindowPalette.secondaryText)
                .padding(.horizontal, 10)
                .frame(minHeight: 24)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                )
        }
    }

    /// No surface at rest, so the caps stand on the card. Hover shows that the
    /// caps are one button, and an accent edge shows that it is listening.
    private var recorderSurface: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return shape.fill(isHovered || isCapturing ? MainWindowPalette.selectedFill : .clear)
            .overlay(
                shape.strokeBorder(Color.accentColor.opacity(isCapturing ? 0.7 : 0), lineWidth: 1.5)
            )
    }

    private func toggleCapture() {
        if isCapturing {
            stopCapturing()
        } else {
            startCapturing()
        }
    }

    private func startCapturing() {
        isCapturing = true
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stopCapturing()
                return nil
            }

            // Collision policy is owned by AppState's didSet observers: a colliding
            // capture is written through the binding, rejected there (with the value
            // reverted and a user-visible message), and this view re-renders the
            // reverted configuration.
            if let captured = HotkeyConfiguration.from(event: event) {
                configuration = captured
                stopCapturing()
                return nil
            }

            return event
        }
    }

    private func stopCapturing() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        isCapturing = false
    }
}
