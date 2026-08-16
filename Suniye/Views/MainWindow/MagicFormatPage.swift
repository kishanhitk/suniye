import AppKit
import SwiftUI

/// Magic Format, flattened: nothing is in a card, groups are separated by space,
/// rows by a hairline, and every row ends in a chevron rather than a verb. The
/// filename, download size, keep-alive trade-off and eval note all moved into the
/// sheet you open to change that thing — they answer questions you only ask while
/// editing.
struct StylePage: View {
    @Bindable var appState: AppState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var vocabularyDraft = ""
    @State private var isAddingWord = false
    @State private var sheet: MagicFormatSheetRoute?

    private var providerPresenter: MagicFormatProviderPresenter {
        MagicFormatProviderPresenter(appState: appState)
    }

    var body: some View {
        DetailScrollContainer {
            header

            if appState.llmEnabled {
                onState
            } else {
                MagicFormatOffState(appState: appState) {
                    appState.llmEnabled = true
                    // Only when the engine being switched on is actually the
                    // local one: an API or Apple Intelligence user would
                    // otherwise silently start a multi-gigabyte download they
                    // will never use.
                    if providerPresenter.displayedProviderSelection == .localGemma,
                       case .notInstalled = appState.localGemmaInstallState,
                       appState.canStartLocalGemmaDownload {
                        appState.startLocalGemmaDownload()
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: appState.llmEnabled)
        .sheet(item: $sheet) { route in
            switch route {
            case .engine:
                EngineSheet(appState: appState)
            case .instructions:
                InstructionsSheet(appState: appState)
            case .perApp:
                PerAppInstructionsSheet(appState: appState)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                DetailPageTitle(title: "Magic Format")
                if let statusLine {
                    Text(statusLine.text)
                        .font(AppTypography.body)
                        .foregroundStyle(statusLine.tint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            Toggle("", isOn: $appState.llmEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel("Magic Format")
        }
        .padding(.bottom, 6)
    }

    /// Off says what happens instead, which the toggle cannot. On says nothing:
    /// the toggle already shows it is on and the Engine row below names the
    /// engine — unless something is wrong, which is worth a line.
    private var statusLine: (text: String, tint: Color)? {
        guard appState.llmEnabled else {
            return ("Off. Dictation is pasted exactly as heard.", MainWindowPalette.secondaryText)
        }
        switch appState.magicFormatSetupState {
        case .ready, .off:
            return nil
        case .needsAPIKey, .needsServiceSetup:
            return (providerPresenter.topStatusText, .orange)
        }
    }

    // MARK: - On

    private var onState: some View {
        VStack(alignment: .leading, spacing: 30) {
            group(heading: "Engine") {
                DisclosureSettingRow(
                    title: engineName,
                    value: engineValue
                ) {
                    sheet = .engine
                }

                if appState.usesLocalGemmaMagicFormatSettings {
                    RowSeparator()
                    keepAliveRow
                }
            }

            group(heading: "Instructions") {
                DisclosureSettingRow(
                    title: "Base instructions",
                    value: isPromptAtDefault ? "Default" : "Edited"
                ) {
                    sheet = .instructions
                }

                RowSeparator()

                DisclosureSettingRow(
                    title: "App-specific writing style",
                    value: appPromptSummary
                ) {
                    sheet = .perApp
                }
            }

            vocabularyGroup
        }
    }

    private func group<Content: View>(
        heading: String,
        note: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsGroupHeading(text: heading, note: note)
            VStack(spacing: 0) {
                content()
            }
        }
    }

    /// A menu, not a sheet: picking a duration is one decision with four answers.
    /// The trade-off lives on an info tip beside the label — as a menu item it
    /// stretched the menu to the width of the sentence.
    ///
    /// "Keep alive" over "Release memory after": it is the standard name for this
    /// setting, so it is the phrase a user is most likely to already know.
    private var keepAliveRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            HStack(spacing: 5) {
                // The term the runtime itself uses (llama.cpp / Ollama keep_alive),
                // and what the type is already called: LocalLLMKeepAlive.
                Text("Keep alive")
                    .font(AppTypography.rowTitle)

                Image(systemName: "info.circle")
                    .font(AppTypography.caption)
                    .foregroundStyle(MainWindowPalette.tertiaryText)
                    .help("Shorter frees memory sooner; the next dictation then waits for the model to load again.")
                    .accessibilityLabel("Shorter frees memory sooner; the next dictation then waits for the model to load again.")
            }

            Spacer(minLength: 12)

            Picker("", selection: $appState.localModelKeepAlive) {
                ForEach(LocalLLMKeepAlive.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 4)
    }

    // MARK: - Vocabulary

    private var vocabularyGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsGroupHeading(
                text: "Vocabulary",
                // The dependency stated where the words are. Honest version: these
                // reach the formatter, so they apply while it is on.
                note: "Words the formatter is told to spell your way."
            )

            if !appState.vocabularyTerms.isEmpty {
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

            // Inline, not a sheet: adding five words should be five keystrokes
            // and no dismissals.
            if isAddingWord {
                HStack(spacing: 8) {
                    TextField("Word or phrase", text: $vocabularyDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(AppTypography.rowTitle)
                        .frame(maxWidth: 260)
                        .onSubmit(addTerm)

                    Button("Add", action: addTerm)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(vocabularyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Cancel") {
                        vocabularyDraft = ""
                        isAddingWord = false
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            } else {
                Button("Add a word") { isAddingWord = true }
                    .buttonStyle(.link)
                    .font(AppTypography.rowTitle)
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Keep learning from my corrections")
                    .font(AppTypography.rowTitle)
                Spacer(minLength: 12)
                Toggle("", isOn: $appState.learnFromEditsEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .padding(.top, 4)
        }
    }

    private func addTerm() {
        appState.addVocabularyTerm(vocabularyDraft)
        vocabularyDraft = ""
        isAddingWord = false
    }

    // MARK: - Values

    private var engineName: String {
        switch providerPresenter.displayedProviderSelection {
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

    private var engineValue: String {
        switch providerPresenter.displayedProviderSelection {
        case .localGemma:
            // The row title already says the engine is local, so the value
            // spends itself on the one fact it does not carry: which model.
            return appState.localGemmaModelEntry.displayName
        case .appleFoundationModels:
            return "On this Mac"
        case .openAICompatible:
            return URL(string: appState.llmEndpointURLString)?.host ?? "Not set up"
        case .automatic:
            return appState.magicFormatProviderDetailText
        }
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

    private var appPromptSummary: String {
        let names = appState.llmAppPromptBindings.map(\.appDisplayName)
        guard !names.isEmpty else {
            return "None"
        }
        return names.joined(separator: ", ")
    }
}

enum MagicFormatSheetRoute: String, Identifiable {
    case engine
    case instructions
    case perApp

    var id: String { rawValue }
}
