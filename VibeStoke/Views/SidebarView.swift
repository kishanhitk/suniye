import SwiftUI

struct SidebarView: View {
    @Bindable var appState: AppState

    var body: some View {
        List {
            Section("Status") {
                Label(appState.phase.rawValue.capitalized, systemImage: "waveform")
                Label(appState.hasMicPermission ? "Mic Granted" : "Mic Missing", systemImage: "mic")
                Label(appState.hasAccessibilityPermission ? "Accessibility Granted" : "Accessibility Missing", systemImage: "accessibility")
            }

            Section("Settings") {
                Label("Hotkey: fn/globe", systemImage: "keyboard")
                Label("Audio: default input", systemImage: "waveform.and.mic")
                Label("Overlay animation: enabled", systemImage: "sparkles")
            }

            Section("About") {
                Label("Parakeet TDT 0.6B INT8", systemImage: "cpu")
                Label("sherpa-onnx C API", systemImage: "link")
            }
        }
        .listStyle(.sidebar)
    }
}
