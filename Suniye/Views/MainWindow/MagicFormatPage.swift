import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct StylePage: View {
    @Bindable var appState: AppState
    @State private var vocabularyDraft = ""
    @State private var apiKeyDraft = ""
    @State private var isApplePromptExpanded = false
    @State private var isLocalGemmaPromptExpanded = false
    @State private var isAPIEndpointConfigurationExpanded = false
    @State private var expandedAppPromptBindingIDs: Set<UUID> = []

    var body: some View {
        DetailScrollContainer {
            VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
                DetailPageTitle(title: "Magic Format")

                featureToggleCard
            }

            if appState.llmEnabled {
                formatterSection
                perAppPromptsSection
                vocabularySection
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
                        Text("Magic Format")
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
                        Text(topStatusText)
                            .font(AppTypography.caption)
                            .foregroundStyle(MainWindowPalette.secondaryText)
                    }
                }
            }
        }
    }

    // MARK: - Formatter

    private var formatterSection: some View {
        VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
            SectionHeading(title: "Formatter")

            SurfaceCard(padding: 8) {
                let options = providerPresenter.providerOptions

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.element) { index, provider in
                        formatterProviderRow(for: provider)

                        if index < options.count - 1 {
                            CardDivider()
                                .padding(.leading, 56)
                        }
                    }
                }
            }
        }
    }

    private func formatterProviderRow(for provider: MagicFormatProvider) -> some View {
        let isSelected = providerPresenter.displayedProviderSelection == provider
        let isEnabled = providerPresenter.isSelectable(provider)
        let status = providerPresenter.status(for: provider)

        return VStack(alignment: .leading, spacing: 0) {
            if isEnabled {
                Button {
                    appState.llmProvider = provider
                } label: {
                    formatterProviderHeader(for: provider, isSelected: isSelected, isEnabled: isEnabled, status: status)
                }
                .buttonStyle(.plain)
            } else {
                formatterProviderHeader(for: provider, isSelected: isSelected, isEnabled: isEnabled, status: status)
            }

            providerUnavailableHelp(for: provider)

            if isSelected {
                CardDivider()
                    .padding(.leading, 56)
                selectedProviderDetails(for: provider)
                    .padding(.leading, 56)
                    .padding(.trailing, 10)
                    .padding(.vertical, 10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? MainWindowPalette.selectedFill.opacity(0.8) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
        )
    }

    private func formatterProviderHeader(
        for provider: MagicFormatProvider,
        isSelected: Bool,
        isEnabled: Bool,
        status: MagicFormatProviderStatus
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            providerIcon(for: provider)

            VStack(alignment: .leading, spacing: 3) {
                Text(provider.displayName)
                    .font(AppTypography.bodyMedium)
                    .foregroundStyle(Color.primary)

                Text(providerPresenter.subtitle(for: provider))
                    .font(AppTypography.caption)
                    .foregroundStyle(MainWindowPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                FlowLayout(spacing: 5) {
                    ForEach(providerPresenter.capabilityTags(for: provider), id: \.self) { tag in
                        StylePageProviderTagBadge(title: tag)
                    }
                }
                .padding(.top, 3)
            }

            Spacer(minLength: 12)

            StylePageProviderStatusPill(text: status.text, color: status.color)

            StylePageRadioIndicator(isSelected: isSelected, isEnabled: isEnabled)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .opacity(isEnabled || isSelected ? 1 : 0.76)
    }

    @ViewBuilder
    private func selectedProviderDetails(for provider: MagicFormatProvider) -> some View {
        switch provider {
        case .automatic:
            VStack(alignment: .leading, spacing: 8) {
                settingsValueRow(label: "Using", value: appState.magicFormatProviderDetailText)

                if appState.needsAPIConfigurationForMagicFormat {
                    CardDivider()
                    apiEndpointConfigurationDisclosure(title: "Configure API fallback...")
                }
            }
        case .appleFoundationModels:
            providerPromptDisclosure(isExpanded: $isApplePromptExpanded)
        case .localGemma:
            VStack(alignment: .leading, spacing: 10) {
                settingsValueRow(label: "Model", value: appState.localGemmaModelEntry.displayName)
                CardDivider()
                settingsValueRow(label: "Size", value: appState.localGemmaModelEntry.expectedSizeText)

                if let detail = localGemmaInstallDetail {
                    CardDivider()
                    settingsValueRow(
                        label: detail.label,
                        value: detail.value,
                        valueFont: AppTypography.codeBody
                    )
                }

                CardDivider()
                localGemmaControls
                CardDivider()
                localGemmaKeepAlivePicker
                CardDivider()
                providerPromptDisclosure(isExpanded: $isLocalGemmaPromptExpanded)
            }
        case .openAICompatible:
            apiEndpointConfigurationDisclosure(title: "Configure...")
        }
    }

    private func apiEndpointConfigurationDisclosure(title: String) -> some View {
        DisclosureGroup(isExpanded: $isAPIEndpointConfigurationExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                promptAdvancedSection
                CardDivider()
                apiConnectionAdvancedSection
                CardDivider()
                apiModelAdvancedSection
                CardDivider()
                apiTestAdvancedSection
            }
            .padding(.top, AppMetrics.disclosureContentTopPadding)
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(AppTypography.subheadlineSemibold)

                Spacer(minLength: 12)

                if let result = appState.magicFormatSetupTestResult {
                    Label(result.message, systemImage: result.severity == .success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(AppTypography.caption)
                        .foregroundStyle(result.severity.color)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .disclosureGroupStyle(.automatic)
    }

    private func providerPromptDisclosure(isExpanded: Binding<Bool>) -> some View {
        DisclosureGroup(isExpanded: isExpanded) {
            promptAdvancedSection
                .padding(.top, AppMetrics.disclosureContentTopPadding)
        } label: {
            Text("Prompt")
                .font(AppTypography.subheadlineSemibold)
        }
        .disclosureGroupStyle(.automatic)
    }

    @ViewBuilder
    private func providerUnavailableHelp(for provider: MagicFormatProvider) -> some View {
        switch provider {
        case .appleFoundationModels where !appState.appleMagicFormatAvailability.isAvailable:
            CardDivider()
                .padding(.leading, 56)
            appleIntelligenceHelpRow
                .padding(.leading, 56)
                .padding(.trailing, 10)
                .padding(.vertical, 10)
        case .localGemma where !appState.isLocalGemmaProviderSelectable:
            CardDivider()
                .padding(.leading, 56)
            Text("Local Model requires Apple Silicon. Use Apple Intelligence or API Endpoint on this Mac.")
                .font(AppTypography.caption)
                .foregroundStyle(MainWindowPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 56)
                .padding(.trailing, 10)
                .padding(.vertical, 10)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var appleIntelligenceHelpRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(appleIntelligenceHelpText)
                .font(AppTypography.caption)
                .foregroundStyle(MainWindowPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 12)

            if appState.appleMagicFormatAvailability == .appleIntelligenceNotEnabled {
                Button("Open Settings") {
                    appState.openAppleIntelligenceSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var appleIntelligenceHelpText: String {
        switch appState.appleMagicFormatAvailability {
        case .available:
            return "Apple Intelligence is ready."
        case .appleIntelligenceNotEnabled:
            return "Turn on Apple Intelligence in System Settings, then come back to Suniye."
        case .modelNotReady:
            return "Apple Intelligence is downloading or preparing its local model. Try again when it is ready."
        case .deviceNotEligible:
            return "This Mac is not eligible for Apple Intelligence. Use Local Model or API Endpoint instead."
        case .unsupportedSDKOrRuntime:
            return "Apple Intelligence requires macOS 26 or newer. Use Local Model or API Endpoint instead."
        }
    }

    private var localGemmaInstallDetail: (label: String, value: String)? {
        switch appState.localGemmaInstallState {
        case .unavailable:
            return ("Runtime", appState.localGemmaInstallStatusText)
        case .notInstalled, .installed:
            return nil
        case .downloading:
            return ("Download", appState.localGemmaInstallStatusText)
        case .verifying:
            return ("Install", appState.localGemmaInstallStatusText)
        case .failed:
            return ("Error", appState.localGemmaInstallStatusText)
        }
    }

    private var localGemmaKeepAlivePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Keep model loaded for")
                .font(AppTypography.subheadlineSemibold)

            NativePopupPicker(
                items: LocalLLMKeepAlive.allCases,
                selection: $appState.localModelKeepAlive,
                title: { $0.displayName }
            )
            .frame(maxWidth: 320)

            Text("Longer keeps repeat formatting fast but holds memory while idle.")
                .font(AppTypography.caption)
                .foregroundStyle(MainWindowPalette.secondaryText)
        }
    }

    @ViewBuilder
    private var localGemmaControls: some View {
        HStack(spacing: 8) {
            switch appState.localGemmaInstallState {
            case .unavailable:
                EmptyView()
            case .notInstalled, .failed:
                Button("Download Local Model") {
                    appState.startLocalGemmaDownload()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!appState.canStartLocalGemmaDownload)
            case .downloading:
                Button("Cancel") {
                    appState.cancelLocalGemmaDownload()
                }
                .buttonStyle(.bordered)
                .disabled(!appState.canCancelLocalGemmaDownload)
            case .verifying:
                ProgressView()
                    .controlSize(.small)
            case .installed:
                Button(appState.isMagicFormatSetupTestInProgress ? "Testing\u{2026}" : "Test") {
                    Task {
                        await appState.testLocalGemmaSetup()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.isMagicFormatSetupTestInProgress || !appState.localGemmaMagicFormatAvailability.isAvailable)

                Button("Delete Model") {
                    Task {
                        await appState.deleteLocalGemmaModel()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!appState.canDeleteLocalGemmaModel)
            }

            if appState.isMagicFormatSetupTestInProgress, appState.usesLocalGemmaMagicFormatSettings {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer(minLength: 12)

            if let result = appState.magicFormatSetupTestResult, appState.usesLocalGemmaMagicFormatSettings {
                Label(result.message, systemImage: result.severity == .success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(AppTypography.caption)
                    .foregroundStyle(result.severity.color)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    // MARK: - Per-App Prompts

    private var perAppPromptsSection: some View {
        VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
            SectionHeading(title: "Per-App Prompts")

            SurfaceCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("App-specific prompts")
                                .font(AppTypography.body)
                            Text("Use a different Magic Format prompt when dictating into these apps. All other apps use the formatter prompt above. A per-app prompt applies as written, whichever formatter runs.")
                                .font(AppTypography.caption)
                                .foregroundStyle(MainWindowPalette.secondaryText)
                        }

                        Spacer(minLength: 12)

                        addAppPromptBindingMenu
                    }

                    if !appState.llmAppPromptBindings.isEmpty {
                        CardDivider()

                        ForEach(appState.llmAppPromptBindings) { binding in
                            appPromptBindingRow(for: binding)

                            if binding.id != appState.llmAppPromptBindings.last?.id {
                                CardDivider()
                            }
                        }
                    }
                }
            }
        }
    }

    private var addAppPromptBindingMenu: some View {
        Menu {
            ForEach(AppPromptBindingCandidates.running(excluding: appState.llmAppPromptBindings)) { candidate in
                Button(candidate.appDisplayName) {
                    addAppPromptBinding(for: candidate)
                }
            }

            Divider()

            Button("Choose from Applications\u{2026}") {
                presentAppPromptBindingOpenPanel()
            }
        } label: {
            Label("Add App", systemImage: "plus")
        }
        .controlSize(.small)
        .fixedSize()
    }

    private func appPromptBindingRow(for binding: AppPromptBinding) -> some View {
        DisclosureGroup(isExpanded: appPromptBindingExpansion(for: binding.id)) {
            TextEditor(text: appPromptBindingPrompt(for: binding.id))
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
                .padding(.top, AppMetrics.disclosureContentTopPadding)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(binding.appDisplayName)
                        .font(AppTypography.bodyMedium)
                    Text(binding.bundleID)
                        .font(AppTypography.caption)
                        .foregroundStyle(MainWindowPalette.secondaryText)
                }

                Spacer(minLength: 12)

                Button {
                    appState.removeAppPromptBinding(id: binding.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove prompt for \(binding.appDisplayName)")
            }
        }
        .disclosureGroupStyle(.automatic)
    }

    private func appPromptBindingExpansion(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { expandedAppPromptBindingIDs.contains(id) },
            set: { isExpanded in
                if isExpanded {
                    expandedAppPromptBindingIDs.insert(id)
                } else {
                    expandedAppPromptBindingIDs.remove(id)
                }
            }
        )
    }

    private func appPromptBindingPrompt(for id: UUID) -> Binding<String> {
        Binding(
            get: { appState.llmAppPromptBindings.first { $0.id == id }?.prompt ?? "" },
            set: { appState.updateAppPromptBinding(id: id, prompt: $0) }
        )
    }

    private func addAppPromptBinding(for candidate: AppPromptBindingCandidate) {
        if let binding = appState.addAppPromptBinding(bundleID: candidate.bundleID, appDisplayName: candidate.appDisplayName) {
            expandedAppPromptBindingIDs.insert(binding.id)
        }
    }

    private func presentAppPromptBindingOpenPanel() {
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
            addAppPromptBinding(for: candidate)
        }
    }

    // MARK: - Vocabulary

    private var vocabularySection: some View {
        VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
            SectionHeading(title: "Vocabulary")

            SurfaceCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("Protected words")
                            .font(AppTypography.body)
                            .foregroundStyle(Color.primary)
                            .frame(minWidth: 112, alignment: .leading)

                        TextField("e.g. Suniye, PostgreSQL, gRPC", text: $vocabularyDraft)
                            .textFieldStyle(.roundedBorder)
                            .font(AppTypography.body)
                            .onSubmit(addTerm)

                        Button("Add", action: addTerm)
                            .buttonStyle(.bordered)
                            .disabled(vocabularyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if !appState.vocabularyTerms.isEmpty {
                        CardDivider()

                        FlowLayout(spacing: 6) {
                            ForEach(appState.vocabularyTerms, id: \.self) { term in
                                StylePageVocabularyTag(
                                    term: term,
                                    isAutoLearned: appState.isAutoLearnedVocabularyTerm(term)
                                ) {
                                    appState.removeVocabularyTerm(term)
                                }
                            }
                        }
                    }

                    CardDivider()

                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Learn from my edits")
                                .font(AppTypography.body)
                            Text("When you correct a name or term right after dictating, Suniye adds it here automatically.")
                                .font(AppTypography.caption)
                                .foregroundStyle(MainWindowPalette.secondaryText)
                        }

                        Spacer(minLength: 12)

                        Toggle("", isOn: $appState.learnFromEditsEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    private var promptAdvancedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Prompt")
                        .font(AppTypography.subheadlineSemibold)
                    Text(promptDescription)
                        .font(AppTypography.caption)
                        .foregroundStyle(MainWindowPalette.secondaryText)
                }

                Spacer(minLength: 12)

                Button(promptResetTitle) {
                    resetPrompt()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isPromptAtDefault)
            }

            TextEditor(text: promptBinding)
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

    private var apiConnectionAdvancedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
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
        }
    }

    private var apiModelAdvancedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Model")
                .font(AppTypography.subheadlineSemibold)

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

    private var apiTestAdvancedSection: some View {
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

    // MARK: - Helpers

    private var providerPresenter: MagicFormatProviderPresenter {
        MagicFormatProviderPresenter(appState: appState)
    }

    private func addTerm() {
        appState.addVocabularyTerm(vocabularyDraft)
        vocabularyDraft = ""
    }

    @ViewBuilder
    private func providerIcon(for provider: MagicFormatProvider) -> some View {
        StylePageProviderIcon(provider: provider)
    }

    private var promptBinding: Binding<String> {
        if appState.usesAppleMagicFormatSettings {
            return $appState.llmAppleSystemPrompt
        }
        if appState.usesLocalGemmaMagicFormatSettings {
            return $appState.llmGemmaSystemPrompt
        }
        return $appState.llmBaseSystemPrompt
    }

    private var promptDescription: String {
        if appState.usesAppleMagicFormatSettings {
            return "Instructions for Apple's local formatter."
        }
        if appState.usesLocalGemmaMagicFormatSettings {
            return "Instructions for the local model."
        }
        return "Instructions for rewriting your text."
    }

    private var promptResetTitle: String {
        if appState.usesAppleMagicFormatSettings {
            return "Reset to Apple Default"
        }
        if appState.usesLocalGemmaMagicFormatSettings {
            return "Reset to Local Model Default"
        }
        return "Reset to API Default"
    }

    private var isPromptAtDefault: Bool {
        if appState.usesAppleMagicFormatSettings {
            return appState.llmAppleSystemPrompt == LLMDefaults.defaultAppleMagicFormatPrompt
        }
        if appState.usesLocalGemmaMagicFormatSettings {
            return appState.llmGemmaSystemPrompt == LLMDefaults.defaultGemmaMagicFormatPrompt
        }
        return appState.llmBaseSystemPrompt == LLMDefaults.defaultBaseSystemPrompt
    }

    private func resetPrompt() {
        if appState.usesAppleMagicFormatSettings {
            appState.resetAppleMagicFormatPrompt()
        } else if appState.usesLocalGemmaMagicFormatSettings {
            appState.resetGemmaMagicFormatPrompt()
        } else {
            appState.resetBaseMagicFormatPrompt()
        }
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

    private var topStatusText: String {
        providerPresenter.topStatusText
    }

    private var setupStatusColor: Color {
        providerPresenter.setupStatusColor
    }

    private var setupStatusText: String {
        providerPresenter.setupStatusText
    }

    private func settingsValueRow(label: String, value: String, valueFont: Font = AppTypography.body) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .font(AppTypography.body)
                .foregroundStyle(Color.primary)

            Spacer(minLength: 12)

            Text(value)
                .font(valueFont)
                .foregroundStyle(MainWindowPalette.secondaryText)
                .multilineTextAlignment(.trailing)
        }
        .frame(maxWidth: .infinity, minHeight: 28)
    }

}
