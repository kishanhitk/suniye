import SwiftUI

struct LLMPolishPageView: View {
    @Bindable var appState: AppState
    @State private var pendingAPIKey = ""
    @State private var pendingBaseSystemPrompt = ""
    @State private var pendingUserSystemPrompt = ""
    @State private var pendingKeywordsRaw = ""
    @FocusState private var isAPIKeyFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Style")
                    .font(AppTypography.ui(size: 48, weight: .bold))
                    .foregroundStyle(AppTheme.primaryText)

                AppShellCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Make output sound like you")
                            .font(AppTypography.serif(size: 56))
                            .foregroundStyle(AppTheme.primaryText)

                        Text("Tune model, prompts, and keywords for your writing style.")
                            .font(AppTypography.ui(size: 23, weight: .medium))
                            .foregroundStyle(AppTheme.primaryText)

                        HStack(spacing: 14) {
                            Toggle(isOn: $appState.llmEnabled) {
                                Text("Enable style polish")
                                    .font(AppTypography.ui(size: 16, weight: .semibold))
                                    .foregroundStyle(AppTheme.primaryText)
                            }
                            .toggleStyle(.switch)

                            Spacer()

                            ModelPresetMenuField(selection: $appState.llmSelectedModelPreset)
                                .frame(width: 292)
                        }

                        if appState.llmSelectedModelPreset == .custom {
                            FormTextField("openrouter/model-id", text: $appState.llmCustomModelId)
                        }

                        Text("Active model: \(appState.llmSelectedModelIdPreview)")
                            .font(AppTypography.mono(size: 12))
                            .foregroundStyle(AppTheme.secondaryText)

                        if !appState.llmVocabulary.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(Array(appState.llmVocabulary.prefix(10)), id: \.self) { term in
                                        TagChip(text: term)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    .padding(22)
                    .background(AppTheme.warmCardBackground)
                }

                AppShellCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Advanced")
                            .font(AppTypography.ui(size: 24, weight: .semibold))
                            .foregroundStyle(AppTheme.primaryText)

                        SettingsRow(title: "OpenRouter key") {
                            HStack(spacing: 8) {
                                FormSecureField(apiKeyFieldPlaceholder, text: $pendingAPIKey, isFocused: $isAPIKeyFieldFocused)
                                    .frame(width: 340)
                                Button("Clear") {
                                    appState.clearOpenRouterAPIKey()
                                    pendingAPIKey = ""
                                }
                                .buttonStyle(SoftPillButtonStyle())
                                .disabled(!appState.hasOpenRouterAPIKey && pendingAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }

                        Divider().overlay(AppTheme.border)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Base prompt")
                                .font(AppTypography.ui(size: 16, weight: .semibold))
                            FormTextEditor(text: $pendingBaseSystemPrompt, minHeight: 100)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("User prompt")
                                .font(AppTypography.ui(size: 16, weight: .semibold))
                            FormTextEditor(text: $pendingUserSystemPrompt, minHeight: 100)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Keywords")
                                .font(AppTypography.ui(size: 16, weight: .semibold))
                            FormTextEditor(text: $pendingKeywordsRaw, minHeight: 86)
                        }

                        HStack(spacing: 10) {
                            Button("Save") {
                                appState.llmBaseSystemPrompt = pendingBaseSystemPrompt
                                appState.llmSystemPrompt = pendingUserSystemPrompt
                                appState.llmKeywordsRaw = pendingKeywordsRaw
                                AppLogger.shared.log(.info, "llm prompt layers saved")
                            }
                            .buttonStyle(PrimaryDarkButtonStyle())
                            .disabled(!hasUnsavedLLMTextChanges)

                            Button("Reset base") {
                                pendingBaseSystemPrompt = LLMDefaults.defaultBaseSystemPrompt
                            }
                            .buttonStyle(SoftPillButtonStyle())
                            .disabled(pendingBaseSystemPrompt == LLMDefaults.defaultBaseSystemPrompt)

                            Text(hasUnsavedLLMTextChanges ? "Unsaved" : "Saved")
                                .font(AppTypography.ui(size: 13, weight: .semibold))
                                .foregroundStyle(hasUnsavedLLMTextChanges ? AppTheme.primaryText : AppTheme.secondaryText)
                        }

                        if let llmKeyOperationError = appState.llmKeyOperationError {
                            Text(llmKeyOperationError)
                                .font(AppTypography.ui(size: 13, weight: .semibold))
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(18)
                }
            }
            .padding(26)
            .frame(maxWidth: 980, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .onAppear {
            pendingAPIKey = ""
            pendingBaseSystemPrompt = appState.llmBaseSystemPrompt
            pendingUserSystemPrompt = appState.llmSystemPrompt
            pendingKeywordsRaw = appState.llmKeywordsRaw
        }
        .onChange(of: isAPIKeyFieldFocused) { _, isFocused in
            if !isFocused {
                savePendingAPIKeyIfNeeded()
            }
        }
    }

    private var hasUnsavedLLMTextChanges: Bool {
        pendingBaseSystemPrompt != appState.llmBaseSystemPrompt ||
            pendingUserSystemPrompt != appState.llmSystemPrompt ||
            pendingKeywordsRaw != appState.llmKeywordsRaw
    }

    private var apiKeyFieldPlaceholder: String {
        if appState.hasOpenRouterAPIKey && pendingAPIKey.isEmpty {
            return appState.llmMaskedAPIKey
        }
        return "API key"
    }

    private func savePendingAPIKeyIfNeeded() {
        let normalized = pendingAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return
        }

        appState.saveOpenRouterAPIKey(normalized)
        if appState.llmKeyOperationError == nil {
            pendingAPIKey = ""
        }
    }
}

private struct FormFieldSurface<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppLayout.chipCornerRadius, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppLayout.chipCornerRadius, style: .continuous)
                    .stroke(AppTheme.border.opacity(1.2), lineWidth: 1)
            )
    }
}

private struct FormTextField: View {
    let placeholder: String
    @Binding var text: String

    init(_ placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        _text = text
    }

    var body: some View {
        FormFieldSurface {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(AppTypography.ui(size: 15, weight: .medium))
                .foregroundStyle(AppTheme.primaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
        }
    }
}

private struct FormSecureField: View {
    let placeholder: String
    @Binding var text: String
    private var isFocused: FocusState<Bool>.Binding?

    init(_ placeholder: String, text: Binding<String>, isFocused: FocusState<Bool>.Binding? = nil) {
        self.placeholder = placeholder
        _text = text
        self.isFocused = isFocused
    }

    var body: some View {
        FormFieldSurface {
            SecureField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .submitLabel(.done)
                .applyIf(isFocused != nil) { view in
                    view.focused(isFocused!)
                }
                .font(AppTypography.ui(size: 15, weight: .medium))
                .foregroundStyle(AppTheme.primaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
        }
    }
}

private struct FormTextEditor: View {
    @Binding var text: String
    let minHeight: CGFloat

    var body: some View {
        FormFieldSurface {
            TextEditor(text: $text)
                .font(AppTypography.ui(size: 15))
                .foregroundStyle(AppTheme.primaryText)
                .frame(minHeight: minHeight)
                .scrollContentBackground(.hidden)
                .padding(10)
        }
    }
}

private struct ModelPresetMenuField: View {
    @Binding var selection: LLMModelPreset

    var body: some View {
        Menu {
            ForEach(LLMModelPreset.allCases, id: \.self) { preset in
                Button {
                    selection = preset
                } label: {
                    HStack {
                        Text(preset.displayName)
                        if preset == selection {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            FormFieldSurface {
                HStack(spacing: 12) {
                    Text("Model")
                        .font(AppTypography.ui(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                    Spacer(minLength: 8)
                    Text(selection.displayName)
                        .font(AppTypography.ui(size: 15, weight: .medium))
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func applyIf<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
