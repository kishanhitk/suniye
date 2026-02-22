import SwiftUI

struct DashboardPageView: View {
    @Bindable var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Dashboard")
                    .font(AppTypography.ui(size: 34, weight: .bold))

                if appState.showOnboarding {
                    OnboardingView(appState: appState)
                        .frame(minHeight: 380)
                        .background(AppTheme.subtleBackground, in: RoundedRectangle(cornerRadius: 12))
                }

                HStack(spacing: 14) {
                    StatCard(title: "Sessions", value: "\(appState.sessionCount)")
                    StatCard(title: "Words", value: "\(appState.wordsTranscribed)")
                    StatCard(title: "Minutes", value: String(format: "%.1f", appState.totalDictationSeconds / 60))
                }

                HStack(spacing: 10) {
                    Button("Start Recording") {
                        appState.startRecordingFromUI()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.phase != .ready)

                    Button("Stop Recording") {
                        appState.stopRecordingFromUI()
                    }
                    .buttonStyle(.bordered)
                    .disabled(appState.phase != .recording)

                    Button("Open Model Folder") {
                        appState.openModelFolder()
                    }
                    .buttonStyle(.bordered)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Recent Activity")
                        .font(AppTypography.ui(size: 18, weight: .semibold))

                    let recent = Array(appState.historyEntries.prefix(10))
                    if recent.isEmpty {
                        Text("No transcription sessions yet")
                            .font(AppTypography.ui(size: 13))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(recent) { entry in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(entry.text)
                                    .font(AppTypography.ui(size: 13))
                                    .lineLimit(3)
                                Text("\(formatDateTime(entry.createdAt))  •  \(entry.wordCount) words")
                                    .font(AppTypography.mono(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(AppTheme.subtleBackground, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
            .padding(22)
        }
    }
}

private struct StatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppTypography.ui(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(AppTypography.mono(size: 30, weight: .bold))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 14))
    }
}
