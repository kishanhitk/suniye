import SwiftUI

struct ModelPageView: View {
    @Bindable var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Model")
                    .font(AppTypography.ui(size: 32, weight: .bold))

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(appState.isModelInstalled ? "Model installed" : "Model missing", systemImage: appState.isModelInstalled ? "checkmark.seal" : "exclamationmark.triangle")
                            .foregroundStyle(appState.isModelInstalled ? Color.primary : Color.orange)

                        Text("Model: sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8")
                            .font(AppTypography.mono(size: 12))
                            .foregroundStyle(.secondary)

                        if appState.phase == .downloadingModel {
                            ProgressView(value: appState.downloadProgress)
                            Text("\(Int(appState.downloadProgress * 100))%")
                                .font(AppTypography.mono(size: 12))
                                .foregroundStyle(.secondary)
                        }

                        if let lastError = appState.lastError, appState.phase == .error {
                            Text(lastError)
                                .font(AppTypography.ui(size: 12))
                                .foregroundStyle(.red)
                        }

                        if let diagnostics = appState.modelDiagnostics {
                            Text("Disk usage: \(formatByteCount(diagnostics.diskUsageBytes))")
                                .font(AppTypography.ui(size: 12))
                                .foregroundStyle(.secondary)
                            Text(diagnostics.modelDirectoryPath)
                                .font(AppTypography.mono(size: 11))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        } else if let modelDiagnosticsError = appState.modelDiagnosticsError {
                            Text(modelDiagnosticsError)
                                .font(AppTypography.ui(size: 12))
                                .foregroundStyle(.red)
                        }

                        HStack(spacing: 10) {
                            Button(appState.isModelInstalled ? "Re-download Model" : "Download Model") {
                                appState.startModelDownload()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(appState.phase == .downloadingModel || appState.phase == .recording || appState.phase == .transcribing)

                            Button("Open Model Folder") {
                                appState.openModelFolder()
                            }
                            .buttonStyle(.bordered)
                            .disabled(!appState.isModelInstalled)

                            Button("Rescan") {
                                appState.refreshModelDiagnostics()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text("Status")
                }

                GroupBox {
                    if let diagnostics = appState.modelDiagnostics {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(diagnostics.requiredFiles) { file in
                                HStack {
                                    Label(file.fileName, systemImage: file.exists ? "checkmark.circle.fill" : "xmark.circle")
                                        .foregroundStyle(file.exists ? Color.primary : Color.orange)
                                    Spacer()
                                    Text(formatByteCount(file.sizeBytes))
                                        .font(AppTypography.mono(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } else {
                        Text("Diagnostics unavailable")
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    Text("Required Files")
                }
            }
            .padding(22)
        }
    }
}
