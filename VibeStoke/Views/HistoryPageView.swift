import SwiftUI

struct HistoryPageView: View {
    @Bindable var appState: AppState
    @State private var searchText = ""
    @State private var showClearConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("History")
                    .font(AppTypography.ui(size: 32, weight: .bold))
                Spacer()
                Button("Clear All", role: .destructive) {
                    showClearConfirm = true
                }
                .disabled(appState.historyEntries.isEmpty)
            }

            TextField("Search history", text: $searchText)
                .textFieldStyle(.roundedBorder)

            if let historyActionMessage = appState.historyActionMessage {
                Text(historyActionMessage)
                    .font(AppTypography.ui(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            let entries = appState.filteredHistoryEntries(searchText: searchText)
            if entries.isEmpty {
                Spacer()
                Text("No history entries")
                    .font(AppTypography.ui(size: 14))
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(entries) { entry in
                    VStack(alignment: .leading, spacing: 7) {
                        Text(entry.text)
                            .font(AppTypography.ui(size: 13))
                            .lineLimit(4)

                        HStack {
                            Text("\(formatDateTime(entry.createdAt)) • \(entry.wordCount) words • \(String(format: "%.1fs", entry.durationSeconds))")
                                .font(AppTypography.mono(size: 11))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Copy") {
                                appState.copyHistoryEntryText(entry.text)
                            }
                            .buttonStyle(.bordered)

                            Button("Delete", role: .destructive) {
                                appState.deleteHistoryEntry(id: entry.id)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .listStyle(.inset)
            }
        }
        .padding(22)
        .confirmationDialog("Clear all history?", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Clear All", role: .destructive) {
                appState.clearHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }
}
