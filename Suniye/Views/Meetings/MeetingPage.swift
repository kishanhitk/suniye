import AppKit
import SwiftUI

enum MeetingTab: Int, CaseIterable {
    case summary
    case notes
    case transcript

    var title: String {
        switch self {
        case .summary: return "Summary"
        case .notes: return "Notes"
        case .transcript: return "Transcript"
        }
    }
}

/// One meeting: while it records, and after.
struct MeetingPage: View {
    @Bindable var meetings: MeetingCoordinator
    let appState: AppState
    let id: UUID

    @State private var tab: MeetingTab
    @State private var actions = MeetingActions()
    @State private var segments: [MeetingSegment] = []
    @State private var summary: String?
    /// Nil until the notes are read, so the editor never saves over them.
    @State private var notes: MeetingNotesDraft?
    @State private var notesUnreadable = false

    init(meetings: MeetingCoordinator, appState: AppState, id: UUID) {
        self.meetings = meetings
        self.appState = appState
        self.id = id
        _tab = State(initialValue: meetings.live?.id == id ? .notes : .summary)
    }

    var body: some View {
        if let record = meetings.record(id) {
            VStack(alignment: .leading, spacing: 14) {
                header(record)
                if let live {
                    MeetingLiveMeta(session: live)
                    MeetingLiveBanner(session: live, meetings: meetings)
                } else {
                    Text(metaLine(record))
                        .font(AppTypography.body)
                        .foregroundStyle(MainWindowPalette.secondaryText)
                }
                if let failure = meetings.writeFailure, failure.meetingID == id, let duration = record.duration {
                    InlineStatusBanner(
                        icon: "exclamationmark.triangle.fill",
                        tint: .orange,
                        title: failure.outOfSpace ? "Recording stopped because the disk is full" : "Recording stopped because the audio could not be saved",
                        detail: "Everything up to \(MeetingTranscript.clock(duration)) is saved." + (failure.outOfSpace ? " Free up space to record again." : "")
                    )
                }
                MeetingTabs(selection: $tab, tabs: live == nil ? MeetingTab.allCases : [.notes, .transcript])
                    .fixedSize()
                content(record)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, AppMetrics.detailPaddingHorizontal)
            .padding(.top, AppMetrics.detailPaddingTop)
            .padding(.bottom, AppMetrics.detailPaddingBottom)
            .meetingActionDialogs(actions, meetings: meetings)
            .task(id: record) {
                segments = await meetings.transcript(of: id)
                summary = await meetings.summary(of: id)
            }
            .task(id: id) {
                let saved = await meetings.notes(of: id)
                notes = saved.map(MeetingNotesDraft.init(saved:))
                notesUnreadable = saved == nil
            }
            .onAppear { meetings.pageOnScreen = id }
            .onDisappear {
                if meetings.pageOnScreen == id {
                    meetings.pageOnScreen = nil
                }
            }
            .onChange(of: live == nil) { _, finished in
                if finished, tab == .notes, notes?.text.isEmpty ?? true {
                    tab = .summary
                }
            }
        }
    }

    private var live: MeetingSession? {
        guard let live = meetings.live, live.id == id else { return nil }
        return live
    }

    // MARK: - Header

    private func header(_ record: MeetingRecord) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                meetings.openMeetingID = nil
            } label: {
                Image(systemName: "chevron.backward")
                    .font(AppTypography.bodyMedium)
                    .foregroundStyle(MainWindowPalette.secondaryText)
            }
            .buttonStyle(.borderless)
            .help("Back")
            .keyboardShortcut("[", modifiers: .command)

            Text(record.title)
                .font(AppTypography.transcriptsHeadline)
                .tracking(AppTypography.transcriptsHeadlineTracking)
                .lineLimit(1)
                .truncationMode(.tail)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.2), value: record.title)

            Spacer(minLength: 12)

            if let live {
                Button {
                    Task {
                        if live.isPaused {
                            do {
                                try await meetings.resume()
                            } catch {
                                actions.failure = MeetingActionFailure(title: "Couldn’t resume the recording", message: error.localizedDescription)
                            }
                        } else {
                            await meetings.pause()
                        }
                    }
                } label: {
                    Label(live.isPaused ? "Resume" : "Pause", systemImage: live.isPaused ? "record.circle" : "pause.fill")
                }
                Button {
                    Task { await meetings.stop() }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .keyboardShortcut(".", modifiers: .command)
            } else if let text = copyText(record) {
                MeetingCopyButton(title: "Copy \(tab.title)", text: text)
            }

            Menu {
                MeetingMenuItems(record: record, meetings: meetings, actions: actions, isLive: live != nil)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
        }
    }

    /// "Today · 2:06 PM · 38 min · Zoom"
    private func metaLine(_ record: MeetingRecord) -> String {
        var parts = [
            TranscriptBrowser.dayTitle(for: record.startedAt),
            record.startedAt.formatted(date: .omitted, time: .shortened),
        ]
        if let duration = record.duration {
            parts.append(MeetingDurationText.text(duration))
        }
        if let app = record.callAppName {
            parts.append(app)
        }
        return parts.joined(separator: " · ")
    }

    private func copyText(_ record: MeetingRecord) -> String? {
        let text: String
        switch tab {
        case .summary:
            text = summary ?? ""
        case .notes:
            text = notes?.text ?? ""
        case .transcript:
            text = MeetingExport.transcript(record: record, segments: segments)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ record: MeetingRecord) -> some View {
        switch tab {
        case .summary:
            MeetingSummaryTab(meetings: meetings, appState: appState, actions: actions, record: record, summary: summary)
        case .notes:
            VStack(alignment: .leading, spacing: 12) {
                if let draft = Binding($notes) {
                    MeetingNotesEditor(draft: draft) { text in
                        Task { await meetings.saveNotes(text, for: id) }
                    }
                } else if notesUnreadable {
                    Text("Couldn’t read the notes.")
                        .foregroundStyle(MainWindowPalette.secondaryText)
                }
                if live == nil {
                    MeetingRegenerateMenu(title: "Regenerate Summary", meetings: meetings, actions: actions, record: record)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        case .transcript:
            MeetingTranscriptView(lines: transcriptLines(record), followsLatest: live != nil)
        }
    }

    private func transcriptLines(_ record: MeetingRecord) -> [MeetingTranscriptLine] {
        let shown = live?.visibleSegments ?? segments
        let timeline = MeetingTimeline(pauses: record.pauses)
        return shown.map { segment in
            MeetingTranscriptLine(
                id: segment.id,
                time: MeetingTranscript.clock(timeline.wallSeconds(forSample: segment.audioStart)),
                speaker: record.hasCallTrack ? segment.track : nil,
                text: segment.text
            )
        }
    }
}

/// Summary, Notes, Transcript in one native segmented control, whose Summary
/// segment is off while the meeting records.
/// While the meeting records there is no summary yet, so the control has
/// only Notes and Transcript.
private struct MeetingTabs: NSViewRepresentable {
    @Binding var selection: MeetingTab
    let tabs: [MeetingTab]

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: tabs.map(\.title),
            trackingMode: .selectOne,
            target: context.coordinator,
            action: #selector(Coordinator.changed(_:))
        )
        control.segmentDistribution = .fit
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        context.coordinator.tabs = tabs
        if control.segmentCount != tabs.count {
            control.segmentCount = tabs.count
            for (index, tab) in tabs.enumerated() {
                control.setLabel(tab.title, forSegment: index)
                control.setWidth(0, forSegment: index)
            }
            control.invalidateIntrinsicContentSize()
        }
        control.selectedSegment = tabs.firstIndex(of: selection) ?? -1
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection, tabs: tabs)
    }

    final class Coordinator: NSObject {
        var selection: Binding<MeetingTab>
        var tabs: [MeetingTab]

        init(selection: Binding<MeetingTab>, tabs: [MeetingTab]) {
            self.selection = selection
            self.tabs = tabs
        }

        @objc func changed(_ sender: NSSegmentedControl) {
            guard tabs.indices.contains(sender.selectedSegment) else { return }
            selection.wrappedValue = tabs[sender.selectedSegment]
        }
    }
}

/// "Copy Summary", then "Copied" with a checkmark for a moment.
struct MeetingCopyButton: View {
    let title: String
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            copied = NSPasteboard.general.setString(text, forType: .string)
        } label: {
            if copied {
                Label("Copied", systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

/// While the meeting records: the timer, and a meter for each track with its
/// problem in place of the meter.
private struct MeetingLiveMeta: View {
    let session: MeetingSession

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                Circle()
                    .fill(session.isPaused ? Color.secondary : Color.red)
                    .frame(width: 8, height: 8)
                if session.isPaused {
                    Text("Paused")
                        .font(AppTypography.bodyMedium)
                }
                MeetingTimer(session: session)
            }
            track(.you, level: session.youLevel)
            if session.hasCallTrack {
                track(.them, level: session.callAudioProblem == nil ? session.themLevel : 0)
            }
        }
        .font(AppTypography.body)
        .foregroundStyle(MainWindowPalette.secondaryText)
    }

    /// A failed track shows its cause in place of the meter.
    @ViewBuilder
    private func track(_ track: MeetingTrack, level: Float) -> some View {
        if let problem = session.failedTracks[track] {
            Label(track.speakerLabel, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .help(problem)
        } else {
            HStack(spacing: 6) {
                Text(track.speakerLabel)
                MeetingLevelMeter(level: session.isPaused ? 0 : level, tint: track == .you ? .accentColor : MainWindowPalette.secondaryText)
            }
        }
    }
}

/// No sound from the call, or a new microphone, above the tabs.
private struct MeetingLiveBanner: View {
    let session: MeetingSession
    let meetings: MeetingCoordinator

    var body: some View {
        if session.hasCallTrack, let problem = session.callAudioProblem {
            switch problem {
            case .neverHeard:
                InlineStatusBanner(
                    icon: "exclamationmark.circle",
                    tint: .orange,
                    title: "No sound from the call for \(MeetingDurationText.spelledOut(MeetingRecorder.callSilenceLimit))",
                    detail: "If people are talking, Suniye may need permission to record system audio.",
                    actionTitle: "Open System Settings",
                    action: { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!) }
                )
            case let .stopped(since):
                InlineStatusBanner(
                    icon: "exclamationmark.circle",
                    tint: .orange,
                    title: "Call audio stopped",
                    detail: "No sound from the call since \(MeetingTranscript.clock(since)).",
                    actionTitle: "Restart Call Audio",
                    action: { meetings.restartCallAudio() }
                )
            }
        } else if let name = session.changedInput {
            InlineStatusBanner(
                icon: "mic",
                tint: .accentColor,
                title: "Microphone changed",
                detail: "Recording continues with \(name)."
            )
        }
    }
}

/// Five bars for a track: its last five levels, the newest on the right.
struct MeetingLevelMeter: View {
    let level: Float
    let tint: Color
    @State private var levels = [Float](repeating: 0, count: 5)

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(levels.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(levels[index] > 0.02 ? tint : MainWindowPalette.divider)
                    .frame(width: 3, height: 3 + 11 * CGFloat(min(max(levels[index], 0), 1)))
            }
        }
        .frame(height: 14, alignment: .bottom)
        .animation(.linear(duration: 0.066), value: levels)
        .onChange(of: level) { _, newLevel in
            levels = Array((levels + [newLevel]).suffix(5))
        }
        .accessibilityHidden(true)
    }
}
