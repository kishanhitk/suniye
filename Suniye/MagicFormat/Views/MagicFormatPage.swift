import AppKit
import SwiftUI

/// Magic Format: the engine, the instructions and the vocabulary, each a card.
/// A row that opens a sheet ends in a chevron; the sheet holds the details
/// that only matter while editing, such as the file name and download size.
struct StylePage: View {
    @Bindable var appState: AppState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var vocabularyDraft = ""
    @State private var isAddingWord = false
    @FocusState private var isWordFieldFocused: Bool
    @State private var sheet: MagicFormatSheetRoute?

    private var providerPresenter: MagicFormatProviderPresenter {
        MagicFormatProviderPresenter(appState: appState)
    }

    var body: some View {
        SettingsForm(
            title: "Magic Format",
            subtitle: statusLine?.text,
            subtitleTint: statusLine?.tint ?? MainWindowPalette.settingsSecondaryText
        ) {
            // Only while on: the off page turns Magic Format on with its own
            // button, which also starts the local model download when needed.
            if appState.llmEnabled {
                Toggle("", isOn: $appState.llmEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel("Magic Format")
                    .settingsControlAnchor(.magicFormat)
            }
        } content: {
            if appState.llmEnabled {
                if let progress = appState.localGemmaInstallProgress {
                    InlineStatusBanner(
                        icon: "arrow.down.circle",
                        tint: .accentColor,
                        title: "Downloading the local model",
                        detail: appState.localGemmaInstallStatusText,
                        progress: progress,
                        actionTitle: appState.canCancelLocalGemmaDownload ? "Cancel" : nil,
                        action: appState.canCancelLocalGemmaDownload ? { appState.cancelLocalGemmaDownload() } : nil,
                        actionIsProminent: false
                    )
                    .transition(SettingsMotion.banner(reduceMotion: reduceMotion))
                }
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
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: appState.llmEnabled)
        .animation(SettingsMotion.curve(reduceMotion: reduceMotion), value: appState.localGemmaInstallProgress == nil)
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

    /// Off says what happens instead, which the toggle cannot. On says nothing:
    /// the toggle already shows it is on and the Engine row below names the
    /// engine, unless something is wrong, which is worth a line.
    private var statusLine: (text: String, tint: Color)? {
        guard appState.llmEnabled else {
            return ("Off. Dictation is pasted exactly as heard.", MainWindowPalette.settingsSecondaryText)
        }
        if appState.localGemmaInstallState.isActive {
            return nil
        }
        switch appState.magicFormatSetupState {
        case .ready, .off:
            return nil
        case .needsAPIKey, .needsServiceSetup:
            return (providerPresenter.topStatusText, MainWindowPalette.warningText)
        }
    }

    // MARK: - On

    @ViewBuilder
    private var onState: some View {
        SettingsSection(SettingsRowID.magicFormatEngine.title) {
            DisclosureSettingRow(
                title: engineName,
                value: engineValue,
                anchor: .magicFormatEngine
            ) {
                sheet = .engine
            }

            if SettingsRowID.keepAlive.isAvailable(in: appState) {
                keepAliveRow
            }
        }

        SettingsSection("Instructions") {
            DisclosureSettingRow(.baseInstructions, in: appState, value: isPromptAtDefault ? "Default" : "Edited") {
                sheet = .instructions
            }
            DisclosureSettingRow(.appSpecificWritingStyle, in: appState, value: appState.llmAppPromptSummary) {
                sheet = .perApp
            }
        }

        vocabularySection
    }

    /// A menu, not a sheet: picking a duration is one decision with four answers.
    ///
    /// "Keep alive" over "Release memory after": it is the standard name for this
    /// setting, so it is the phrase a user is most likely to already know.
    ///
    /// It is also the term the runtime itself uses (llama.cpp / Ollama
    /// keep_alive), and what the type is already called: LocalLLMKeepAlive.
    private var keepAliveRow: some View {
        ControlSettingRow(.keepAlive, in: appState) {
            Picker(SettingsRowID.keepAlive.title, selection: $appState.localModelKeepAlive) {
                ForEach(LocalLLMKeepAlive.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }

    // MARK: - Vocabulary

    /// The switch first, then the words, so the footer that explains the
    /// words sits under them.
    private var vocabularySection: some View {
        SettingsSection(SettingsRowID.vocabulary.title) {
            ToggleSettingRow(.keepLearning, in: appState, isOn: $appState.learnFromEditsEnabled)

            SettingsCustomRow(anchor: .vocabulary) {
                VStack(alignment: .leading, spacing: 12) {
                    // Inline, not a sheet: adding five words should be five
                    // keystrokes and no dismissals, so the field stays open and
                    // focused after Add. It sits above the words, so a long
                    // list never pushes it out of view.
                    if isAddingWord {
                        HStack(spacing: 8) {
                            TextField("Word or phrase", text: $vocabularyDraft)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 260)
                                .focused($isWordFieldFocused)
                                .onSubmit(addTerm)
                                .onExitCommand(perform: stopAddingWords)
                                .onAppear { isWordFieldFocused = true }

                            Button("Add", action: addTerm)
                                .disabled(vocabularyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            Button("Done", action: stopAddingWords)
                                .buttonStyle(.borderless)
                        }
                        .transition(.opacity)
                    } else {
                        Button("Add a Word") {
                            withAnimation(SettingsMotion.curve(reduceMotion: reduceMotion)) {
                                isAddingWord = true
                            }
                        }
                        .transition(.opacity)
                    }

                    if !appState.vocabularyTerms.isEmpty {
                        // A word that is added or removed scales in or out where
                        // it sits, and the words after it move to their places.
                        FlowLayout(spacing: 6) {
                            ForEach(appState.vocabularyTerms, id: \.self) { term in
                                StylePageVocabularyTag(
                                    term: term,
                                    isAutoLearned: appState.isAutoLearnedVocabularyTerm(term)
                                ) {
                                    withAnimation(SettingsMotion.curve(reduceMotion: reduceMotion)) {
                                        appState.removeVocabularyTerm(term)
                                    }
                                }
                                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                            }
                        }
                    }
                }
            }
        } footer: {
            if let note = SettingsRowID.vocabulary.info {
                Text(note)
            }
        }
    }

    private func addTerm() {
        withAnimation(SettingsMotion.curve(reduceMotion: reduceMotion)) {
            appState.addVocabularyTerm(vocabularyDraft)
        }
        vocabularyDraft = ""
        isWordFieldFocused = true
    }

    private func stopAddingWords() {
        vocabularyDraft = ""
        withAnimation(SettingsMotion.curve(reduceMotion: reduceMotion)) {
            isAddingWord = false
        }
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
        appState.activeMagicFormatPrompt == appState.activeMagicFormatEngine.defaultPrompt
    }

}

enum MagicFormatSheetRoute: String, Identifiable {
    case engine
    case instructions
    case perApp

    var id: String { rawValue }
}
