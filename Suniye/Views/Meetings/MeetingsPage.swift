import AppKit
import SwiftUI

/// The Meetings section of the main window: the list, or one meeting's page.
struct MeetingsSection: View {
    @Bindable var meetings: MeetingCoordinator
    let appState: AppState

    var body: some View {
        if let id = meetings.openMeetingID, meetings.record(id) != nil {
            MeetingPage(meetings: meetings, appState: appState, id: id)
                .id(id)
        } else {
            MeetingsPage(meetings: meetings, appState: appState)
        }
    }
}

struct MeetingsPage: View {
    @Bindable var meetings: MeetingCoordinator
    let appState: AppState

    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @State private var texts: [UUID: MeetingListText] = [:]
    @State private var selectedID: UUID?
    @State private var actions = MeetingActions()

    var body: some View {
        DetailScrollContainer {
            HStack(alignment: .firstTextBaseline) {
                DetailPageTitle(title: "Meetings")
                Spacer()
                Button("Record Meeting") {
                    actions.startMeeting(meetings)
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(meetings.live != nil)
            }

            ForEach(unfinished) { record in
                InlineStatusBanner(
                    icon: "exclamationmark.triangle.fill",
                    tint: .orange,
                    title: MeetingStatus.interruptedTitle,
                    detail: "Suniye closed while it wrote the transcript of the \(record.startedAt.formatted(date: .omitted, time: .shortened)) meeting. The audio is saved.",
                    actionTitle: meetings.finishing.contains(record.id) ? nil : "Finish Transcript",
                    action: { meetings.finishTranscript(record.id) }
                )
            }

            if let live = meetings.live {
                LiveMeetingRow(session: live) {
                    meetings.openMeetingID = live.id
                }
            }

            if !finished.isEmpty {
                TranscriptSearchBar(searchText: $searchText, isSearchFocused: $isSearchFocused, placeholder: "Search meetings")
            }

            list
        }
        .meetingActionDialogs(actions, meetings: meetings)
        .task(id: searchText) {
            guard !query.isEmpty else { return }
            for record in finished where texts[record.id] == nil {
                texts[record.id] = await meetings.listText(for: record.id)
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        if finished.isEmpty, meetings.live == nil {
            VStack(spacing: 12) {
                EmptyStateCard(
                    icon: "person.2",
                    title: "No Meetings Yet",
                    detail: meetings.canRecordCallAudio
                        ? "Record a call or a meeting in the room."
                        : "Recording a call needs macOS 14.4 or later."
                )
                if !meetings.canRecordCallAudio {
                    Button("Open Software Update") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension")!)
                    }
                }
            }
        } else if visible.isEmpty, !query.isEmpty {
            EmptyStateCard(icon: "magnifyingglass", title: "No Matches", detail: "No meetings match this search.")
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(groups, id: \.day) { group in
                    Section {
                        ForEach(group.records) { record in
                            MeetingRow(
                                record: record,
                                snippet: snippet(for: record),
                                query: query,
                                isSelected: selectedID == record.id
                            ) {
                                selectedID = record.id
                                meetings.openMeetingID = record.id
                            }
                            .task(id: record) {
                                texts[record.id] = await meetings.listText(for: record.id)
                            }
                            .contextMenu {
                                MeetingMenuItems(record: record, meetings: meetings, actions: actions, isLive: false, includesOpen: true)
                            }
                        }
                    } header: {
                        Text(TranscriptBrowser.dayTitle(for: group.day).uppercased())
                            .font(AppTypography.caption)
                            .tracking(0.8)
                            .foregroundStyle(MainWindowPalette.tertiaryText)
                            .padding(.top, group.day == groups.first?.day ? 0 : 18)
                    }
                }
            }
            .focusable()
            .focusEffectDisabled()
            .onDeleteCommand {
                if let selectedID, let record = meetings.record(selectedID) {
                    actions.confirmDelete(record)
                }
            }
        }
    }

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Finished meetings: everything but the live one and the ones whose
    /// transcript did not finish (they have their own banner above).
    private var finished: [MeetingRecord] {
        meetings.meetings.filter { $0.id != meetings.live?.id && $0.status != .interrupted }
    }

    private var unfinished: [MeetingRecord] {
        meetings.meetings.filter { $0.status == .interrupted }
    }

    private var visible: [MeetingRecord] {
        guard !query.isEmpty else { return finished }
        return finished.filter { record in
            record.title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || texts[record.id]?.line(matching: query) != nil
        }
    }

    private var groups: [(day: Date, records: [MeetingRecord])] {
        let calendar = Calendar.autoupdatingCurrent
        var groups: [(day: Date, records: [MeetingRecord])] = []
        for record in visible {
            let day = calendar.startOfDay(for: record.startedAt)
            if groups.last?.day == day {
                groups[groups.count - 1].records.append(record)
            } else {
                groups.append((day, [record]))
            }
        }
        return groups
    }

    private func snippet(for record: MeetingRecord) -> String? {
        guard let text = texts[record.id] else { return nil }
        if !query.isEmpty, let line = text.line(matching: query) {
            return line
        }
        return text.snippet(for: record.status)
    }
}

/// The meeting that records now, on top of the list.
private struct LiveMeetingRow: View {
    let session: MeetingSession
    let open: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(session.isPaused ? Color.secondary : Color.red)
                .frame(width: 8, height: 8)
            Text(session.isPaused ? "Paused" : "Recording")
                .font(AppTypography.bodyMedium)
            MeetingTimer(session: session)
                .foregroundStyle(MainWindowPalette.secondaryText)
            Text(session.record.title)
                .font(AppTypography.body)
                .lineLimit(1)
            Spacer()
            Button("Open Meeting", action: open)
        }
        .padding(.vertical, AppMetrics.listRowVerticalPadding)
    }
}

private struct MeetingRow: View {
    let record: MeetingRecord
    let snippet: String?
    let query: String
    let isSelected: Bool
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(record.startedAt.formatted(date: .omitted, time: .shortened))
                    .font(AppTypography.body.monospacedDigit())
                    .foregroundStyle(MainWindowPalette.secondaryText)
                    .frame(width: 72, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.title)
                        .font(AppTypography.bodyMedium)
                        .lineLimit(1)
                    if let snippet {
                        Text(snippet.highlightingMatches(of: query))
                            .font(AppTypography.body)
                            .foregroundStyle(MainWindowPalette.secondaryText)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 12)
                if let duration = record.duration {
                    Text(MeetingDurationText.text(duration))
                        .font(AppTypography.body.monospacedDigit())
                        .foregroundStyle(MainWindowPalette.tertiaryText)
                }
            }
            .padding(.vertical, AppMetrics.listRowVerticalPadding)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: AppMetrics.cardCornerRadius, style: .continuous)
                    .fill(isSelected ? MainWindowPalette.selectedFill : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle(pressedScale: 0.995))
    }
}
