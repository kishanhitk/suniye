import SwiftUI

struct ModelDownloadView: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Download Parakeet Model")
                .font(AppTypography.pageTitle)

            Text("Required model: sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8")
                .font(AppTypography.body)
                .foregroundStyle(.secondary)

            if appState.phase == .downloadingModel {
                ProgressView(value: appState.downloadProgress)
                Text("\(Int(appState.downloadProgress * 100))%")
                    .font(Font.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if let error = appState.lastError, appState.phase == .error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(AppTypography.caption)
            }

            Spacer()

            HStack(spacing: 8) {
                Button("Download") {
                    appState.startModelDownload()
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.phase == .downloadingModel)

                if appState.phase == .ready {
                    Button("Done") {
                        appState.showOnboarding = false
                    }
                }
            }
        }
        .padding(20)
    }
}
