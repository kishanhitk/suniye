import Carbon
import AppKit
import SwiftUI

/// Post-onboarding Magic Format pitch, shown once the user has real dictations
/// to judge it against. The before/after snippet makes the value concrete.
struct MagicFormatNudgeCard: View {
    let onSetUp: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        SurfaceCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(AppTypography.bodyMedium)
                        .foregroundStyle(Color.accentColor)
                    Text("Make dictations cleaner")
                        .font(AppTypography.bodyMedium)
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("\u{201C}so um send the report friday\u{201D}")
                        .font(AppTypography.caption)
                        .foregroundStyle(MainWindowPalette.tertiaryText)
                        .strikethrough(color: MainWindowPalette.tertiaryText)
                    Text("\u{201C}Send the report by Friday.\u{201D}")
                        .font(AppTypography.caption)
                        .foregroundStyle(Color.primary)
                }

                Text("Magic Format fixes punctuation and filler words on your Mac, before text is pasted.")
                    .font(AppTypography.caption)
                    .foregroundStyle(MainWindowPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button("Set Up Magic Format", action: onSetUp)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button("Not Now", action: onDismiss)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

struct GeneralPage: View {
    @Bindable var appState: AppState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        DetailScrollContainer {
            DetailPageTitle(title: "General")

            if !appState.hasMicPermission || !appState.hasAccessibilityPermission {
                permissions
                    .transition(SettingsMotion.banner(reduceMotion: reduceMotion))
            }

            microphone
            shortcuts
            indicator
            dictation
            startup
            privacy
            about
        }
        // Granting a permission deletes a whole group and pulls the rest of the
        // page up. It is also the moment the app starts working, so the change
        // is worth showing rather than snapping.
        .animation(motion, value: appState.hasMicPermission)
        .animation(motion, value: appState.hasAccessibilityPermission)
        .animation(motion, value: inputWarning)
        .animation(motion, value: appState.hotkeyValidationMessage)
        .animation(motion, value: appState.launchAtLoginError ?? appState.launchAtLoginWarningText)
    }

    private var motion: Animation? {
        SettingsMotion.curve(reduceMotion: reduceMotion)
    }

    // MARK: - Permissions

    /// Only rendered while something is missing, so it never becomes a row of
    /// green ticks reporting that nothing is wrong.
    private var permissions: some View {
        SettingsGroup(
            heading: "Permissions",
            note: "\(AppIdentity.current.displayName) cannot dictate until these are allowed."
        ) {
            if !appState.hasMicPermission {
                PermissionRow(appState: appState, presentation: appState.microphonePresentation, askSurface: .settings)
            }

            if !appState.hasMicPermission && !appState.hasAccessibilityPermission {
                RowSeparator()
            }

            if !appState.hasAccessibilityPermission {
                PermissionRow(appState: appState, presentation: appState.accessibilityPresentation, askSurface: .settings)
            }
        }
    }

    // MARK: - Microphone

    private var microphone: some View {
        SettingsGroup(heading: "Microphone") {
            ControlSettingRow(
                title: "Input device",
                // Only while the picker says "System Default" and therefore hides
                // which device that actually is.
                info: appState.selectedInputDeviceID == nil ? appState.effectiveInputDeviceStatusText : nil
            ) {
                NativePopupPicker(
                    items: inputDeviceChoices,
                    selection: inputDeviceSelection,
                    title: \.title
                )
                .frame(maxWidth: 260)
            }

            if let warning = inputWarning {
                inputWarningRow(warning)
            }

            RowSeparator()
            ToggleSettingRow(
                title: "Echo cancellation",
                info: "Uses Apple's Voice Processing when the current input and output route supports it. It is bypassed for Bluetooth routes.",
                isOn: $appState.echoCancellationEnabled
            )

            RowSeparator()
            ToggleSettingRow(
                title: "Sound feedback",
                isOn: $appState.soundFeedbackEnabled
            )
        }
    }

    /// A microphone problem is worth interrupting the list for; a working
    /// microphone is not.
    private var inputWarning: String? {
        if appState.audioRouteSnapshot == nil {
            return appState.audioRouteWarningText ?? appState.effectiveInputDeviceStatusText
        }
        return appState.audioRouteWarningText
    }

    private func inputWarningRow(_ warning: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Label(warning, systemImage: "exclamationmark.triangle.fill")
                .font(AppTypography.subheadline)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 12)

            if let recommended = appState.recommendedInputDevice {
                Button("Use \(recommended.name)") {
                    appState.useRecommendedInputDevice()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.bottom, 12)
        .padding(.horizontal, 4)
        .transition(SettingsMotion.notice)
    }

    // MARK: - Shortcuts

    private var shortcuts: some View {
        SettingsGroup(heading: "Shortcuts") {
            ControlSettingRow(
                title: "Hold to dictate"
            ) {
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

            RowSeparator()
            ControlSettingRow(
                title: "Paste last transcript",
                info: "Focus a text field and press this shortcut to insert your latest completed dictation without submitting it again."
            ) {
                HotkeyRecorderButton(
                    configuration: Binding(
                        get: { appState.pasteLastTranscriptHotkeyConfiguration },
                        set: { newValue in
                            if let newValue {
                                appState.updatePasteLastTranscriptHotkey(newValue)
                            }
                        }
                    ),
                    idleIcon: "text.insert"
                )
            }

            RowSeparator()
            ControlSettingRow(
                title: "Hold to edit selection",
                info: "Select text in any app, hold the shortcut, and speak an instruction like \"make this formal\". With nothing selected, the spoken instruction generates text at the cursor. Requires Magic Format."
            ) {
                HotkeyRecorderButton(
                    configuration: $appState.editModeHotkeyConfiguration,
                    idleIcon: "pencil.line",
                    allowsClear: true,
                    clearHelp: "Remove the Edit Mode shortcut"
                )
            }

            if let message = appState.hotkeyValidationMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(SettingsMotion.notice)
            }
        }
    }

    // MARK: - Indicator

    private var indicator: some View {
        SettingsGroup(heading: "Indicator") {
            ToggleSettingRow(
                title: "Live transcription preview",
                isOn: $appState.liveTranscriptionPreviewEnabled
            )

            RowSeparator()
            ToggleSettingRow(
                title: "Hide while idle",
                info: "Hide the floating indicator when \(AppIdentity.current.displayName) is ready but not actively dictating. When hidden, floating click-to-start is unavailable until the indicator appears again for recording, processing, or errors.",
                isOn: $appState.hideFloatingIndicatorWhenIdle
            )

            RowSeparator()
            ControlSettingRow(
                title: "Position",
                info: "Drag the floating pill to place it somewhere that stays out of the way."
            ) {
                HStack(spacing: 12) {
                    Text(appState.floatingIndicatorPlacement == nil ? "Default" : "Moved")
                        .font(AppTypography.rowTitle)
                        .foregroundStyle(MainWindowPalette.secondaryText)

                    Button("Reset") {
                        appState.resetFloatingIndicatorPlacement()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(appState.floatingIndicatorPlacement == nil)
                }
            }
        }
    }

    // MARK: - Dictation

    private var dictation: some View {
        SettingsGroup(heading: "Dictation") {
            ToggleSettingRow(
                title: "Press Enter after pasting",
                info: "You can also say \"send\" or \"enter\" at the end of a dictation to trigger this once, without turning it on here.",
                isOn: $appState.autoSubmitEnabled
            )
        }
    }

    // MARK: - Startup

    private var startup: some View {
        SettingsGroup(heading: "Startup") {
            ToggleSettingRow(
                title: "Launch at login",
                isOn: Binding(
                    get: { appState.launchAtLoginEnabledForUI },
                    set: { appState.setLaunchAtLoginEnabled($0) }
                )
            )

            if let notice = appState.launchAtLoginError ?? appState.launchAtLoginWarningText {
                Label(notice, systemImage: "exclamationmark.triangle.fill")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(appState.launchAtLoginError == nil ? Color.orange : Color.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(SettingsMotion.notice)
            }
        }
    }

    // MARK: - Privacy

    private var privacy: some View {
        SettingsGroup(heading: "Privacy") {
            ToggleSettingRow(
                title: "Share anonymous analytics",
                isOn: Binding(
                    get: { appState.shareAnalyticsEnabled },
                    set: { appState.shareAnalyticsEnabled = $0 }
                )
            )

            RowSeparator()
            DisclosureSettingRow(title: "What we collect", value: "") {
                appState.openAnalyticsPrivacyInfo()
            }
        }
    }

    // MARK: - About

    private var about: some View {
        SettingsGroup(heading: "About") {
            ControlSettingRow(title: "Version") {
                HStack(spacing: 12) {
                    Text(appState.appVersionText)
                        .font(AppTypography.codeBody)
                        .foregroundStyle(MainWindowPalette.secondaryText)

                    ActionIconButton(
                        systemName: "arrow.triangle.2.circlepath",
                        accessibilityLabel: "Check for updates",
                        tint: MainWindowPalette.tertiaryText,
                        hoverTint: Color.primary
                    ) {
                        appState.checkForUpdates()
                    }
                    .help("Check for updates")
                    .disabled(!appState.canCheckForUpdates)
                    .opacity(appState.canCheckForUpdates ? 1 : 0.4)
                }
            }

            RowSeparator()
            ControlSettingRow(
                title: "Update channel",
                info: appState.updateChannel.detail
            ) {
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

            RowSeparator()
            ToggleSettingRow(
                title: "Check automatically",
                isOn: Binding(
                    get: { appState.automaticallyChecksForUpdates },
                    set: { appState.setAutomaticallyChecksForUpdates($0) }
                )
            )

            RowSeparator()
            DisclosureSettingRow(title: "Report a problem", value: "") {
                appState.openIssueReportWindow()
            }
        }
    }

    private var inputDeviceChoices: [InputDeviceChoice] {
        let devices = appState.availableInputDevices.map {
            let availability = $0.isAvailable ? "" : " - Unavailable"
            let defaultLabel = $0.isDefault ? " - Default" : ""
            return InputDeviceChoice(
                id: $0.id,
                title: "\($0.name) - \($0.transport.title)\(defaultLabel)\(availability)"
            )
        }
        return [InputDeviceChoice(id: nil, title: "System Default")] + devices
    }

    private var inputDeviceSelection: Binding<InputDeviceChoice> {
        Binding(
            get: {
                inputDeviceChoices.first(where: { $0.id == appState.selectedInputDeviceID })
                    ?? InputDeviceChoice(id: appState.selectedInputDeviceID, title: "System Default")
            },
            set: { appState.selectedInputDeviceID = $0.id }
        )
    }
}

private struct InputDeviceChoice: Hashable {
    let id: String?
    let title: String
}

private struct HotkeyRecorderButton: View {
    @Binding var configuration: HotkeyConfiguration?
    var idleIcon = "globe"
    var allowsClear = false
    var clearHelp = "Remove the shortcut"
    @State private var isCapturing = false
    @State private var localMonitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Button {
                toggleCapture()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isCapturing ? "record.circle" : idleIcon)
                        .font(.headline.weight(.medium))
                    Text(isCapturing ? "Press shortcut" : (configuration?.displayString ?? "Not Set"))
                        .font(AppTypography.codeBodyMedium)
                }
                .padding(.horizontal, 12)
                // Minimum, not fixed: a hard height clips at larger text sizes.
                .frame(minHeight: 34)
                .background(recorderSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isCapturing ? Color.accentColor.opacity(0.5) : MainWindowPalette.cardStroke, lineWidth: 1)
                )
            }
            .buttonStyle(PressableButtonStyle(pressedScale: 0.98))

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

    /// The recorder needs a surface of its own to read as pressable. Flat, like
    /// the app's other editable fields, with an accent edge while capturing
    /// standing in for what the glass highlight used to say.
    private var recorderSurface: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return shape.fill(MainWindowPalette.editorBackground)
            .overlay(
                shape.strokeBorder(
                    isCapturing ? Color.accentColor.opacity(0.7) : MainWindowPalette.cardStroke,
                    lineWidth: isCapturing ? 1.5 : 1
                )
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
