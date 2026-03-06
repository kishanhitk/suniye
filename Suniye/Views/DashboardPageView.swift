import SwiftUI

struct DashboardPageView: View {
    @Bindable var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center) {
                    Text("Welcome back")
                        .font(AppTypography.ui(size: 48, weight: .bold))
                        .foregroundStyle(AppTheme.primaryText)

                    Spacer()

                    HStack(spacing: 10) {
                        MetricPill(symbol: "🔥", label: "Sessions", value: "\(appState.sessionCount)")
                        MetricPill(symbol: "🚀", label: "Words", value: "\(appState.wordsTranscribed)")
                        MetricPill(symbol: "🥇", label: "WPM", value: "\(wpm)")
                    }
                }

                AppShellCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Make Suniye sound like you")
                            .font(AppTypography.serif(size: 60, weight: .regular))
                            .foregroundStyle(AppTheme.primaryText)

                        Text(heroDescription)
                            .font(AppTypography.ui(size: 26, weight: .medium))
                            .foregroundStyle(AppTheme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 12) {
                            Button(primaryActionTitle) {
                                runPrimaryAction()
                            }
                            .buttonStyle(PrimaryDarkButtonStyle())
                            .disabled(primaryActionDisabled)

                            if appState.phase == .downloadingModel {
                                ProgressView(value: appState.downloadProgress)
                                    .frame(width: 180)
                            }
                        }

                        if let lastError = appState.lastError, appState.phase == .error {
                            Text(lastError)
                                .font(AppTypography.ui(size: 14, weight: .medium))
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(22)
                    .background(AppTheme.warmCardBackground)
                }

                if recentEntries.isEmpty {
                    AppShellCard {
                        Text("No notes yet. Hold your hotkey and start dictating.")
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
                                            .frame(width: 88, alignment: .leading)

                                        Text(entry.text)
                                            .font(AppTypography.ui(size: 18))
                                            .foregroundStyle(AppTheme.primaryText)
                                            .lineLimit(2)

                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)

                                    if index < group.entries.count - 1 {
                                        Divider()
                                            .overlay(AppTheme.border)
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
    }

    private var recentEntries: [HistoryEntry] {
        Array(appState.historyEntries.prefix(24))
    }

    private var wpm: String {
        guard appState.totalDictationSeconds > 0 else {
            return "0"
        }
        let rate = Double(appState.wordsTranscribed) / (appState.totalDictationSeconds / 60)
        return String(Int(rate.rounded()))
    }

    private var heroDescription: String {
        switch appState.phase {
        case .needsModel:
            return "Download the local speech model first. Your transcription never leaves your machine."
        case .downloadingModel:
            return "Downloading local speech model. This runs once and unlocks offline dictation."
        case .loading:
            return "Loading model files and preparing recognizer."
        case .recording:
            return "Listening now. Release hotkey to transcribe and paste."
        case .transcribing:
            return "Processing captured audio clip."
        case .error:
            return "There is an issue blocking dictation. Resolve it from Settings."
        case .ready:
            return "Use hold-to-talk dictation for messages, docs, and editor input."
        }
    }

    private var primaryActionTitle: String {
        switch appState.phase {
        case .needsModel, .error:
            return "Download model"
        case .downloadingModel:
            return "Downloading..."
        case .loading:
            return "Loading..."
        case .ready:
            return "Start now"
        case .recording:
            return "Stop now"
        case .transcribing:
            return "Processing..."
        }
    }

    private var primaryActionDisabled: Bool {
        switch appState.phase {
        case .downloadingModel, .loading, .transcribing:
            return true
        default:
            return false
        }
    }

    private func runPrimaryAction() {
        switch appState.phase {
        case .needsModel, .error:
            appState.startModelDownload()
        case .ready:
            appState.startRecordingFromUI()
        case .recording:
            appState.stopRecordingFromUI()
        case .downloadingModel, .loading, .transcribing:
            break
        }
    }

    private var groupedEntries: [HistoryGroup] {
        let grouped = Dictionary(grouping: recentEntries) {
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
