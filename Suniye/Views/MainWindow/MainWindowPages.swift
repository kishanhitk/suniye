import Carbon
import SwiftUI

struct DashboardPage: View {
    @Bindable var appState: AppState
    let onNavigate: (MainWindowSection) -> Void

    var body: some View {
        DetailScrollContainer {
            DetailPageTitle(title: "Dashboard")

            if !appState.attentionItems.isEmpty {
                VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
                    ForEach(appState.attentionItems) { item in
                        AttentionTile(item: item) {
                            onNavigate(item.recommendedSection)
                        } onFixAction: { action in
                            appState.handleAttentionFixAction(action)
                        }
                    }
                }
            }

            if appState.updateStatus == .downloaded {
                SurfaceCard {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Update ready to install")
                                .font(AppTypography.bodyMedium)
                            Text(appState.updateStatusText)
                                .font(AppTypography.subheadline)
                                .foregroundStyle(MainWindowPalette.secondaryText)
                        }

                        Spacer(minLength: 12)

                        Button("Install Update") {
                            Task {
                                await appState.downloadAndOpenUpdate()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                DashboardMetricCard(icon: "waveform", iconTint: .blue, value: "\(appState.sessionCount)", label: "Sessions")
                DashboardMetricCard(icon: "calendar", iconTint: .orange, value: "\(appState.todaySessionCount)", label: "Today")
                DashboardMetricCard(icon: "quote.opening", iconTint: .purple, value: appState.wordsTranscribed.abbreviatedString, label: "Words")
                DashboardMetricCard(icon: "clock", iconTint: .green, value: appState.totalDictationSeconds.compactDurationString, label: "Time")
            }

            VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
                SectionHeading(title: "Recent")

                if appState.recentResultsPreview.isEmpty {
                    SurfaceCard {
                        Text("No transcription sessions yet.")
                            .font(AppTypography.body)
                            .foregroundStyle(MainWindowPalette.secondaryText)
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(appState.recentResultsPreview) { result in
                            TranscriptSummaryRow(result: result)
                        }
                    }
                }
            }
        }
    }
}

struct HistoryPage: View {
    @Bindable var appState: AppState

    var body: some View {
        DetailScrollContainer {
            DetailPageTitle(title: "History")

            if appState.recentResults.isEmpty {
                EmptyStateCard(
                    icon: "clock.arrow.circlepath",
                    title: "No History Yet",
                    detail: "Completed dictation sessions will appear here with relative time, duration, copy, and delete actions."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(appState.recentResults) { result in
                        TranscriptHistoryRow(
                            result: result,
                            onCopy: { appState.copyRecentResult(result) },
                            onDelete: { appState.deleteRecentResult(result) }
                        )
                    }
                }
            }
        }
    }
}

struct ModelPage: View {
    @Bindable var appState: AppState

    var body: some View {
        DetailScrollContainer {
            SectionHeading(title: "ASR Model")

            SurfaceCard {
                VStack(spacing: 12) {
                    InfoRow(title: "Name", value: "Parakeet TDT 0.6B v3")
                    CardDivider()
                    InfoRow(title: "Quantization", value: "INT8 (CPU-optimized)")
                    CardDivider()
                    InfoRow(title: "Disk size", value: appState.modelExpectedSizeText)
                    CardDivider()
                    InfoRow(
                        title: "Status",
                        value: appState.modelStatusValue,
                        valueColor: appState.modelStatusColor,
                        trailingIcon: appState.modelStatusIcon,
                        trailingIconColor: appState.modelStatusColor
                    )
                    CardDivider()
                    InfoRow(title: "On disk", value: appState.modelInstalledSizeText)
                }
            }

            SurfaceCard {
                VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(appState.isModelInstalled ? "Model Installed" : "Offline Model Required")
                                .font(AppTypography.bodyMedium)

                            if appState.isModelInstalled {
                                Text(appState.modelLocationText)
                                    .font(AppTypography.caption)
                                    .foregroundStyle(MainWindowPalette.secondaryText)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                Text(appState.modelPrimaryActionDetail)
                                    .font(AppTypography.subheadline)
                                    .foregroundStyle(MainWindowPalette.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        Spacer(minLength: 12)

                        if appState.isModelInstalled {
                            HStack(spacing: 12) {
                                ActionIconButton(systemName: "folder", tint: MainWindowPalette.secondaryText) {
                                    appState.openModelFolder()
                                }
                                ActionIconButton(systemName: "trash", tint: MainWindowPalette.destructive) {
                                    appState.deleteModel()
                                }
                                .disabled(appState.phase == .downloadingModel)
                            }
                        } else {
                            Button(appState.modelPrimaryActionTitle) {
                                appState.startModelDownload()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(appState.phase == .downloadingModel)
                        }
                    }

                    if appState.isModelOperationInProgress {
                        CardDivider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text(appState.modelOperationStatusText)
                                .font(AppTypography.subheadlineSemibold)

                            if appState.phase == .downloadingModel {
                                ProgressView(value: appState.downloadProgress)
                                    .progressViewStyle(.linear)
                                Text(appState.modelDownloadProgressLabel)
                                    .font(AppTypography.caption)
                                    .foregroundStyle(MainWindowPalette.secondaryText)
                            } else {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Download complete. Finishing local setup before the model becomes available.")
                                    .font(AppTypography.caption)
                                    .foregroundStyle(MainWindowPalette.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    if appState.phase == .loading, appState.isModelInstalled {
                        CardDivider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Loading model…")
                                .font(AppTypography.subheadlineSemibold)

                            ProgressView()
                                .controlSize(.small)
                            Text("Preparing the local recognizer.")
                                .font(AppTypography.caption)
                                .foregroundStyle(MainWindowPalette.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if let error = appState.lastError, appState.phase == .error {
                        CardDivider()

                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(AppTypography.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

struct StylePage: View {
    @Bindable var appState: AppState
    @State private var vocabularyDraft = ""
    @State private var apiKeyDraft = ""

    var body: some View {
        DetailScrollContainer {
            VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
                DetailPageTitle(title: "Magic Format")

                featureToggleCard
            }

            if appState.llmEnabled {
                connectionSection
                modelSection
                vocabularySection
                promptSection
            }
        }
    }

    // MARK: - Feature Toggle

    private var featureToggleCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.purple)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Improve text before pasting")
                            .font(AppTypography.bodyMedium)
                        Text("Fix grammar, wording, and names after dictation.")
                            .font(AppTypography.caption)
                            .foregroundStyle(MainWindowPalette.secondaryText)
                    }

                    Spacer(minLength: 12)

                    Toggle("", isOn: $appState.llmEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .accessibilityLabel("Improve text before pasting")
                }

                if appState.llmEnabled {
                    CardDivider()

                    HStack(spacing: 6) {
                        Circle()
                            .fill(setupStatusColor)
                            .frame(width: 7, height: 7)
                        Text(setupStatusText)
                            .font(AppTypography.caption)
                            .foregroundStyle(MainWindowPalette.secondaryText)
                    }
                }
            }
        }
    }

    // MARK: - Connection

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
            SectionHeading(title: "Connection")

            SurfaceCard {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Endpoint")
                            .font(AppTypography.subheadlineSemibold)
                        Text("Any OpenAI-compatible API.")
                            .font(AppTypography.caption)
                            .foregroundStyle(MainWindowPalette.secondaryText)

                        TextField("https://api.openai.com/v1/chat/completions", text: $appState.llmEndpointURLString)
                            .textFieldStyle(.roundedBorder)
                            .font(AppTypography.codeBodyMedium)

                        if let error = appState.llmEndpointValidationError {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(AppTypography.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    CardDivider()

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("API Key")
                                .font(AppTypography.subheadlineSemibold)
                            Spacer(minLength: 12)
                            StylePageStatusPill(
                                text: appState.llmKeyStatusText,
                                isPositive: appState.isMagicFormatSetupVerified
                            )
                        }

                        HStack(spacing: 8) {
                            SecureField("Paste API key", text: $apiKeyDraft)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: apiKeyDraft) { _, _ in
                                    appState.clearMagicFormatSetupTestResult()
                                }

                            Button(appState.hasLLMAPIKey ? "Replace" : "Save") {
                                appState.saveLLMAPIKey(apiKeyDraft)
                                apiKeyDraft = ""
                            }
                            .buttonStyle(.bordered)
                            .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            Button("Clear") {
                                appState.clearLLMAPIKey()
                                apiKeyDraft = ""
                            }
                            .buttonStyle(.bordered)
                            .disabled(!appState.hasLLMAPIKey)
                        }

                        if let error = appState.llmKeyOperationError {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(AppTypography.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    CardDivider()

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Button(appState.isMagicFormatSetupTestInProgress ? "Testing\u{2026}" : "Test Connection") {
                                Task {
                                    await appState.testMagicFormatSetup(apiKeyDraft: apiKeyDraft)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!appState.canTestMagicFormatSetup(apiKeyDraft: apiKeyDraft))

                            if appState.isMagicFormatSetupTestInProgress {
                                ProgressView()
                                    .controlSize(.small)
                            }

                            Spacer()

                            if let result = appState.magicFormatSetupTestResult {
                                Label(result.message, systemImage: result.severity == .success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .font(AppTypography.caption)
                                    .foregroundStyle(result.severity.color)
                            }
                        }

                        Text("Works with unsaved keys too.")
                            .font(AppTypography.caption)
                            .foregroundStyle(MainWindowPalette.tertiaryText)
                    }
                }
            }
        }
    }

    // MARK: - Model

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
            SectionHeading(title: "Model")

            SurfaceCard {
                VStack(alignment: .leading, spacing: 8) {
                    NativePopupPicker(
                        items: modelPickerPresets,
                        selection: $appState.llmSelectedModelPreset,
                        title: modelPickerTitle(for:)
                    )
                    .frame(maxWidth: 320)

                    Text(modelPickerDescription(for: appState.llmSelectedModelPreset))
                        .font(AppTypography.caption)
                        .foregroundStyle(MainWindowPalette.secondaryText)

                    if appState.llmSelectedModelPreset == .custom {
                        CardDivider()
                            .padding(.vertical, 2)

                        TextField("gpt-4.1-mini or provider/model-id", text: $appState.llmCustomModelId)
                            .textFieldStyle(.roundedBorder)
                            .font(AppTypography.codeBodyMedium)

                        if let error = appState.llmModelValidationError {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(AppTypography.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Vocabulary

    private var vocabularySection: some View {
        VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
            SectionHeading(title: "Vocabulary")

            SurfaceCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Words the model should never change.")
                        .font(AppTypography.caption)
                        .foregroundStyle(MainWindowPalette.secondaryText)

                    if !appState.vocabularyTerms.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(appState.vocabularyTerms, id: \.self) { term in
                                StylePageVocabularyTag(term: term) {
                                    appState.removeVocabularyTerm(term)
                                }
                            }
                        }

                        CardDivider()
                    }

                    HStack(spacing: 8) {
                        TextField("e.g. Suniye, PostgreSQL, gRPC", text: $vocabularyDraft)
                            .textFieldStyle(.roundedBorder)
                            .font(AppTypography.body)
                            .onSubmit(addTerm)

                        Button("Add", action: addTerm)
                            .buttonStyle(.bordered)
                            .disabled(vocabularyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    // MARK: - Prompt

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
            SectionHeading(title: "Prompt")

            SurfaceCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Instructions for rewriting your text.")
                        .font(AppTypography.caption)
                        .foregroundStyle(MainWindowPalette.secondaryText)

                    TextEditor(text: $appState.llmBaseSystemPrompt)
                        .font(AppTypography.body)
                        .frame(minHeight: 120)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(MainWindowPalette.editorBackground)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(MainWindowPalette.cardStroke, lineWidth: 1)
                        )
                }
            }
        }
    }

    // MARK: - Helpers

    private func addTerm() {
        appState.addVocabularyTerm(vocabularyDraft)
        vocabularyDraft = ""
    }

    private var modelPickerPresets: [LLMModelPreset] {
        [.gpt41Mini, .gemini25Flash, .custom]
    }

    private func modelPickerTitle(for preset: LLMModelPreset) -> String {
        switch preset {
        case .custom:
            return "Custom model"
        case .gemini25Flash, .gpt41Mini:
            return preset.displayName
        }
    }

    private func modelPickerDescription(for preset: LLMModelPreset) -> String {
        switch preset {
        case .custom:
            return "Use the exact model ID supported by your endpoint."
        case .gemini25Flash:
            return "Fast and cheap. Quick text cleanup."
        case .gpt41Mini:
            return "Balanced quality and speed. Good default."
        }
    }

    private var setupStatusColor: Color {
        switch appState.magicFormatSetupState {
        case .off:
            return .gray
        case .needsAPIKey, .needsServiceSetup:
            return .orange
        case .ready:
            return appState.isMagicFormatSetupVerified ? .green : .blue
        }
    }

    private var setupStatusText: String {
        if appState.isMagicFormatSetupVerified {
            return "Connected and ready"
        }
        switch appState.magicFormatSetupState {
        case .off:
            return "Off"
        case .needsAPIKey:
            return "Add an API key to get started"
        case .needsServiceSetup:
            return "Check the connection settings below"
        case .ready:
            return "Run a connection test to verify"
        }
    }
}

private struct StylePageStatusPill: View {
    let text: String
    let isPositive: Bool

    var body: some View {
        Text(text)
            .font(AppTypography.caption)
            .foregroundStyle(isPositive ? .green : MainWindowPalette.secondaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(isPositive ? Color.green.opacity(0.1) : MainWindowPalette.selectedFill)
            )
    }
}

private struct StylePageVocabularyTag: View {
    let term: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(term)
                .font(AppTypography.callout)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(MainWindowPalette.secondaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(MainWindowPalette.selectedFill)
        )
        .overlay(
            Capsule()
                .stroke(MainWindowPalette.cardStroke, lineWidth: 0.5)
        )
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
                                        appState.requestAccessibilityPermission()
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

                        SettingsToggleRow(
                            title: "Echo Cancellation",
                            detail: "Filters out system audio (music, video, TTS) from the microphone during dictation. Uses Apple's Voice Processing. Leave off to preserve full-quality Bluetooth headphone playback.",
                            isOn: $appState.echoCancellationEnabled
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
                SectionHeading(title: "Hotkey")

                SurfaceCard {
                    VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
                        HStack(spacing: 12) {
                            Text("Hold to Dictate")
                                .font(AppTypography.body)
                            Spacer(minLength: 12)
                            HotkeyRecorderButton(configuration: $appState.hotkeyConfiguration)
                        }
                        CardDivider()
                        Text("Works from any app. Hold the shortcut to record, release to transcribe.")
                            .font(AppTypography.subheadline)
                            .foregroundStyle(MainWindowPalette.secondaryText)
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
                SectionHeading(title: "About")

                SurfaceCard {
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Text("Suniye")
                                .font(AppTypography.bodyMedium)
                            Spacer(minLength: 0)
                            Text(appState.appVersionText)
                                .font(AppTypography.codeBodyMedium)
                                .foregroundStyle(MainWindowPalette.secondaryText)
                        }

                        CardDivider()

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(appState.updateStatusText)
                                    .font(AppTypography.subheadline)
                                    .foregroundStyle(appState.updateStatus == .error ? .red : MainWindowPalette.secondaryText)

                                if appState.updateStatus == .downloading {
                                    ProgressView(value: appState.updateDownloadProgress)
                                        .progressViewStyle(.linear)
                                }
                            }

                            Spacer(minLength: 12)

                            if appState.updateStatus == .available || appState.updateStatus == .downloaded {
                                HStack(spacing: 8) {
                                    Button("Release Notes") {
                                        appState.openReleaseNotes()
                                    }
                                    .buttonStyle(.bordered)

                                    Button(appState.updateStatus == .downloaded ? "Install" : "Download") {
                                        Task {
                                            await appState.downloadAndOpenUpdate()
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            } else {
                                Button(appState.updateStatus == .checking ? "Checking..." : "Check for Updates") {
                                    Task {
                                        await appState.checkForUpdates(background: false)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(appState.updateStatus == .checking || appState.updateStatus == .downloading)
                            }
                        }
                    }
                }
            }
        }
    }

    private var inputDeviceChoices: [InputDeviceChoice] {
        let devices = appState.availableInputDevices.map {
            InputDeviceChoice(
                id: $0.id,
                title: $0.isDefault ? "\($0.name) (Default)" : $0.name
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
    @Binding var configuration: HotkeyConfiguration
    @State private var isCapturing = false
    @State private var localMonitor: Any?

    var body: some View {
        Button {
            toggleCapture()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isCapturing ? "record.circle" : "globe")
                    .font(.headline.weight(.medium))
                Text(isCapturing ? "Press shortcut" : configuration.displayString)
                    .font(AppTypography.codeBodyMedium)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(MainWindowPalette.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isCapturing ? Color.accentColor.opacity(0.5) : MainWindowPalette.cardStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onDisappear {
            stopCapturing()
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
