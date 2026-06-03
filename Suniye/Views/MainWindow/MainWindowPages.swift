import Carbon
import AppKit
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
    @State private var isHoveringCurrentModelActions = false
    @State private var hoveredLibraryModelID: ASRModelID?
    private let currentModelColumns = [
        GridItem(.flexible(minimum: 150), spacing: 18, alignment: .leading),
        GridItem(.flexible(minimum: 150), spacing: 18, alignment: .leading)
    ]
    private let libraryModelColumns = [
        GridItem(.flexible(minimum: 120), spacing: 18, alignment: .leading),
        GridItem(.flexible(minimum: 120), spacing: 18, alignment: .leading)
    ]

    var body: some View {
        DetailScrollContainer {
            VStack(alignment: .leading, spacing: 4) {
                DetailPageTitle(title: "ASR Model")
                Text("Choose the offline recognizer Suniye keeps on your Mac.")
                    .font(AppTypography.body)
                    .foregroundStyle(MainWindowPalette.secondaryText)
            }

            if let banner = appState.asrModelBanner {
                InlineStatusBanner(
                    icon: banner.tone.icon,
                    tint: banner.tone.color,
                    title: banner.title,
                    detail: banner.detail,
                    progress: banner.progress
                )
            }

            VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
                SectionHeading(title: "Current Model")
                currentModelCard
            }

            VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
                SectionHeading(title: "Available Models")

                ForEach(appState.availableASRModelEntries) { entry in
                    modelLibraryRow(for: entry)
                }
            }
        }
    }

    private var currentModelCard: some View {
        let entry = appState.currentASRModelEntry

        return SurfaceCard(padding: 18) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Text(entry.displayName)
                                .font(AppTypography.pageTitle)

                            StatusPill(
                                title: appState.modelStatusValue,
                                tint: appState.modelStatusColor
                            )
                        }

                        Text(entry.description)
                            .font(AppTypography.body)
                            .foregroundStyle(MainWindowPalette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        FlowLayout(spacing: 6) {
                            ForEach(entry.badges, id: \.self) { badge in
                                ModelTagBadge(title: badge.rawValue)
                            }
                        }
                    }

                    Spacer(minLength: 24)

                    VStack(alignment: .trailing, spacing: 12) {
                        if appState.modelPrimaryActionTitle != "Current" {
                            Button(appState.modelPrimaryActionTitle) {
                                appState.performPrimaryASRAction(for: entry.id)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!appState.asrModelCanPerformPrimaryAction(for: entry.id))
                        }

                        if appState.asrModelSecondaryActionsEnabled(for: entry.id) {
                            hoverRevealActions(
                                for: entry.id,
                                isVisible: isHoveringCurrentModelActions
                            )
                        }
                    }
                }

                CardDivider()
                    .padding(.vertical, 2)

                LazyVGrid(columns: currentModelColumns, alignment: .leading, spacing: 14) {
                    rowMeta(title: "Speed", value: entry.speedLabel)
                    rowMeta(title: "Quality", value: entry.qualityLabel)
                    rowMeta(title: "Languages", value: entry.languageSummary)
                    rowMeta(title: "Size", value: entry.estimatedSizeText)
                    rowMeta(title: "On disk", value: appState.asrModelInstalledSizeText(for: entry.id))
                }

            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: AppMetrics.cardCornerRadius, style: .continuous)
                .stroke(appState.modelStatusColor.opacity(0.28), lineWidth: 1)
        )
        .onHover { hovering in
            isHoveringCurrentModelActions = hovering
        }
    }

    private func modelLibraryRow(for entry: ASRModelCatalogEntry) -> some View {
        SurfaceCard(padding: 16) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Text(entry.displayName)
                                .font(AppTypography.bodyMedium)

                            StatusPill(
                                title: appState.asrModelStatusText(for: entry.id),
                                tint: appState.asrModelStatusColor(for: entry.id)
                            )
                        }

                        Text(entry.description)
                            .font(AppTypography.body)
                            .foregroundStyle(MainWindowPalette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        FlowLayout(spacing: 6) {
                            ForEach(entry.badges, id: \.self) { badge in
                                ModelTagBadge(title: badge.rawValue)
                            }
                        }
                    }

                    Spacer(minLength: 20)

                    VStack(alignment: .trailing, spacing: 12) {
                        Button(appState.asrModelPrimaryActionTitle(for: entry.id)) {
                            appState.performPrimaryASRAction(for: entry.id)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!appState.asrModelCanPerformPrimaryAction(for: entry.id))

                        if appState.asrModelSecondaryActionsEnabled(for: entry.id) {
                            hoverRevealActions(
                                for: entry.id,
                                isVisible: hoveredLibraryModelID == entry.id
                            )
                        }
                    }
                }

                LazyVGrid(columns: libraryModelColumns, alignment: .leading, spacing: 12) {
                    rowMeta(title: "Size", value: entry.estimatedSizeText)
                    rowMeta(title: "Speed", value: entry.speedLabel)
                    rowMeta(title: "Quality", value: entry.qualityLabel)
                    rowMeta(title: "Languages", value: entry.languageSummary)
                }

                if let progressLabel = appState.asrModelProgressLabel(for: entry.id) {
                    CardDivider()
                        .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 8) {
                        if appState.activeASRModelOperationID == entry.id, appState.phase == .downloadingModel {
                            ProgressView(value: appState.downloadProgress)
                                .progressViewStyle(.linear)
                        } else if appState.activeASRModelOperationID == entry.id, appState.phase == .loading {
                            ProgressView()
                                .controlSize(.small)
                        }

                        Text(progressLabel)
                            .font(AppTypography.caption)
                            .foregroundStyle(MainWindowPalette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: AppMetrics.cardCornerRadius, style: .continuous)
                .stroke(appState.asrModelStatusColor(for: entry.id).opacity(appState.activeASRModelOperationID == entry.id ? 0.4 : 0), lineWidth: 1)
        )
        .onHover { hovering in
            if hovering {
                hoveredLibraryModelID = entry.id
            } else if hoveredLibraryModelID == entry.id {
                hoveredLibraryModelID = nil
            }
        }
    }

    private func hoverRevealActions(for modelID: ASRModelID, isVisible: Bool) -> some View {
        HStack(spacing: 6) {
            ActionIconButton(
                systemName: "folder",
                accessibilityLabel: "Open model folder",
                action: {
                appState.openModelFolder(for: modelID)
                }
            )

            ActionIconButton(
                systemName: "trash",
                accessibilityLabel: "Delete model",
                tint: MainWindowPalette.destructive,
                action: {
                appState.deleteASRModel(modelID)
                }
            )
        }
        .frame(height: AppMetrics.iconButtonSize)
        .opacity(isVisible ? 1 : 0.001)
        .offset(y: isVisible ? 0 : -2)
        .animation(.easeOut(duration: 0.16), value: isVisible)
    }

    private func rowMeta(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppTypography.caption)
                .foregroundStyle(MainWindowPalette.tertiaryText)
            Text(value)
                .font(AppTypography.subheadlineSemibold)
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StylePage: View {
    @Bindable var appState: AppState
    @State private var vocabularyDraft = ""
    @State private var apiKeyDraft = ""
    @State private var isApplePromptExpanded = false
    @State private var isLocalGemmaPromptExpanded = false
    @State private var isAPIEndpointConfigurationExpanded = false

    var body: some View {
        DetailScrollContainer {
            VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
                DetailPageTitle(title: "Magic Format")

                featureToggleCard
            }

            if appState.llmEnabled {
                formatterSection
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
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(providerOptions.enumerated()), id: \.element) { index, provider in
                        formatterProviderRow(for: provider)

                        if index < providerOptions.count - 1 {
                            CardDivider()
                                .padding(.leading, 56)
                        }
                    }
                }
            }
        }
        .onAppear {
            appState.selectRecommendedMagicFormatProviderIfAutomatic()
        }
    }

    private func formatterProviderRow(for provider: MagicFormatProvider) -> some View {
        let isSelected = appState.llmProvider == provider
        let isEnabled = providerPickerEnabled(provider)
        let status = providerStatus(for: provider)

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
        status: ProviderStatus
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            providerIcon(for: provider)

            VStack(alignment: .leading, spacing: 3) {
                Text(provider.displayName)
                    .font(AppTypography.bodyMedium)
                    .foregroundStyle(Color.primary)

                Text(providerSubtitle(for: provider))
                    .font(AppTypography.caption)
                    .foregroundStyle(MainWindowPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                FlowLayout(spacing: 5) {
                    ForEach(providerCapabilityTags(for: provider), id: \.self) { tag in
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
                providerPromptDisclosure(isExpanded: $isLocalGemmaPromptExpanded)
            }
        case .openAICompatible:
            VStack(alignment: .leading, spacing: 10) {
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
                        Text("Configure...")
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
        }
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
                    appState.deleteLocalGemmaModel()
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
                                StylePageVocabularyTag(term: term) {
                                    appState.removeVocabularyTerm(term)
                                }
                            }
                        }
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

    private func addTerm() {
        appState.addVocabularyTerm(vocabularyDraft)
        vocabularyDraft = ""
    }

    private var providerOptions: [MagicFormatProvider] {
        [.localGemma, .appleFoundationModels, .openAICompatible]
    }

    private func providerPickerEnabled(_ provider: MagicFormatProvider) -> Bool {
        switch provider {
        case .appleFoundationModels:
            return appState.appleMagicFormatAvailability.isAvailable
        case .localGemma:
            return appState.isLocalGemmaProviderSelectable
        case .automatic, .openAICompatible:
            return true
        }
    }

    private func providerIconName(for provider: MagicFormatProvider) -> String {
        switch provider {
        case .automatic:
            return "wand.and.stars"
        case .appleFoundationModels:
            return appleIntelligenceSymbolName
        case .localGemma:
            return "cpu"
        case .openAICompatible:
            return "key.horizontal"
        }
    }

    private var appleIntelligenceSymbolName: String {
        NSImage(systemSymbolName: "apple.intelligence", accessibilityDescription: nil) == nil
            ? "sparkles"
            : "apple.intelligence"
    }

    @ViewBuilder
    private func providerIcon(for provider: MagicFormatProvider) -> some View {
        if provider == .appleFoundationModels && appleIntelligenceSymbolName == "apple.intelligence" {
            Image(systemName: "apple.intelligence")
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(MainWindowPalette.selectedFill.opacity(0.75))
                )
        } else {
            Image(systemName: providerIconName(for: provider))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(providerIconColor(for: provider))
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(providerIconColor(for: provider).opacity(0.12))
                )
        }
    }

    private func providerIconColor(for provider: MagicFormatProvider) -> Color {
        switch provider {
        case .automatic:
            return .purple
        case .appleFoundationModels:
            return .blue
        case .localGemma:
            return .green
        case .openAICompatible:
            return .orange
        }
    }

    private func providerSubtitle(for provider: MagicFormatProvider) -> String {
        switch provider {
        case .automatic:
            return "Chooses Apple Intelligence, local model, then API."
        case .appleFoundationModels:
            if !appState.appleMagicFormatAvailability.isAvailable {
                return appState.appleMagicFormatAvailability.statusText
            }
            return "Fast on-device formatting, less accurate than the local model."
        case .localGemma:
            return "Fastest local LLM formatter on this Mac."
        case .openAICompatible:
            return "Use your OpenAI-compatible endpoint."
        }
    }

    private func providerCapabilityTags(for provider: MagicFormatProvider) -> [String] {
        switch provider {
        case .automatic:
            return ["Local first", "Fallbacks"]
        case .appleFoundationModels:
            switch appState.appleMagicFormatAvailability {
            case .available:
                return ["On-device", "Fast", "Lower accuracy"]
            case .appleIntelligenceNotEnabled:
                return ["On-device", "Fast", "Needs setting"]
            case .modelNotReady:
                return ["On-device", "Fast", "Preparing"]
            case .deviceNotEligible, .unsupportedSDKOrRuntime:
                return ["On-device", "Unavailable", "Lower accuracy"]
            }
        case .localGemma:
            if !appState.isLocalGemmaProviderSelectable {
                return ["Recommended", "Fastest", "Apple Silicon only"]
            }

            switch appState.localGemmaInstallState {
            case .notInstalled, .failed:
                return ["Recommended", "Fastest", "Download once"]
            case .downloading:
                return ["Recommended", "Fastest", "Downloading"]
            case .verifying:
                return ["Recommended", "Fastest", "Verifying"]
            case .installed:
                return ["Recommended", "Fastest", "Private"]
            case .unavailable:
                return ["Recommended", "Fastest", "Runtime missing"]
            }
        case .openAICompatible:
            return ["Cloud/API", "Bring key", "Most flexible"]
        }
    }

    private func providerStatus(for provider: MagicFormatProvider) -> ProviderStatus {
        switch provider {
        case .automatic:
            switch appState.magicFormatSetupState {
            case .off:
                return ProviderStatus(text: "Off", color: .gray)
            case .ready:
                return ProviderStatus(text: "Ready", color: .green)
            case .needsAPIKey:
                return ProviderStatus(text: "Needs key", color: .orange)
            case .needsServiceSetup:
                return ProviderStatus(text: "Setup needed", color: .orange)
            }
        case .appleFoundationModels:
            switch appState.appleMagicFormatAvailability {
            case .available:
                return ProviderStatus(text: "Ready", color: .green)
            case .appleIntelligenceNotEnabled:
                return ProviderStatus(text: "Off", color: .orange)
            case .modelNotReady:
                return ProviderStatus(text: "Preparing", color: .blue)
            case .deviceNotEligible:
                return ProviderStatus(text: "Unsupported", color: .gray)
            case .unsupportedSDKOrRuntime:
                return ProviderStatus(text: "Requires macOS 26", color: .gray)
            }
        case .localGemma:
            if !appState.isLocalGemmaProviderSelectable {
                return ProviderStatus(text: "Requires Apple Silicon", color: .gray)
            }
            switch appState.localGemmaInstallState {
            case .unavailable:
                return ProviderStatus(text: "Unavailable", color: .gray)
            case .notInstalled:
                return ProviderStatus(text: "Not installed", color: .orange)
            case .downloading:
                return ProviderStatus(text: "Downloading", color: .blue)
            case .verifying:
                return ProviderStatus(text: "Verifying", color: .blue)
            case .installed:
                return appState.localGemmaMagicFormatAvailability.isAvailable
                    ? ProviderStatus(text: "Ready", color: .green)
                    : ProviderStatus(text: "Setup needed", color: .orange)
            case .failed:
                return ProviderStatus(text: "Failed", color: .red)
            }
        case .openAICompatible:
            if appState.llmEndpointValidationError != nil || appState.llmModelValidationError != nil {
                return ProviderStatus(text: "Invalid", color: .red)
            }
            if appState.isMagicFormatSetupVerified {
                return ProviderStatus(text: "Connected", color: .green)
            }
            return appState.hasLLMAPIKey
                ? ProviderStatus(text: "Saved key", color: .blue)
                : ProviderStatus(text: "Needs key", color: .orange)
        }
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
        switch appState.magicFormatSetupState {
        case .ready:
            return "Ready - using \(activeFormatterName)"
        case .off:
            return "Off"
        case .needsAPIKey, .needsServiceSetup:
            return setupStatusText
        }
    }

    private var activeFormatterName: String {
        if appState.usesAppleMagicFormatSettings {
            return "Apple Intelligence"
        }
        if appState.usesLocalGemmaMagicFormatSettings {
            return "Local Model"
        }
        return "API Endpoint"
    }

    private var setupStatusColor: Color {
        switch appState.magicFormatSetupState {
        case .off:
            return .gray
        case .needsAPIKey, .needsServiceSetup:
            return .orange
        case .ready:
            if appState.usesLocalMagicFormatSettings {
                return .green
            }
            return appState.isMagicFormatSetupVerified ? .green : .blue
        }
    }

    private var setupStatusText: String {
        if appState.usesAppleMagicFormatSettings {
            return appState.appleMagicFormatAvailability.isAvailable
                ? "Apple Intelligence ready"
                : appState.appleMagicFormatAvailability.statusText
        }
        if appState.usesLocalGemmaMagicFormatSettings {
            return appState.localGemmaMagicFormatAvailability.isAvailable
                ? "Local model ready"
                : appState.localGemmaInstallStatusText
        }
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

    private struct ProviderStatus {
        let text: String
        let color: Color
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

private struct StylePageProviderStatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(AppTypography.caption)
            .lineLimit(1)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(color.opacity(0.12))
            )
    }
}

private struct StylePageProviderTagBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(AppTypography.caption)
            .foregroundStyle(MainWindowPalette.secondaryText)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(MainWindowPalette.selectedFill.opacity(0.7))
            )
    }
}

private struct StylePageRadioIndicator: View {
    let isSelected: Bool
    let isEnabled: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(indicatorColor, lineWidth: 1.3)

            if isSelected {
                Circle()
                    .fill(indicatorColor)
                    .padding(4)
            }
        }
        .frame(width: 14, height: 14)
    }

    private var indicatorColor: Color {
        if isSelected {
            return .accentColor
        }
        return isEnabled ? MainWindowPalette.tertiaryText : MainWindowPalette.divider
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

                        CardDivider()
                            .padding(.vertical, AppMetrics.toggleDetailVerticalPadding)

                        SettingsToggleRow(
                            title: "Sound Feedback",
                            detail: "Play short local sounds when recording starts, dictation succeeds, or dictation fails.",
                            isOn: $appState.soundFeedbackEnabled
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
                SectionHeading(title: "Indicator")

                SurfaceCard {
                    VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
                        SettingsToggleRow(
                            title: "Hide While Idle",
                            detail: "Hide the floating indicator when Suniye is ready but not actively dictating. When hidden, floating click-to-start is unavailable until the indicator appears again for recording, processing, or errors.",
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
                            detail: "Suniye checks in the background and asks before installing.",
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
