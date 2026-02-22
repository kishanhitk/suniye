import AppKit
import SwiftUI

struct MainWindowView: View {
    @Bindable var appState: AppState
    @State private var selection: MainWindowSection = CommandLine.arguments.contains("--open-settings") ? .settings : .stats

    var body: some View {
        NavigationSplitView {
            SidebarView(appState: appState, selection: $selection)
                .navigationSplitViewColumnWidth(min: 220, ideal: 240)
        } detail: {
            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .navigationTitle(selection.title)
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection {
        case .stats:
            statsView
        case .settings:
            SettingsDetailView(appState: appState)
        case .about:
            AboutDetailView(appState: appState)
        }
    }

    private var statsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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
                        ForEach(Array(appState.recentResults.enumerated()), id: \.offset) { index, item in
                            RecentActivityRow(
                                text: item,
                                onCopy: {
                                    let pasteboard = NSPasteboard.general
                                    pasteboard.clearContents()
                                    pasteboard.setString(item, forType: .string)
                                },
                                onDelete: {
                                    appState.recentResults.remove(at: index)
                                }
                            )
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}

private struct RecentActivityRow: View {
    let text: String
    let onCopy: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Spacer()

                Button("Copy") {
                    onCopy()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Delete") {
                    onDelete()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
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

private struct AboutDetailView: View {
    @Bindable var appState: AppState

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "VibeStoke"
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }

    private var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "Unknown"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox("Application") {
                VStack(alignment: .leading, spacing: 8) {
                    Label(appName, systemImage: "app")
                    Label("Version \(version) (\(build))", systemImage: "number")
                    Label(bundleIdentifier, systemImage: "shippingbox")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Engine") {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Local-only offline transcription", systemImage: "lock.shield")
                    Label("Model: sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8", systemImage: "cpu")
                    Label("Inference: sherpa-onnx C API + ONNX Runtime", systemImage: "link")
                    Label("Hotkey: Hold Fn/Globe to dictate", systemImage: "keyboard")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Current Device Status") {
                VStack(alignment: .leading, spacing: 8) {
                    Label(appState.isModelInstalled ? "Model installed" : "Model missing", systemImage: appState.isModelInstalled ? "checkmark.seal" : "exclamationmark.triangle")
                    Label(appState.hasMicPermission ? "Microphone granted" : "Microphone not granted", systemImage: "mic")
                    Label(appState.hasAccessibilityPermission ? "Accessibility granted" : "Accessibility not granted", systemImage: "accessibility")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
