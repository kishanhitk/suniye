import AppKit
import SwiftUI

/// Engine chooser. Selecting a row does not switch the formatter — the button
/// does, and it names which engine it will use, so backing out is free. Per-row
/// actions (Set up, Delete) act on that engine, not on the choice.
struct EngineSheet: View {
    @Bindable var appState: AppState

    @Environment(\.dismiss) private var dismiss
    @State private var selection: MagicFormatProvider?
    @State private var showsAPISetup = false

    private var presenter: MagicFormatProviderPresenter {
        MagicFormatProviderPresenter(appState: appState)
    }

    private var pending: MagicFormatProvider {
        selection ?? presenter.displayedProviderSelection
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Engine")
                    .font(AppTypography.cardTitle)
                Text("What rewrites your dictation. Audio never leaves this Mac either way.")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(MainWindowPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                ForEach(Array(presenter.providerOptions.enumerated()), id: \.element) { index, provider in
                    engineRow(provider)
                    if index < presenter.providerOptions.count - 1 {
                        RowSeparator()
                    }
                }
            }

            HStack(spacing: 10) {
                if let result = appState.magicFormatSetupTestResult {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(result.severity.color)
                            .frame(width: 7, height: 7)
                        Text(result.latencyText ?? result.message)
                            .font(AppTypography.subheadline)
                            .foregroundStyle(MainWindowPalette.secondaryText)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 12)

                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)

                Button("Use this engine") {
                    appState.llmProvider = pending
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!presenter.isSelectable(pending))
            }
        }
        .padding(20)
        .frame(width: 560)
        .subtleScrollers()
        .background(MainWindowPalette.windowBackground)
        .sheet(isPresented: $showsAPISetup) {
            APIEndpointSheet(appState: appState)
        }
    }

    private func engineRow(_ provider: MagicFormatProvider) -> some View {
        let isEnabled = presenter.isSelectable(provider)

        return HStack(alignment: .top, spacing: 12) {
            StylePageRadioIndicator(isSelected: pending == provider, isEnabled: isEnabled)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 3) {
                Text(name(for: provider))
                    .font(AppTypography.rowTitle)
                    .foregroundStyle(Color.primary)
                // The two facts you would weigh: what it costs you, and what it
                // costs in quality.
                Text(facts(for: provider))
                    .font(AppTypography.subheadline)
                    .foregroundStyle(MainWindowPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            rowActions(provider)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            guard isEnabled else { return }
            selection = provider
        }
        .opacity(isEnabled ? 1 : 0.55)
    }

    @ViewBuilder
    private func rowActions(_ provider: MagicFormatProvider) -> some View {
        switch provider {
        case .localGemma:
            switch appState.localGemmaInstallState {
            case .notInstalled, .failed:
                Button("Download") { appState.startLocalGemmaDownload() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!appState.canStartLocalGemmaDownload)
            case .downloading:
                Button("Cancel") { appState.cancelLocalGemmaDownload() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            case .verifying:
                ProgressView().controlSize(.small)
            case .installed:
                HStack(spacing: 8) {
                    Button(isTesting(.localGemma) ? "Testing\u{2026}" : "Test") {
                        Task { await appState.testLocalGemmaSetup() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(appState.isMagicFormatSetupTestInProgress)

                    Button("Delete") {
                        Task { await appState.deleteLocalGemmaModel() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundStyle(MainWindowPalette.destructive)
                    .disabled(!appState.canDeleteLocalGemmaModel)
                }
            case .unavailable:
                EmptyView()
            }

        case .openAICompatible:
            Button("Set up") { showsAPISetup = true }
                .buttonStyle(.bordered)
                .controlSize(.small)

        case .appleFoundationModels:
            if appState.appleMagicFormatAvailability.isAvailable {
                Button(isTesting(.appleFoundationModels) ? "Testing\u{2026}" : "Test") {
                    Task { await appState.testAppleMagicFormatSetup() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(appState.isMagicFormatSetupTestInProgress)
            } else if appState.appleMagicFormatAvailability == .appleIntelligenceNotEnabled {
                Button("Open Settings") { appState.openAppleIntelligenceSettings() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

        case .automatic:
            EmptyView()
        }
    }

    private func isTesting(_ provider: MagicFormatProvider) -> Bool {
        appState.magicFormatTestingProvider == provider
    }

    private func name(for provider: MagicFormatProvider) -> String {
        switch provider {
        case .localGemma:
            return "Local model"
        case .appleFoundationModels:
            return "Apple Intelligence"
        case .openAICompatible:
            return "Your own API endpoint"
        case .automatic:
            return "Automatic"
        }
    }

    /// Deliberately no latency figures: they are not measured, and an invented
    /// number is worse than none.
    private func facts(for provider: MagicFormatProvider) -> String {
        switch provider {
        case .localGemma:
            switch appState.localGemmaInstallState {
            case .installed:
                return "\(appState.localGemmaModelEntry.displayName) \u{00B7} \(appState.localGemmaModelEntry.expectedSizeText) on disk"
            case .unavailable:
                return "Requires Apple Silicon"
            default:
                return "\(appState.localGemmaModelEntry.displayName) \u{00B7} \(appState.localGemmaModelEntry.expectedSizeText) to download"
            }
        case .appleFoundationModels:
            guard appState.appleMagicFormatAvailability.isAvailable else {
                return appState.appleMagicFormatAvailability.statusText
            }
            return "Nothing to download \u{00B7} less accurate than the local model"
        case .openAICompatible:
            // Generic on purpose: the endpoint is whatever the user points it at,
            // and naming today's host makes the row read like an endorsement.
            return "Transcript text is sent to a service you choose"
        case .automatic:
            return appState.magicFormatProviderDetailText
        }
    }
}

/// One editor for the active engine's prompt. Restore default sits next to the
/// text it would replace, and only appears once something has changed.
struct InstructionsSheet: View {
    @Bindable var appState: AppState

    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Base instructions")
                    .font(AppTypography.cardTitle)
                Text(detail)
                    .font(AppTypography.subheadline)
                    .foregroundStyle(MainWindowPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Stated at the point of editing, not on the page: this is the one
            // setting where the shipped value is measurably better than most
            // edits to it.
            Label(
                "The default is tuned against an eval suite of real dictations. Edits usually make formatting worse \u{2014} change it only if you are testing a specific behaviour.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(AppTypography.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $draft)
                .font(AppTypography.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 300)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(MainWindowPalette.editorBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(MainWindowPalette.cardStroke, lineWidth: 1)
                )

            HStack(spacing: 10) {
                if draft != defaultPrompt {
                    Button("Restore default") { draft = defaultPrompt }
                        .buttonStyle(.bordered)
                }

                Button {
                    appState.openCurrentMagicFormatPromptInEditor()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(.bordered)
                .help("Open in an external editor")
                .accessibilityLabel("Open in an external editor")

                Spacer(minLength: 12)

                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)

                Button("Save") {
                    binding.wrappedValue = draft
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 620)
        .subtleScrollers()
        .background(MainWindowPalette.windowBackground)
        .onAppear {
            guard !loaded else { return }
            draft = binding.wrappedValue
            loaded = true
        }
    }

    private var detail: String {
        if appState.usesAppleMagicFormatSettings {
            return "Sent to Apple Intelligence with every dictation. The default is tested against a suite of real recordings."
        }
        if appState.usesLocalGemmaMagicFormatSettings {
            return "Sent to the local model with every dictation. The default is tested against a suite of real recordings."
        }
        return "Sent to your API endpoint with every dictation. The default is tested against a suite of real recordings."
    }

    private var binding: Binding<String> {
        if appState.usesAppleMagicFormatSettings {
            return $appState.llmAppleSystemPrompt
        }
        if appState.usesLocalGemmaMagicFormatSettings {
            return $appState.llmGemmaSystemPrompt
        }
        return $appState.llmBaseSystemPrompt
    }

    private var defaultPrompt: String {
        if appState.usesAppleMagicFormatSettings {
            return LLMDefaults.defaultAppleMagicFormatPrompt
        }
        if appState.usesLocalGemmaMagicFormatSettings {
            return LLMDefaults.defaultGemmaMagicFormatPrompt
        }
        return LLMDefaults.defaultBaseSystemPrompt
    }
}

/// Just the app names. A real rule is a paragraph — previewing it either
/// truncates to something unreadable or makes every row a different height.
/// Edit expands the row in place rather than stacking a second sheet on this one.
struct PerAppInstructionsSheet: View {
    @Bindable var appState: AppState

    @Environment(\.dismiss) private var dismiss
    @State private var editingID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("App-specific writing style")
                    .font(AppTypography.cardTitle)
                Text("Added to your instructions when you dictate into that app: tone, formatting, anything specific to it.")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(MainWindowPalette.secondaryText)
            }

            if appState.llmAppPromptBindings.isEmpty {
                Text("No apps yet.")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(MainWindowPalette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(appState.llmAppPromptBindings) { binding in
                            bindingRow(binding)
                            if binding.id != appState.llmAppPromptBindings.last?.id {
                                RowSeparator()
                            }
                        }
                    }
                }
                .frame(maxHeight: 340)
            }

            HStack(spacing: 12) {
                addAppMenu
                Spacer(minLength: 12)
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
        .subtleScrollers()
        .background(MainWindowPalette.windowBackground)
    }

    private func bindingRow(_ binding: AppPromptBinding) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                TranscriptAppIcon(bundleID: binding.bundleID, size: 20)

                Text(binding.appDisplayName)
                    .font(AppTypography.rowTitle)

                Spacer(minLength: 12)

                Button(editingID == binding.id ? "Done" : "Edit") {
                    editingID = editingID == binding.id ? nil : binding.id
                }
                .buttonStyle(.link)
                .font(AppTypography.subheadline)

                ActionIconButton(
                    systemName: "trash",
                    accessibilityLabel: "Remove \(binding.appDisplayName)",
                    tint: MainWindowPalette.tertiaryText,
                    hoverTint: MainWindowPalette.destructive
                ) {
                    appState.removeAppPromptBinding(id: binding.id)
                }
            }

            if editingID == binding.id {
                TextEditor(text: promptBinding(for: binding.id))
                    .font(AppTypography.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 110)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(MainWindowPalette.editorBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(MainWindowPalette.cardStroke, lineWidth: 1)
                    )
            }
        }
        .padding(.vertical, 11)
    }

    private var addAppMenu: some View {
        Menu {
            ForEach(AppPromptBindingCandidates.running(excluding: appState.llmAppPromptBindings)) { candidate in
                Button {
                    add(candidate)
                } label: {
                    Label {
                        Text(candidate.appDisplayName)
                    } icon: {
                        TranscriptAppIcon(bundleID: candidate.bundleID, size: 16)
                    }
                }
            }

            Divider()

            Button("Choose from Applications\u{2026}") { presentOpenPanel() }
        } label: {
            Text("Add an app")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func promptBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { appState.llmAppPromptBindings.first { $0.id == id }?.prompt ?? "" },
            set: { appState.updateAppPromptBinding(id: id, prompt: $0) }
        )
    }

    private func add(_ candidate: AppPromptBindingCandidate) {
        if let binding = appState.addAppPromptBinding(
            bundleID: candidate.bundleID,
            appDisplayName: candidate.appDisplayName
        ) {
            editingID = binding.id
        }
    }

    private func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        Task {
            guard let candidate = await AppPromptBindingCandidates.forApplication(at: url) else {
                return
            }
            add(candidate)
        }
    }
}

/// API endpoint set-up, reached from the engine sheet's per-row "Set up".
struct APIEndpointSheet: View {
    @Bindable var appState: AppState

    @Environment(\.dismiss) private var dismiss
    @State private var apiKeyDraft = ""
    @State private var isReplacingKey = false

    private var modelPresets: [LLMModelPreset] {
        [.gemini25Flash, .gpt41Mini, .custom]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your own API endpoint")
                    .font(AppTypography.cardTitle)
                Text("Transcript text is sent to this service. Audio never leaves this Mac.")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(MainWindowPalette.secondaryText)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Endpoint")
                    .font(AppTypography.subheadlineSemibold)
                TextField("https://api.openai.com/v1/chat/completions", text: $appState.llmEndpointURLString)
                    .textFieldStyle(.roundedBorder)
                    .font(AppTypography.codeBodyMedium)
                if let error = appState.llmEndpointValidationError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(AppTypography.caption)
                        .foregroundStyle(.red)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("API key")
                        .font(AppTypography.subheadlineSemibold)
                    Spacer(minLength: 12)
                    // Only "Connected" earns a pill — it means a test actually
                    // succeeded. "Saved" would just repeat the masked key below.
                    if appState.isMagicFormatSetupVerified {
                        StylePageStatusPill(text: "Connected", isPositive: true)
                    }
                }

                // Two states, one action each — rather than a placeholder field
                // beside a disabled Replace while a key is in fact stored.
                if let hint = appState.llmAPIKeyHint, !isReplacingKey {
                    HStack(spacing: 8) {
                        Text(hint)
                            .font(AppTypography.codeBodyMedium)
                            .foregroundStyle(MainWindowPalette.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .frame(minHeight: 22)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(MainWindowPalette.editorBackground)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(MainWindowPalette.cardStroke, lineWidth: 1)
                            )
                            .accessibilityLabel("Saved API key, ending \(hint.suffix(4))")

                        Button("Replace") { isReplacingKey = true }
                            .buttonStyle(.bordered)

                        Button("Clear") {
                            appState.clearLLMAPIKey()
                            apiKeyDraft = ""
                        }
                        .buttonStyle(.bordered)
                        .foregroundStyle(MainWindowPalette.destructive)
                    }
                } else {
                    HStack(spacing: 8) {
                        SecureField("Paste API key", text: $apiKeyDraft)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: apiKeyDraft) { _, _ in
                                appState.clearMagicFormatSetupTestResult()
                            }

                        Button("Save") {
                            appState.saveLLMAPIKey(apiKeyDraft)
                            apiKeyDraft = ""
                            isReplacingKey = false
                        }
                        .buttonStyle(.bordered)
                        .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if isReplacingKey {
                            Button("Cancel") {
                                apiKeyDraft = ""
                                isReplacingKey = false
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                if let error = appState.llmKeyOperationError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(AppTypography.caption)
                        .foregroundStyle(.red)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Model")
                    .font(AppTypography.subheadlineSemibold)

                HStack(spacing: 8) {
                    ForEach(modelPresets, id: \.self) { preset in
                        let isActive = appState.llmSelectedModelPreset == preset
                        Button {
                            appState.llmSelectedModelPreset = preset
                        } label: {
                            Text(preset == .custom ? "Custom ID" : preset.displayName)
                                .font(AppTypography.body)
                                .foregroundStyle(isActive ? Color.white : Color.primary)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(isActive ? Color.accentColor : MainWindowPalette.cardBackground)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(isActive ? .clear : MainWindowPalette.cardStroke, lineWidth: 1)
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableButtonStyle(pressedScale: 0.98))
                    }
                }

                if appState.llmSelectedModelPreset == .custom {
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

            HStack(spacing: 12) {
                Button(appState.isMagicFormatSetupTestInProgress ? "Testing\u{2026}" : "Test connection") {
                    Task { await appState.testMagicFormatSetup(apiKeyDraft: apiKeyDraft) }
                }
                .buttonStyle(.bordered)
                .disabled(!appState.canTestMagicFormatSetup(apiKeyDraft: apiKeyDraft))

                if appState.isMagicFormatSetupTestInProgress {
                    ProgressView().controlSize(.small)
                }

                if let result = appState.magicFormatSetupTestResult {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(result.severity.color)
                            .frame(width: 7, height: 7)
                        Text(result.latencyText ?? result.message)
                            .font(AppTypography.subheadline)
                            .foregroundStyle(MainWindowPalette.secondaryText)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 12)

                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
        .subtleScrollers()
        .background(MainWindowPalette.windowBackground)
    }
}
