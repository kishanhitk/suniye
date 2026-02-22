import SwiftUI

struct MainWindowView: View {
    @Bindable var appState: AppState
    @State private var selection: MainWindowSection = CommandLine.arguments.contains("--open-settings") ? .settings : .stats

    var body: some View {
        NavigationSplitView {
            SidebarView(appState: appState, selection: $selection)
        } detail: {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    topNavButton(title: "Stats", section: .stats)
                    topNavButton(title: "Settings", section: .settings)
                    topNavButton(title: "About", section: .about)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider()

                switch selection {
                case .stats:
                    statsView
                case .settings:
                    SettingsDetailView(appState: appState)
                case .about:
                    AboutDetailView()
                }
            }
        }
    }

    private func topNavButton(title: String, section: MainWindowSection) -> some View {
        Button(title) {
            selection = section
        }
        .buttonStyle(.bordered)
        .tint(selection == section ? .gray : nil)
        .accessibilityLabel(Text(title))
    }

    private var statsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("VibeStoke")
                    .font(.system(size: 36, weight: .bold))

                if appState.showOnboarding {
                    OnboardingView(appState: appState)
                        .frame(minHeight: 380)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                HStack(spacing: 16) {
                    StatCard(title: "Sessions", value: "\(appState.sessionCount)")
                    StatCard(title: "Words", value: "\(appState.wordsTranscribed)")
                    StatCard(title: "Minutes", value: String(format: "%.1f", appState.totalDictationSeconds / 60))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Recent Activity")
                        .font(.system(size: 18, weight: .semibold))
                    if appState.recentResults.isEmpty {
                        Text("No transcription sessions yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(appState.recentResults.enumerated()), id: \.offset) { _, item in
                            Text(item)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}

private struct StatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .monospaced))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct SettingsDetailView: View {
    @Bindable var appState: AppState
    @State private var pendingAPIKey = ""

    var body: some View {
        let modelActionTitle = appState.isModelInstalled ? "Re-download Model" : "Download Model"

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Settings")
                    .font(.system(size: 32, weight: .bold))

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
                            Text("System prompt")
                                .font(.system(size: 12, weight: .semibold))
                            TextEditor(text: $appState.llmSystemPrompt)
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
                            TextEditor(text: $appState.llmKeywordsRaw)
                                .font(.system(size: 12))
                                .frame(minHeight: 68)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(24)
        }
        .onAppear {
            AppLogger.shared.log(.info, "settings view appeared model_installed=\(appState.isModelInstalled)")
            AppLogger.shared.log(.info, "settings llm controls rendered model=\(appState.llmSelectedModelIdPreview)")
        }
    }
}

private struct AboutDetailView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("About")
                .font(.system(size: 32, weight: .bold))
            Label("Parakeet TDT 0.6B INT8", systemImage: "cpu")
            Label("sherpa-onnx C API", systemImage: "link")
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
