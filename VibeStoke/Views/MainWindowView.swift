import SwiftUI

struct MainWindowView: View {
    @Bindable var appState: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView(appState: appState)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("VibeStoke")
                        .font(.system(size: 36, weight: .bold))

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
                            ForEach(Array(appState.recentResults.enumerated()), id: \.offset) { _, item in
                                Text(item)
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                }
                .padding(24)
            }
        }
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
