import SwiftUI

struct LLMPolishPageView: View {
    @Bindable var appState: AppState
    @State private var pendingAPIKey = ""
    @State private var pendingBaseSystemPrompt = ""
    @State private var pendingUserSystemPrompt = ""
    @State private var pendingKeywordsRaw = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("LLM Polish")
                    .font(AppTypography.ui(size: 32, weight: .bold))

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Enable LLM polishing", isOn: $appState.llmEnabled)

                        HStack(spacing: 10) {
                            Text("Model")
                                .font(AppTypography.ui(size: 12, weight: .semibold))
                                .frame(width: 84, alignment: .leading)

                            Picker("Model", selection: $appState.llmSelectedModelPreset) {
                                ForEach(LLMModelPreset.allCases, id: \.self) { preset in
                                    Text(preset.displayName).tag(preset)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 240)
                        }

                        if appState.llmSelectedModelPreset == .custom {
                            TextField("openrouter/model-id", text: $appState.llmCustomModelId)
                                .textFieldStyle(.roundedBorder)
                        }

                        Text("Active model: \(appState.llmSelectedModelIdPreview)")
                            .font(AppTypography.mono(size: 12))
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(appState.llmKeyStatusText)
                                .font(AppTypography.ui(size: 12, weight: .semibold))
                                .foregroundStyle(appState.hasOpenRouterAPIKey ? Color.primary : Color.orange)

                            HStack(spacing: 10) {
                                SecureField("OpenRouter API key", text: $pendingAPIKey)
                                    .textFieldStyle(.roundedBorder)

                                Button(appState.hasOpenRouterAPIKey ? "Replace Key" : "Save Key") {
                                    appState.saveOpenRouterAPIKey(pendingAPIKey)
                                    pendingAPIKey = ""
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Clear Key") {
                                    appState.clearOpenRouterAPIKey()
                                    pendingAPIKey = ""
                                }
                                .buttonStyle(.bordered)
                                .disabled(!appState.hasOpenRouterAPIKey)
                            }

                            if let llmKeyOperationError = appState.llmKeyOperationError {
                                Text(llmKeyOperationError)
                                    .font(AppTypography.ui(size: 12))
                                    .foregroundStyle(.red)
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Base prompt")
                                .font(AppTypography.ui(size: 12, weight: .semibold))
                            TextEditor(text: $pendingBaseSystemPrompt)
                                .font(AppTypography.ui(size: 12))
                                .frame(minHeight: 90)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(AppTheme.border, lineWidth: 1)
                                )
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("User prompt")
                                .font(AppTypography.ui(size: 12, weight: .semibold))
                            TextEditor(text: $pendingUserSystemPrompt)
                                .font(AppTypography.ui(size: 12))
                                .frame(minHeight: 90)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(AppTheme.border, lineWidth: 1)
                                )
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Keywords (comma or newline separated)")
                                .font(AppTypography.ui(size: 12, weight: .semibold))
                            TextEditor(text: $pendingKeywordsRaw)
                                .font(AppTypography.ui(size: 12))
                                .frame(minHeight: 80)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(AppTheme.border, lineWidth: 1)
                                )
                        }

                        HStack(spacing: 10) {
                            Button("Save") {
                                appState.llmBaseSystemPrompt = pendingBaseSystemPrompt
                                appState.llmSystemPrompt = pendingUserSystemPrompt
                                appState.llmKeywordsRaw = pendingKeywordsRaw
                                AppLogger.shared.log(.info, "llm prompt layers saved")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!hasUnsavedLLMTextChanges)

                            Button("Reset Base Prompt") {
                                pendingBaseSystemPrompt = LLMDefaults.defaultBaseSystemPrompt
                            }
                            .buttonStyle(.bordered)
                            .disabled(pendingBaseSystemPrompt == LLMDefaults.defaultBaseSystemPrompt)

                            Text(hasUnsavedLLMTextChanges ? "Unsaved changes" : "Saved")
                                .font(AppTypography.ui(size: 12))
                                .foregroundStyle(hasUnsavedLLMTextChanges ? Color.orange : Color.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text("Configuration")
                }
            }
            .padding(22)
        }
        .onAppear {
            pendingBaseSystemPrompt = appState.llmBaseSystemPrompt
            pendingUserSystemPrompt = appState.llmSystemPrompt
            pendingKeywordsRaw = appState.llmKeywordsRaw
            AppLogger.shared.log(.info, "llm settings view appeared model=\(appState.llmSelectedModelIdPreview)")
        }
    }

    private var hasUnsavedLLMTextChanges: Bool {
        pendingBaseSystemPrompt != appState.llmBaseSystemPrompt ||
            pendingUserSystemPrompt != appState.llmSystemPrompt ||
            pendingKeywordsRaw != appState.llmKeywordsRaw
    }
}
