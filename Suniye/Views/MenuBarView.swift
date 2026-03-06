import SwiftUI

struct MenuBarView: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(statusTitle, systemImage: statusIcon)
                    .font(AppTypography.ui(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText)
                Spacer()
                Text(appState.phase.rawValue.capitalized)
                    .font(AppTypography.mono(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.secondaryText)
            }

            if let error = appState.lastError {
                Text(error)
                    .font(AppTypography.ui(size: 12, weight: .medium))
                    .foregroundStyle(.red)
            } else {
                Text(appState.statusText)
                    .font(AppTypography.ui(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.secondaryText)
            }

            if appState.phase == .downloadingModel {
                ProgressView(value: appState.downloadProgress)
            }

            Divider().overlay(AppTheme.border)

            HStack(spacing: 8) {
                Button("Start") { appState.startRecordingFromUI() }
                    .buttonStyle(PrimaryDarkButtonStyle())
                    .disabled(appState.phase != .ready)

                Button("Stop") { appState.stopRecordingFromUI() }
                    .buttonStyle(SoftPillButtonStyle())
                    .disabled(appState.phase != .recording)
            }

            Button("Open Home") { appState.openMainWindow() }
                .buttonStyle(SoftPillButtonStyle())

            if appState.phase == .needsModel || appState.showOnboarding {
                Button("Download local model") { appState.startModelDownload() }
                    .buttonStyle(SoftPillButtonStyle())
            }

            Divider().overlay(AppTheme.border)

            Button("Quit Suniye") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(SoftPillButtonStyle())
        }
        .padding(14)
        .background(AppTheme.panelBackground)
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
