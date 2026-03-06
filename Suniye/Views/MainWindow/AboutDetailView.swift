import SwiftUI

struct AboutDetailView: View {
    @Bindable var appState: AppState

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Suniye"
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

            GroupBox("LLM") {
                VStack(alignment: .leading, spacing: 8) {
                    Label(appState.llmEnabled ? "LLM polishing enabled" : "LLM polishing disabled", systemImage: appState.llmEnabled ? "wand.and.stars" : "wand.and.stars.inverse")
                    Label("Model: \(appState.llmSelectedModelIdPreview)", systemImage: "brain")
                    Label(appState.hasOpenRouterAPIKey ? "OpenRouter API key saved" : "OpenRouter API key missing", systemImage: appState.hasOpenRouterAPIKey ? "key.fill" : "key")
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
