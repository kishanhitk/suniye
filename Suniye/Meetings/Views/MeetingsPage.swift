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
            MeetingsPage(meetings: meetings)
        }
    }
}

struct MeetingsPage: View {
    @Bindable var meetings: MeetingCoordinator

    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @State private var texts: [UUID: MeetingListText] = [:]
    @State private var actions = MeetingActions()

    var body: some View {
        DetailScrollContainer {
            HStack(alignment: .firstTextBaseline) {
                DetailPageTitle(title: "Meetings")
                Spacer()
                Button {
                    actions.startMeeting(meetings)
                } label: {
                    Label("Record Meeting", systemImage: "record.circle")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("n", modifiers: .command)
                .disabled(meetings.live != nil)
            }

            if !meetings.canRecordCallAudio {
                InlineStatusBanner(
                    icon: "info.circle",
                    tint: .accentColor,
                    title: "Recording a call needs macOS 14.4 or later",
                    detail: "You can still record a meeting in the room.",
                    actionTitle: "Software Update",
                    action: { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension")!) }
                )
            }

            ForEach(unfinished) { record in
                InlineStatusBanner(
                    icon: "exclamationmark.triangle.fill",
                    tint: .orange,
                    title: MeetingStatus.interruptedTitle,
                    detail: unfinishedDetail(record),
                    actionTitle: "Finish Transcript",
                    action: { meetings.finishTranscript(record.id) }
                )
            }

            if let live = meetings.live {
                LiveMeetingRow(session: live) {
                    meetings.openMeetingID = live.id
                }
            }

            if !listed.isEmpty {
                TranscriptSearchBar(searchText: $searchText, isSearchFocused: $isSearchFocused, placeholder: "Search meetings")
            }

            list
        }
        .meetingActionDialogs(actions, meetings: meetings)
        .task(id: searchText) {
            guard !query.isEmpty else { return }
            for record in listed where texts[record.id] == nil {
                texts[record.id] = await meetings.listText(for: record.id)
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        if listed.isEmpty, meetings.live == nil {
            EmptyStateCard(
                icon: "person.2",
                title: "No Meetings Yet",
                detail: meetings.canRecordCallAudio ? "Record a call or a meeting in the room." : "Record a meeting in the room."
            )
        } else if visible.isEmpty, !query.isEmpty {
            EmptyStateCard(icon: "magnifyingglass", title: "No Matches", detail: "No meetings match this search.")
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(groups, id: \.day) { group in
                    Section {
                        ForEach(group.records) { record in
                            MeetingRow(record: record, snippet: snippet(for: record), query: query) {
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
        }
    }

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Every meeting but the live one, which has its own row above.
    private var listed: [MeetingRecord] {
        meetings.meetings.filter { $0.id != meetings.live?.id }
    }

    private func unfinishedDetail(_ record: MeetingRecord) -> String {
        let time = record.startedAt.formatted(date: .omitted, time: .shortened)
        guard let failure = record.transcriptFailure else {
            return "Suniye closed while it wrote the transcript of the \(time) meeting. The audio is saved."
        }
        return "\(failure) The audio of the \(time) meeting is saved."
    }

    private var unfinished: [MeetingRecord] {
        meetings.meetings.filter { $0.status == .interrupted }
    }

    private var visible: [MeetingRecord] {
        guard !query.isEmpty else { return listed }
        return listed.filter { record in
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
            Button("Open Notes", action: open)
        }
        .padding(.vertical, AppMetrics.listRowVerticalPadding)
    }
}

private struct MeetingRow: View {
    let record: MeetingRecord
    let snippet: String?
    let query: String
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
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle(pressedScale: 0.995))
    }
}
