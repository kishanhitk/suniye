import SwiftUI

struct HistoryPageView: View {
    @Bindable var appState: AppState
    @State private var searchText = ""
    @State private var showClearConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Notes")
                        .font(AppTypography.ui(size: 48, weight: .bold))
                        .foregroundStyle(AppTheme.primaryText)
                    Spacer()
                    Button("Clear all", role: .destructive) {
                        showClearConfirm = true
                    }
                    .buttonStyle(SoftPillButtonStyle())
                    .disabled(appState.historyEntries.isEmpty)
                }

                TextField("Search notes", text: $searchText)
                    .font(AppTypography.ui(size: 15))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: AppLayout.chipCornerRadius, style: .continuous)
                            .fill(AppTheme.panelBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppLayout.chipCornerRadius, style: .continuous)
                            .stroke(AppTheme.border, lineWidth: 1)
                    )

                if let historyActionMessage = appState.historyActionMessage {
                    Text(historyActionMessage)
                        .font(AppTypography.ui(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                }

                if entries.isEmpty {
                    AppShellCard {
                        Text("No notes found")
                            .font(AppTypography.ui(size: 16))
                            .foregroundStyle(AppTheme.secondaryText)
                            .padding(20)
                    }
                } else {
                    ForEach(groupedEntries) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(formatDayHeader(group.day))
                                .font(AppTypography.ui(size: 15, weight: .semibold))
                                .foregroundStyle(AppTheme.secondaryText)

                            DataTableCard {
                                ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                                    HStack(alignment: .top, spacing: 14) {
                                        Text(Self.timeFormatter.string(from: entry.createdAt))
                                            .font(AppTypography.ui(size: 15, weight: .medium))
                                            .foregroundStyle(AppTheme.secondaryText)
                                            .frame(width: 90, alignment: .leading)

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(entry.text)
                                                .font(AppTypography.ui(size: 18))
                                                .foregroundStyle(AppTheme.primaryText)
                                                .lineLimit(3)

                                            Text("\(entry.wordCount) words • \(String(format: "%.1fs", entry.durationSeconds))")
                                                .font(AppTypography.mono(size: 12))
                                                .foregroundStyle(AppTheme.secondaryText)
                                        }

                                        Spacer()

                                        HStack(spacing: 8) {
                                            RowActionButton(title: "Copy") {
                                                appState.copyHistoryEntryText(entry.text)
                                            }
                                            RowActionButton(title: "Delete", role: .destructive) {
                                                appState.deleteHistoryEntry(id: entry.id)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)

                                    if index < group.entries.count - 1 {
                                        Divider().overlay(AppTheme.border)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(26)
            .frame(maxWidth: 980, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .confirmationDialog("Clear all notes?", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Clear all", role: .destructive) {
                appState.clearHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private var entries: [HistoryEntry] {
        appState.filteredHistoryEntries(searchText: searchText)
    }

    private var groupedEntries: [HistoryGroup] {
        let grouped = Dictionary(grouping: entries) {
            Calendar.current.startOfDay(for: $0.createdAt)
        }

        return grouped.keys
            .sorted(by: >)
            .map { HistoryGroup(day: $0, entries: grouped[$0, default: []].sorted { $0.createdAt > $1.createdAt }) }
    }

    private struct HistoryGroup: Identifiable {
        let day: Date
        let entries: [HistoryEntry]

        var id: Date { day }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}
