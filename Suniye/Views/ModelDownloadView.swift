import SwiftUI

struct ModelDownloadView: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Download Parakeet Model")
                .font(.system(size: 28, weight: .bold))

            Text("Required model: sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8")
                .foregroundStyle(.secondary)

            if appState.phase == .downloadingModel {
                ProgressView(value: appState.downloadProgress)
                Text("\(Int(appState.downloadProgress * 100))%")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if let error = appState.lastError, appState.phase == .error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.system(size: 12))
            }

            Spacer()

            HStack {
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
        .padding(28)
    }
}
