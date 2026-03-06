import AppKit
import SwiftUI

enum SettingsSection: String, CaseIterable, Hashable {
    case general
    case system
    case vibeCoding

    var title: String {
        switch self {
        case .general:
            return "General"
        case .system:
            return "System"
        case .vibeCoding:
            return "Vibe coding"
        }
    }

    var icon: String {
        switch self {
        case .general:
            return "slider.horizontal.3"
        case .system:
            return "desktopcomputer"
        case .vibeCoding:
            return "number"
        }
    }
}

struct SettingsPageView: View {
    @Bindable var appState: AppState
    @State private var section: SettingsSection = .general

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("SETTINGS")
                    .font(AppTypography.ui(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .padding(.bottom, 8)

                ForEach(SettingsSection.allCases, id: \.self) { item in
                    Button {
                        section = item
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.icon)
                                .font(.system(size: 14, weight: .semibold))
                            Text(item.title)
                                .font(AppTypography.ui(size: 19, weight: .medium))
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: AppLayout.chipCornerRadius, style: .continuous)
                                .fill(section == item ? AppTheme.subtleBackground : Color.clear)
                        )
                        .foregroundStyle(section == item ? AppTheme.primaryText : AppTheme.secondaryText)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .frame(width: 220, alignment: .topLeading)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(section.title)
                        .font(AppTypography.serif(size: 52))
                        .foregroundStyle(AppTheme.primaryText)

                    switch section {
                    case .general:
                        SettingsGeneralSection(appState: appState)
                    case .system:
                        SettingsSystemSection(appState: appState)
                    case .vibeCoding:
                        SettingsVibeCodingSection(appState: appState)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 6)
                .padding(.bottom, 24)
            }
        }
        .padding(26)
        .frame(maxWidth: 1020, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct SettingsGeneralSection: View {
    @Bindable var appState: AppState
    @State private var isCapturing = false
    @State private var captureStatusText = ""
    @State private var localMonitor: Any?
    @State private var modifierOnlyCandidate: HotkeyShortcut?

    var body: some View {
        AppShellCard {
            VStack(alignment: .leading, spacing: 0) {
                SettingsRow(
                    title: "Keybind shortcuts",
                    subtitle: "Hold \(appState.hotkeyShortcut.displayText) and speak."
                ) {
                    HStack(spacing: 8) {
                        Button(isCapturing ? "Recording..." : "Change") {
                            if isCapturing {
                                stopCapture(cancelled: true)
                            } else {
                                beginCapture()
                            }
                        }
                        .buttonStyle(SoftPillButtonStyle())

                        Button("Reset") {
                            appState.updateHotkeyShortcut(.defaultHoldToTalk)
                            captureStatusText = "Reset to Fn"
                        }
                        .buttonStyle(SoftPillButtonStyle())
                    }
                }

                Divider().overlay(AppTheme.border)

                SettingsRow(title: "Microphone", subtitle: selectedDeviceLabel) {
                    HStack(spacing: 8) {
                        Picker("Input Device", selection: Binding<String?>(
                            get: { appState.selectedInputDeviceUID },
                            set: { appState.selectInputDevice(uid: $0) }
                        )) {
                            ForEach(appState.availableInputDevices) { device in
                                Text(device.isDefault ? "\(device.name) (Default)" : device.name)
                                    .tag(Optional(device.uid))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .tint(AppTheme.primaryText)
                        .foregroundStyle(AppTheme.primaryText)
                        .frame(width: 270)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: AppLayout.chipCornerRadius, style: .continuous)
                                .fill(AppTheme.panelBackground)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AppLayout.chipCornerRadius, style: .continuous)
                                .stroke(AppTheme.border, lineWidth: 1)
                        )

                        Button("Refresh") {
                            appState.refreshAudioDevices()
                        }
                        .buttonStyle(SoftPillButtonStyle())
                    }
                }

                Divider().overlay(AppTheme.border)

                SettingsRow(title: "Launch at login", subtitle: appState.launchAtLoginEnabled ? "Enabled" : "Disabled") {
                    Toggle("", isOn: Binding(
                        get: { appState.launchAtLoginEnabled },
                        set: { appState.setLaunchAtLoginEnabled($0) }
                    ))
                    .labelsHidden()
                }

                Divider().overlay(AppTheme.border)

                SettingsRow(
                    title: "Permissions",
                    subtitle: "Mic: \(appState.hasMicPermission ? "Granted" : "Missing") • Accessibility: \(appState.hasAccessibilityPermission ? "Granted" : "Missing")"
                ) {
                    HStack(spacing: 8) {
                        Button("Mic") {
                            Task {
                                await appState.refreshPermissions(requestMicrophone: true)
                            }
                        }
                        .buttonStyle(SoftPillButtonStyle())

                        Button("Accessibility") {
                            appState.requestAccessibilityPermission()
                        }
                        .buttonStyle(SoftPillButtonStyle())
                    }
                }

                if !captureStatusText.isEmpty {
                    Divider().overlay(AppTheme.border)
                    Text(captureStatusText)
                        .font(AppTypography.ui(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryText)
                        .padding(.top, 12)
                }

                if let hotkeyValidationError = appState.hotkeyValidationError {
                    Text(hotkeyValidationError)
                        .font(AppTypography.ui(size: 13, weight: .semibold))
                        .foregroundStyle(.red)
                }

                if let inputDeviceStatusMessage = appState.inputDeviceStatusMessage {
                    Text(inputDeviceStatusMessage)
                        .font(AppTypography.ui(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryText)
                }

                if let launchAtLoginError = appState.launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(AppTypography.ui(size: 13, weight: .semibold))
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
        }
        .onDisappear {
            stopCapture(cancelled: true)
        }
    }

    private var selectedDeviceLabel: String {
        if let selectedUID = appState.selectedInputDeviceUID,
           let device = appState.availableInputDevices.first(where: { $0.uid == selectedUID }) {
            return device.name
        }
        return "Default"
    }

    private func beginCapture() {
        stopCapture(cancelled: true)
        isCapturing = true
        modifierOnlyCandidate = nil
        captureStatusText = "Waiting for shortcut..."

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            guard isCapturing else {
                return event
            }

            switch event.type {
            case .keyDown:
                if event.keyCode == 53 {
                    stopCapture(cancelled: true)
                    return nil
                }

                let modifiers = HotkeyShortcut.Modifiers.from(event.modifierFlags)
                let shortcut = HotkeyShortcut(
                    keyCode: HotkeyShortcut.isModifierKeyCode(event.keyCode) ? nil : event.keyCode,
                    modifiers: modifiers
                )

                if shortcut.isEmpty {
                    return nil
                }

                appState.updateHotkeyShortcut(shortcut)
                captureStatusText = "Saved: \(shortcut.displayText)"
                stopCapture(cancelled: false)
                return nil

            case .flagsChanged:
                let modifiers = HotkeyShortcut.Modifiers.from(event.modifierFlags)

                if modifiers.isEmpty {
                    if let modifierOnlyCandidate {
                        appState.updateHotkeyShortcut(modifierOnlyCandidate)
                        captureStatusText = "Saved: \(modifierOnlyCandidate.displayText)"
                        stopCapture(cancelled: false)
                    }
                    return nil
                }

                modifierOnlyCandidate = HotkeyShortcut(keyCode: nil, modifiers: modifiers)
                return nil

            default:
                return event
            }
        }
    }

    private func stopCapture(cancelled: Bool) {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if cancelled, isCapturing {
            captureStatusText = "Shortcut recording cancelled"
        }
        modifierOnlyCandidate = nil
        isCapturing = false
    }
}

private struct SettingsSystemSection: View {
    @Bindable var appState: AppState

    var body: some View {
        AppShellCard {
            VStack(alignment: .leading, spacing: 0) {
                SettingsRow(
                    title: "Model",
                    subtitle: appState.isModelInstalled ? "Installed" : "Missing"
                ) {
                    HStack(spacing: 8) {
                        Button(appState.isModelInstalled ? "Re-download" : "Download") {
                            appState.startModelDownload()
                        }
                        .buttonStyle(SoftPillButtonStyle())
                        .disabled(appState.phase == .downloadingModel || appState.phase == .recording || appState.phase == .transcribing)

                        Button("Open folder") {
                            appState.openModelFolder()
                        }
                        .buttonStyle(SoftPillButtonStyle())
                        .disabled(!appState.isModelInstalled)

                        Button("Rescan") {
                            appState.refreshModelDiagnostics()
                        }
                        .buttonStyle(SoftPillButtonStyle())
                    }
                }

                if appState.phase == .downloadingModel {
                    ProgressView(value: appState.downloadProgress)
                        .padding(.bottom, 16)
                }

                Divider().overlay(AppTheme.border)

                SettingsRow(title: "Logs", subtitle: "Open local app logs") {
                    Button("Open logs") {
                        NSWorkspace.shared.open(AppLogger.shared.logFileURL.deletingLastPathComponent())
                    }
                    .buttonStyle(SoftPillButtonStyle())
                }

                if let diagnostics = appState.modelDiagnostics {
                    Divider().overlay(AppTheme.border)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Required files")
                            .font(AppTypography.ui(size: 16, weight: .semibold))
                            .foregroundStyle(AppTheme.primaryText)

                        ForEach(diagnostics.requiredFiles) { file in
                            HStack {
                                Image(systemName: file.exists ? "checkmark.circle.fill" : "xmark.circle")
                                    .foregroundStyle(file.exists ? Color(red: 0.24, green: 0.39, blue: 0.30) : Color(red: 0.56, green: 0.19, blue: 0.20))
                                Text(file.fileName)
                                    .font(AppTypography.ui(size: 14))
                                Spacer()
                                Text(formatByteCount(file.sizeBytes))
                                    .font(AppTypography.mono(size: 12))
                                    .foregroundStyle(AppTheme.secondaryText)
                            }
                        }

                        Text("Disk usage: \(formatByteCount(diagnostics.diskUsageBytes))")
                            .font(AppTypography.ui(size: 13, weight: .medium))
                            .foregroundStyle(AppTheme.secondaryText)
                        Text(diagnostics.modelDirectoryPath)
                            .font(AppTypography.mono(size: 11))
                            .foregroundStyle(AppTheme.secondaryText)
                            .textSelection(.enabled)
                    }
                    .padding(.top, 14)
                    .padding(.bottom, 18)
                }

                if let diagnosticsError = appState.modelDiagnosticsError {
                    Text(diagnosticsError)
                        .font(AppTypography.ui(size: 13, weight: .semibold))
                        .foregroundStyle(.red)
                        .padding(.top, 12)
                }

                if let lastError = appState.lastError, appState.phase == .error {
                    Text(lastError)
                        .font(AppTypography.ui(size: 13, weight: .semibold))
                        .foregroundStyle(.red)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
        }
    }
}

private struct SettingsVibeCodingSection: View {
    @Bindable var appState: AppState
    @State private var pendingAPIKey = ""
    @State private var pendingBaseSystemPrompt = ""
    @State private var pendingUserSystemPrompt = ""
    @State private var pendingKeywordsRaw = ""

    var body: some View {
        AppShellCard {
            VStack(alignment: .leading, spacing: 10) {
                SettingsRow(title: "Enable vibe coding", subtitle: "Post-process transcription with LLM") {
                    Toggle("", isOn: $appState.llmEnabled)
                        .labelsHidden()
                }

                Divider().overlay(AppTheme.border)

                SettingsRow(title: "Model", subtitle: appState.llmSelectedModelIdPreview) {
                    Picker("Model", selection: $appState.llmSelectedModelPreset) {
                        ForEach(LLMModelPreset.allCases, id: \.self) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(AppTheme.primaryText)
                    .foregroundStyle(AppTheme.primaryText)
                    .frame(width: 250)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: AppLayout.chipCornerRadius, style: .continuous)
                            .fill(AppTheme.panelBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppLayout.chipCornerRadius, style: .continuous)
                            .stroke(AppTheme.border, lineWidth: 1)
                    )
                }

                if appState.llmSelectedModelPreset == .custom {
                    TextField("openrouter/model-id", text: $appState.llmCustomModelId)
                        .font(AppTypography.ui(size: 14))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: AppLayout.chipCornerRadius, style: .continuous)
                                .fill(AppTheme.panelBackground)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AppLayout.chipCornerRadius, style: .continuous)
                                .stroke(AppTheme.border, lineWidth: 1)
                        )
                        .padding(.bottom, 8)
                }

                Divider().overlay(AppTheme.border)

                SettingsRow(title: "API key", subtitle: appState.llmKeyStatusText) {
                    HStack(spacing: 8) {
                        SecureField("OpenRouter API key", text: $pendingAPIKey)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: AppLayout.chipCornerRadius, style: .continuous)
                                    .fill(AppTheme.panelBackground)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: AppLayout.chipCornerRadius, style: .continuous)
                                    .stroke(AppTheme.border, lineWidth: 1)
                            )
                            .frame(width: 260)
                        Button(appState.hasOpenRouterAPIKey ? "Replace" : "Save") {
                            appState.saveOpenRouterAPIKey(pendingAPIKey)
                            pendingAPIKey = ""
                        }
                        .buttonStyle(SoftPillButtonStyle())
                        Button("Clear") {
                            appState.clearOpenRouterAPIKey()
                            pendingAPIKey = ""
                        }
                        .buttonStyle(SoftPillButtonStyle())
                        .disabled(!appState.hasOpenRouterAPIKey)
                    }
                }

                Divider().overlay(AppTheme.border)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Base prompt")
                        .font(AppTypography.ui(size: 16, weight: .semibold))
                    TextEditor(text: $pendingBaseSystemPrompt)
                        .font(AppTypography.ui(size: 14))
                        .frame(minHeight: 86)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(AppTheme.panelBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppLayout.chipCornerRadius, style: .continuous)
                                .stroke(AppTheme.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: AppLayout.chipCornerRadius, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("User prompt")
                        .font(AppTypography.ui(size: 16, weight: .semibold))
                    TextEditor(text: $pendingUserSystemPrompt)
                        .font(AppTypography.ui(size: 14))
                        .frame(minHeight: 86)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(AppTheme.panelBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppLayout.chipCornerRadius, style: .continuous)
                                .stroke(AppTheme.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: AppLayout.chipCornerRadius, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Keywords")
                        .font(AppTypography.ui(size: 16, weight: .semibold))
                    TextEditor(text: $pendingKeywordsRaw)
                        .font(AppTypography.ui(size: 14))
                        .frame(minHeight: 84)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(AppTheme.panelBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppLayout.chipCornerRadius, style: .continuous)
                                .stroke(AppTheme.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: AppLayout.chipCornerRadius, style: .continuous))
                }

                HStack(spacing: 8) {
                    Button("Save") {
                        appState.llmBaseSystemPrompt = pendingBaseSystemPrompt
                        appState.llmSystemPrompt = pendingUserSystemPrompt
                        appState.llmKeywordsRaw = pendingKeywordsRaw
                        AppLogger.shared.log(.info, "llm prompt layers saved")
                    }
                    .buttonStyle(SoftPillButtonStyle())
                    .disabled(!hasUnsavedLLMTextChanges)

                    Button("Reset base") {
                        pendingBaseSystemPrompt = LLMDefaults.defaultBaseSystemPrompt
                    }
                    .buttonStyle(SoftPillButtonStyle())
                    .disabled(pendingBaseSystemPrompt == LLMDefaults.defaultBaseSystemPrompt)
                }

                if let llmKeyOperationError = appState.llmKeyOperationError {
                    Text(llmKeyOperationError)
                        .font(AppTypography.ui(size: 13, weight: .semibold))
                        .foregroundStyle(.red)
                }
            }
            .padding(18)
        }
        .onAppear {
            pendingBaseSystemPrompt = appState.llmBaseSystemPrompt
            pendingUserSystemPrompt = appState.llmSystemPrompt
            pendingKeywordsRaw = appState.llmKeywordsRaw
        }
    }

    private var hasUnsavedLLMTextChanges: Bool {
        pendingBaseSystemPrompt != appState.llmBaseSystemPrompt ||
            pendingUserSystemPrompt != appState.llmSystemPrompt ||
            pendingKeywordsRaw != appState.llmKeywordsRaw
    }
}
