import AppKit
import SwiftUI

struct StatsDetailView: View {
    @Bindable var appState: AppState
    let onOpenSettings: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !appState.attentionItems.isEmpty {
                    AttentionBanner(
                        items: appState.attentionItems,
                        onOpenSettings: onOpenSettings
                    )
                }

                if appState.showOnboarding {
                    OnboardingView(appState: appState)
                        .frame(minHeight: 380)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

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
                        ForEach(appState.recentResults) { item in
                            RecentActivityRow(
                                result: item,
                                onCopy: {
                                    let pasteboard = NSPasteboard.general
                                    pasteboard.clearContents()
                                    pasteboard.setString(item.text, forType: .string)
                                },
                                onDelete: {
                                    appState.recentResults.removeAll(where: { $0.id == item.id })
                                }
                            )
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}
