import SwiftUI

struct ComputerUseSettingsDisclosure: View {
    @Bindable var coordinator: ComputerUseCoordinator
    @Bindable var modelSettings: ComputerUseModelSettingsController
    @Bindable var appState: AppState
    @State private var showVoiceActivationNotice = false

    var body: some View {
        DisclosureGroup {
            VStack(spacing: 0) {
                modelConfiguration
                Divider().padding(.vertical, 10)
                voiceActivationSection
                Divider().padding(.vertical, 10)
                permissionRow(
                    title: "Accessibility",
                    detail: "Reads controls and sends input to apps.",
                    state: coordinator.permissionSnapshot.accessibility,
                    request: coordinator.requestAccessibility,
                    openSettings: {
                        coordinator.openPermissionSettings(.accessibility)
                    }
                )
                Divider().padding(.vertical, 10)
                permissionRow(
                    title: "Screen Recording",
                    detail: "Captures the selected app window for visual context.",
                    state: coordinator.permissionSnapshot.screenRecording,
                    request: coordinator.requestScreenRecording,
                    openSettings: {
                        coordinator.openPermissionSettings(.screenRecording)
                    }
                )
            }
            .padding(.top, 14)
        } label: {
            Label("Computer Use settings", systemImage: "slider.horizontal.3")
                .font(AppTypography.bodyMedium)
        }
        .padding(16)
        .background(MainWindowPalette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MainWindowPalette.cardStroke, lineWidth: 1)
        )
    }

    /// UX plan: Voice Activation section — toggle, wake phrase display,
    /// toggle shortcut, sound feedback, follow-up window (experimental).
    private var voiceActivationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: appState.voiceActivationEnabled ? "waveform.circle.fill" : "waveform.circle")
                    .foregroundStyle(appState.voiceActivationEnabled ? Color.green : MainWindowPalette.tertiaryText)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Voice Activation")
                        .font(AppTypography.bodyMedium)
                    Text("Say “Hey Suniye” from anywhere to start, correct, or stop a task. Say “stop listening” to turn it off.")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(MainWindowPalette.secondaryText)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { appState.voiceActivationEnabled },
                    set: { enabled in
                        if enabled, !appState.voiceActivationNoticeAcknowledged {
                            showVoiceActivationNotice = true
                        } else {
                            appState.voiceActivationEnabled = enabled
                        }
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
            if appState.voiceActivationEnabled {
                HStack(spacing: 12) {
                    Text("Toggle shortcut")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(MainWindowPalette.secondaryText)
                    Spacer()
                    HotkeyRecorderButton(
                        configuration: $appState.voiceActivationToggleHotkeyConfiguration,
                        idleIcon: "waveform",
                        allowsClear: true,
                        clearHelp: "Remove the Voice Activation shortcut"
                    )
                }
                Toggle("Sound feedback for wake-up and completion", isOn: $appState.voiceActivationSoundFeedbackEnabled)
                    .font(AppTypography.subheadline)
                Toggle("Follow-up window after a task completes (experimental)", isOn: $appState.voiceActivationFollowUpWindowEnabled)
                    .font(AppTypography.subheadline)
                tryWakePhraseRow
            }
        }
        .alert("Voice Activation keeps the microphone in use", isPresented: $showVoiceActivationNotice) {
            Button("Turn On") {
                appState.voiceActivationNoticeAcknowledged = true
                appState.voiceActivationEnabled = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("While waiting for “Hey Suniye,” audio is processed on this Mac in a rolling in-memory buffer of at most 35 seconds. It is never written to disk, and nothing leaves the machine before the wake phrase. The macOS microphone indicator stays visible the whole time.")
        }
    }

    /// UX plan: the try-wake-phrase flow. Live microphone levels plus the
    /// current listening state, so both the wake word and a dead microphone
    /// are testable without leaving Settings.
    private var tryWakePhraseRow: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                let levels = appState.voiceActivationLiveLevels
                ForEach(0..<12, id: \.self) { index in
                    let level = levels.indices.contains(index * 2) ? levels[index * 2] : 0
                    Capsule()
                        .fill(level > 0.05 ? Color.green : MainWindowPalette.tertiaryText.opacity(0.4))
                        .frame(width: 3, height: 4 + CGFloat(min(1, level)) * 14)
                }
            }
            .frame(height: 20)
            .animation(.linear(duration: 0.05), value: appState.voiceActivationLiveLevels)

            Text(tryWakePhraseStatus)
                .font(AppTypography.subheadline)
                .foregroundStyle(tryWakePhraseIsHot ? Color.green : MainWindowPalette.secondaryText)
            Spacer()
        }
        .padding(10)
        .background(MainWindowPalette.selectedFill)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var tryWakePhraseIsHot: Bool {
        if case .listening = appState.voiceActivationDisplayState {
            return true
        }
        if case .transcribing = appState.voiceActivationDisplayState {
            return true
        }
        return false
    }

    private var tryWakePhraseStatus: String {
        switch appState.voiceActivationDisplayState {
        case .off:
            return "Voice Activation is off."
        case .suspended:
            return "Paused — the microphone is in use elsewhere or unavailable."
        case .ready:
            return "Try it: say “Hey Suniye.” The bars should move as you speak; if they stay flat, check the Microphone permission."
        case .listening:
            return "Heard it — listening. Say a task, or wait to return to ready."
        case .transcribing:
            return "Transcribing your turn…"
        case .followUpWindow:
            return "Follow-up window open — speak to continue without the wake phrase."
        }
    }

    private var modelConfiguration: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: modelSettings.isReady ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(modelSettings.isReady ? Color.green : MainWindowPalette.tertiaryText)
                Text("Model")
                    .font(AppTypography.bodyMedium)
                Spacer()
                Picker("Provider", selection: $modelSettings.settings.provider) {
                    ForEach(ComputerUseModelProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
            }

            labeledField("Model ID") {
                TextField("gpt-5.6-luna", text: $modelSettings.settings.modelID)
                    .textFieldStyle(.roundedBorder)
            }

            labeledField("API endpoint") {
                if modelSettings.settings.provider == .custom {
                    TextField(
                        "https://example.com/v1/chat/completions",
                        text: $modelSettings.settings.customEndpointURLString
                    )
                    .textFieldStyle(.roundedBorder)
                } else {
                    Text(modelSettings.settings.endpointURLString)
                        .font(AppTypography.codeBody)
                        .foregroundStyle(MainWindowPalette.secondaryText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            labeledField("API key") {
                HStack(spacing: 8) {
                    SecureField(
                        apiKeyPlaceholder,
                        text: $modelSettings.apiKeyDraft
                    )
                    .textFieldStyle(.roundedBorder)
                    Button("Save") {
                        modelSettings.saveAPIKey()
                    }
                    .disabled(modelSettings.apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if modelSettings.hasAPIKey {
                        Button("Clear", action: modelSettings.clearAPIKey)
                    }
                }
            }

            if let message = modelSettings.status.message {
                Text(message)
                    .font(AppTypography.caption)
                    .foregroundStyle(
                        modelSettings.status.isError ? Color.red : MainWindowPalette.secondaryText
                    )
                    .textSelection(.enabled)
            }

            HStack {
                Spacer()
                Button("Test connection") {
                    Task { await modelSettings.testConnection() }
                }
                .disabled(!modelSettings.isReady || modelSettings.connectionState == .testing)
            }
        }
    }

    private func labeledField<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(MainWindowPalette.secondaryText)
            content()
        }
    }

    private var apiKeyPlaceholder: String {
        if modelSettings.hasAPIKey { return "Saved" }
        return "Required"
    }

    private func permissionRow(
        title: String,
        detail: String,
        state: ComputerUsePermissionState,
        request: @escaping () async -> Void,
        openSettings: @escaping () -> Void
    ) -> some View {
        settingsRow(
            title: title,
            detail: detail,
            isReady: state == .granted,
            buttonTitle: state == .granted ? nil : "Grant Access",
            secondaryButtonTitle: state == .granted ? nil : "Open Settings",
            secondaryAction: openSettings,
            action: {
                Task { await request() }
            }
        )
    }

    private func settingsRow(
        title: String,
        detail: String,
        isReady: Bool,
        buttonTitle: String?,
        secondaryButtonTitle: String? = nil,
        secondaryAction: @escaping () -> Void = {},
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: isReady ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isReady ? Color.green : MainWindowPalette.tertiaryText)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AppTypography.bodyMedium)
                Text(detail)
                    .font(AppTypography.caption)
                    .foregroundStyle(MainWindowPalette.secondaryText)
            }
            Spacer(minLength: 12)
            if let secondaryButtonTitle {
                Button(secondaryButtonTitle, action: secondaryAction)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(coordinator.isBusy)
            }
            if let buttonTitle {
                Button(buttonTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(coordinator.isBusy)
            }
        }
    }
}
