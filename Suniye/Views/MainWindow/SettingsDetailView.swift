import SwiftUI

struct SettingsDetailView: View {
    @Bindable var appState: AppState
    @State private var pendingAPIKey = ""
    @State private var pendingBaseSystemPrompt = ""
    @State private var pendingUserSystemPrompt = ""
    @State private var pendingKeywordsRaw = ""

    var body: some View {
        let modelActionTitle = appState.isModelInstalled ? "Re-download Model" : "Download Model"

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox("Model") {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(appState.isModelInstalled ? "Model installed" : "Model missing", systemImage: appState.isModelInstalled ? "checkmark.seal" : "exclamationmark.triangle")
                            .foregroundStyle(appState.isModelInstalled ? Color.primary : Color.orange)

                        Text("Model: sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        if appState.phase == .downloadingModel {
                            ProgressView(value: appState.downloadProgress)
                            Text("\(Int(appState.downloadProgress * 100))%")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        if let error = appState.lastError, appState.phase == .error {
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundStyle(.red)
                        }

                        HStack(spacing: 10) {
                            Button(modelActionTitle) {
                                appState.startModelDownload()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(appState.phase == .downloadingModel || appState.phase == .recording || appState.phase == .transcribing)
                            .accessibilityLabel(Text(modelActionTitle))

                            Button("Open Model Folder") {
                                appState.openModelFolder()
                            }
                            .disabled(!appState.isModelInstalled)
                            .accessibilityLabel(Text("Open Model Folder"))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Permissions") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(appState.hasMicPermission ? "Microphone granted" : "Microphone missing", systemImage: "mic")
                        Label(appState.hasAccessibilityPermission ? "Accessibility granted" : "Accessibility missing", systemImage: "accessibility")

                        HStack(spacing: 10) {
                            Button("Request Microphone") {
                                Task {
                                    await appState.refreshPermissions(requestMicrophone: true)
                                }
                            }
                            .buttonStyle(.bordered)

                            Button("Request Accessibility") {
                                appState.requestAccessibilityPermission()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("LLM Post-Processing") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Enable LLM polishing", isOn: $appState.llmEnabled)

                        HStack(spacing: 10) {
                            Text("Model")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 84, alignment: .leading)

                            Picker("Model", selection: $appState.llmSelectedModelPreset) {
                                ForEach(LLMModelPreset.allCases, id: \.self) { preset in
                                    Text(preset.displayName).tag(preset)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 220)
                        }

                        if appState.llmSelectedModelPreset == .custom {
                            TextField("openrouter/model-id", text: $appState.llmCustomModelId)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel(Text("Custom OpenRouter Model ID"))
                        }

                        Text("Active model: \(appState.llmSelectedModelIdPreview)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Timeout")
                                    .font(.system(size: 12, weight: .semibold))
                                Spacer()
                                Text("\(appState.llmTimeoutSeconds, specifier: "%.1f")s")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 10) {
                                Slider(
                                    value: $appState.llmTimeoutSeconds,
                                    in: LLMDefaults.minTimeoutSeconds ... LLMDefaults.maxTimeoutSeconds,
                                    step: 0.5
                                )

                                Stepper(
                                    value: $appState.llmTimeoutSeconds,
                                    in: LLMDefaults.minTimeoutSeconds ... LLMDefaults.maxTimeoutSeconds,
                                    step: 0.5
                                ) {
                                    EmptyView()
                                }
                                .labelsHidden()
                            }
                        }

                        Stepper(
                            value: $appState.llmMaxTokens,
                            in: LLMDefaults.minMaxTokens ... LLMDefaults.maxMaxTokens,
                            step: 16
                        ) {
                            Text("Max tokens: \(appState.llmMaxTokens)")
                                .font(.system(size: 12, weight: .semibold))
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text(appState.llmKeyStatusText)
                                .font(.system(size: 12, weight: .semibold))
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

                            if let keyError = appState.llmKeyOperationError {
                                Text(keyError)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.red)
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Base prompt (always included)")
                                .font(.system(size: 12, weight: .semibold))
                            TextEditor(text: $pendingBaseSystemPrompt)
                                .font(.system(size: 12))
                                .frame(minHeight: 88)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                )
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("User prompt (your use case)")
                                .font(.system(size: 12, weight: .semibold))
                            TextEditor(text: $pendingUserSystemPrompt)
                                .font(.system(size: 12))
                                .frame(minHeight: 88)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                )
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Common keywords (comma or newline separated)")
                                .font(.system(size: 12, weight: .semibold))
                            TextEditor(text: $pendingKeywordsRaw)
                                .font(.system(size: 12))
                                .frame(minHeight: 68)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                )
                        }

                        HStack(spacing: 10) {
                            Button("Save Prompt Layers") {
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
                                .font(.system(size: 12))
                                .foregroundStyle(hasUnsavedLLMTextChanges ? Color.orange : Color.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(24)
        }
        .onAppear {
            pendingBaseSystemPrompt = appState.llmBaseSystemPrompt
            pendingUserSystemPrompt = appState.llmSystemPrompt
            pendingKeywordsRaw = appState.llmKeywordsRaw
            AppLogger.shared.log(.info, "settings view appeared model_installed=\(appState.isModelInstalled)")
            AppLogger.shared.log(.info, "settings llm controls rendered model=\(appState.llmSelectedModelIdPreview)")
        }
    }

    private var hasUnsavedLLMTextChanges: Bool {
        pendingBaseSystemPrompt != appState.llmBaseSystemPrompt ||
            pendingUserSystemPrompt != appState.llmSystemPrompt ||
            pendingKeywordsRaw != appState.llmKeywordsRaw
    }
}
