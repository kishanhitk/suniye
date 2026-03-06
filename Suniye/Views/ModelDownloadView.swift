import SwiftUI

struct ModelDownloadView: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Download local model")
                .font(AppTypography.ui(size: 42, weight: .bold))
                .foregroundStyle(AppTheme.primaryText)

            Text("Required model: sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8")
                .font(AppTypography.ui(size: 18, weight: .medium))
                .foregroundStyle(AppTheme.secondaryText)

            AppShellCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("This enables offline transcription on your machine.")
                        .font(AppTypography.ui(size: 18, weight: .medium))
                        .foregroundStyle(AppTheme.primaryText)

                    if appState.phase == .downloadingModel {
                        ProgressView(value: appState.downloadProgress)
                        Text("\(Int(appState.downloadProgress * 100))%")
                            .font(AppTypography.mono(size: 13, weight: .medium))
                            .foregroundStyle(AppTheme.secondaryText)
                    }

                    if let error = appState.lastError, appState.phase == .error {
                        Text(error)
                            .font(AppTypography.ui(size: 13, weight: .semibold))
                            .foregroundStyle(.red)
                    }
                }
                .padding(16)
            }

            Spacer()

            HStack(spacing: 10) {
                Button(appState.isModelInstalled ? "Re-download" : "Download") {
                    appState.startModelDownload()
                }
                .buttonStyle(PrimaryDarkButtonStyle())
                .disabled(appState.phase == .downloadingModel)

                if appState.phase == .ready {
                    Button("Done") {
                        appState.showOnboarding = false
                    }
                    .buttonStyle(SoftPillButtonStyle())
                }
            }
        }
        .padding(28)
        .background(AppTheme.panelBackground)
    }
}
