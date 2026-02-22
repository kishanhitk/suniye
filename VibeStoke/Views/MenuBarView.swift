import SwiftUI

struct MenuBarView: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(statusTitle, systemImage: statusIcon)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(appState.phase.rawValue.capitalized)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if let error = appState.lastError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            } else {
                Text(appState.statusText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            if appState.phase == .downloadingModel {
                ProgressView(value: appState.downloadProgress)
            }

            Divider()

            HStack(spacing: 8) {
                Button("Start") { appState.startRecordingFromUI() }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.phase != .ready)

                Button("Stop") { appState.stopRecordingFromUI() }
                    .buttonStyle(.bordered)
                    .disabled(appState.phase != .recording)
            }

            Button("Open VibeStoke") { appState.openMainWindow() }

            if appState.phase == .needsModel || appState.showOnboarding {
                Button("Download Model") { appState.startModelDownload() }
            }

            Divider()

            Button("Quit VibeStoke") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(14)
    }

    private var statusTitle: String {
        switch appState.phase {
        case .ready: return "Ready"
        case .recording: return "Listening"
        case .transcribing: return "Transcribing"
        case .needsModel: return "Model needed"
        case .downloadingModel: return "Downloading"
        case .loading: return "Loading"
        case .error: return "Error"
        }
    }

    private var statusIcon: String {
        appState.phase == .recording ? "mic.fill" : "mic"
    }
}
