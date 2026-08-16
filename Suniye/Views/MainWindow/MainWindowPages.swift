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

    var body: some View {
        DetailScrollContainer {
            if !appState.hasMicPermission || !appState.hasAccessibilityPermission {
                VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
                    SectionHeading(title: "Permissions")

                    SurfaceCard {
                        VStack(spacing: 0) {
                            if !appState.hasMicPermission {
                                PermissionActionRow(
                                    title: "Microphone",
                                    detail: "Required to capture dictation audio.",
                                    isGranted: false,
                                    primaryTitle: "Request Access",
                                    primaryAction: {
                                        appState.requestMicrophonePermission()
                                    },
                                    secondaryTitle: "Open Settings",
                                    secondaryAction: {
                                        appState.openMicrophonePrivacySettings()
                                    }
                                )
                            }

                            if !appState.hasMicPermission && !appState.hasAccessibilityPermission {
                                CardDivider()
                                    .padding(.vertical, AppMetrics.toggleDetailVerticalPadding)
                            }

                            if !appState.hasAccessibilityPermission {
                                PermissionActionRow(
                                    title: "Accessibility",
                                    detail: "Required to paste transcribed text into other apps.",
                                    isGranted: false,
                                    primaryTitle: "Request Access",
                                    primaryAction: {
                                        appState.beginAccessibilityOnboarding()
                                    },
                                    secondaryTitle: "Open Settings",
                                    secondaryAction: {
                                        appState.openAccessibilityPrivacySettings()
                                    }
                                )
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
                SectionHeading(title: "Microphone")

                SurfaceCard {
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            Text("Input Device")
                                .font(AppTypography.body)
                            Spacer(minLength: 12)
                            NativePopupPicker(
                                items: inputDeviceChoices,
                                selection: inputDeviceSelection,
                                title: \.title
                            )
                            .frame(maxWidth: 300)
                        }

                        CardDivider()
                            .padding(.vertical, AppMetrics.toggleDetailVerticalPadding)

                        VStack(alignment: .leading, spacing: 8) {
                            Label(
                                appState.effectiveInputDeviceStatusText,
                                systemImage: appState.audioRouteSnapshot == nil
                                    ? "exclamationmark.triangle.fill"
                                    : "mic.fill"
                            )
                            .font(AppTypography.subheadline)
                            .foregroundStyle(
                                appState.audioRouteSnapshot == nil
                                    ? Color.orange
                                    : MainWindowPalette.secondaryText
                            )

                            if let warning = appState.audioRouteWarningText {
                                Text(warning)
                                    .font(AppTypography.subheadline)
                                    .foregroundStyle(MainWindowPalette.secondaryText)
                            }

                            if (appState.audioRouteSnapshot?.inputTransport.isBluetooth == true
                                || appState.audioRouteSnapshot == nil),
                               let recommended = appState.recommendedInputDevice {
                                Button("Use \(recommended.name)") {
                                    appState.useRecommendedInputDevice()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        CardDivider()
                            .padding(.vertical, AppMetrics.toggleDetailVerticalPadding)

                        SettingsToggleRow(
                            title: "Echo Cancellation",
                            detail: "Uses Apple's Voice Processing when the current input and output route supports it. It is bypassed for Bluetooth routes.",
                            isOn: $appState.echoCancellationEnabled
                        )

                        CardDivider()
                            .padding(.vertical, AppMetrics.toggleDetailVerticalPadding)

                        SettingsToggleRow(
                            title: "Sound Feedback",
                            detail: "Play short local sounds when dictation succeeds or fails.",
                            isOn: $appState.soundFeedbackEnabled
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
                SectionHeading(title: "Hotkeys")

                SurfaceCard {
                    VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
                        HStack(spacing: 12) {
                            Text("Hold to Dictate")
                                .font(AppTypography.body)
                            Spacer(minLength: 12)
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
                        CardDivider()
                        Text("Works from any app. Hold the shortcut to record, release to transcribe.")
                            .font(AppTypography.subheadline)
                            .foregroundStyle(MainWindowPalette.secondaryText)
                        CardDivider()
                        HStack(spacing: 12) {
                            Text("Paste Last Transcript")
                                .font(AppTypography.body)
                            Spacer(minLength: 12)
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
                        CardDivider()
                        Text("Focus a text field and press this shortcut to insert your latest completed dictation without submitting it again.")
                            .font(AppTypography.subheadline)
                            .foregroundStyle(MainWindowPalette.secondaryText)
                        if let message = appState.hotkeyValidationMessage {
                            CardDivider()
                            Text(message)
                                .font(AppTypography.subheadline)
                                .foregroundStyle(.red)
                        }
                        CardDivider()
                        HStack(spacing: 12) {
                            Text("Hold to Edit Selection")
                                .font(AppTypography.body)
                            Spacer(minLength: 12)
                            HotkeyRecorderButton(
                                configuration: $appState.editModeHotkeyConfiguration,
                                idleIcon: "pencil.line",
                                allowsClear: true,
                                clearHelp: "Remove the Edit Mode shortcut"
                            )
                        }
                        CardDivider()
                        Text("Select text in any app, hold the shortcut, and speak an instruction like \"make this formal\". With nothing selected, the spoken instruction generates text at the cursor. Requires Magic Format.")
                            .font(AppTypography.subheadline)
                            .foregroundStyle(MainWindowPalette.secondaryText)
                    }
                }
            }

            VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
                SectionHeading(title: "Indicator")

                SurfaceCard {
                    VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
                        SettingsToggleRow(
                            title: "Live Transcription Preview",
                            detail: "Show the transcript in the floating indicator while you dictate. Decoding stays fully local.",
                            isOn: $appState.liveTranscriptionPreviewEnabled
                        )

                        CardDivider()

                        SettingsToggleRow(
                            title: "Hide While Idle",
                            detail: "Hide the floating indicator when \(AppIdentity.current.displayName) is ready but not actively dictating. When hidden, floating click-to-start is unavailable until the indicator appears again for recording, processing, or errors.",
                            isOn: $appState.hideFloatingIndicatorWhenIdle
                        )

                        CardDivider()

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Indicator Position")
                                    .font(AppTypography.body)
                                Text("Drag the floating pill to place it somewhere that stays out of the way.")
                                    .font(AppTypography.subheadline)
                                    .foregroundStyle(MainWindowPalette.secondaryText)
                            }

                            Spacer(minLength: 12)

                            Button("Reset Position") {
                                appState.resetFloatingIndicatorPlacement()
                            }
                            .buttonStyle(.bordered)
                            .disabled(appState.floatingIndicatorPlacement == nil)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
                SectionHeading(title: "After Paste")

                SurfaceCard {
                    SettingsToggleRow(
                        title: "Auto-press Enter after paste",
                        detail: "Automatically press Enter/Return after pasting transcribed text. You can also still say \"send\" or \"enter\" at the end of a dictation to trigger this per-message.",
                        isOn: $appState.autoSubmitEnabled
                    )
                }
            }

            VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
                SectionHeading(title: "Startup")

                SurfaceCard {
                    VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
                        SettingsToggleRow(
                            title: "Launch at Login",
                            detail: appState.launchAtLoginDetailText,
                            isOn: Binding(
                                get: { appState.launchAtLoginEnabledForUI },
                                set: { appState.setLaunchAtLoginEnabled($0) }
                            )
                        )

                        if let error = appState.launchAtLoginError {
                            Text(error)
                                .font(AppTypography.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
                SectionHeading(title: "Privacy")

                SurfaceCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SettingsToggleRow(
                            title: "Share Anonymous Analytics",
                            detail: "Helps improve Suniye with anonymous usage stats — word counts, timings, hardware, and feature usage. Never your audio or transcripts. Turn off anytime.",
                            isOn: Binding(
                                get: { appState.shareAnalyticsEnabled },
                                set: { appState.shareAnalyticsEnabled = $0 }
                            )
                        )
                        Button("Learn what we collect") {
                            appState.openAnalyticsPrivacyInfo()
                        }
                        .buttonStyle(.link)
                        .font(AppTypography.subheadline)
                    }
                }
            }

            VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
                SectionHeading(title: "About")

                SurfaceCard {
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Text(AppIdentity.current.displayName)
                                .font(AppTypography.bodyMedium)
                            Spacer(minLength: 0)
                            Text(appState.appVersionText)
                                .font(AppTypography.codeBodyMedium)
                                .foregroundStyle(MainWindowPalette.secondaryText)
                        }

                        CardDivider()

                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Update Channel")
                                    .font(AppTypography.body)
                                Text(appState.updateChannel.detail)
                                    .font(AppTypography.subheadline)
                                    .foregroundStyle(MainWindowPalette.secondaryText)
                            }

                            Spacer(minLength: 12)

                            Picker(
                                "Update Channel",
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
                            .pickerStyle(.segmented)
                            .frame(width: 160)
                        }

                        CardDivider()

                        SettingsToggleRow(
                            title: "Automatically Check for Updates",
                            detail: "\(AppIdentity.current.displayName) checks in the background and asks before installing.",
                            isOn: Binding(
                                get: { appState.automaticallyChecksForUpdates },
                                set: { appState.setAutomaticallyChecksForUpdates($0) }
                            )
                        )

                        CardDivider()

                        HStack(spacing: 8) {
                            Button("Report a Problem") {
                                appState.openIssueReportWindow()
                            }
                            .buttonStyle(.bordered)

                            Spacer(minLength: 12)

                            Button("Check for Updates") {
                                appState.checkForUpdates()
                            }
                            .buttonStyle(.bordered)
                            .disabled(!appState.canCheckForUpdates)
                        }
                    }
                }
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

    /// The recorder sits on a card, so it needs a surface of its own to read as
    /// pressable. On macOS 26 that is interactive glass; below it, the elevated
    /// input fill, matching the app's other editable fields.
    @ViewBuilder
    private var recorderSurface: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        if #available(macOS 26, *) {
            shape.fill(.clear)
                .glassEffect(isCapturing ? .regular.interactive() : .regular, in: shape)
        } else {
            shape.fill(MainWindowPalette.editorBackground)
        }
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
