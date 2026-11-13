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
                    MeetingLiveMeta(session: live, meetings: meetings)
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
                MeetingTabs(selection: $tab, summaryEnabled: live == nil)
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
                notes = MeetingNotesDraft(saved: await meetings.notes(of: id))
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
                Button(live.isPaused ? "Resume" : "Pause") {
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
                }
                Button("Stop") {
                    Task { await meetings.stop() }
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
                }
                if live == nil {
                    MeetingRegenerateMenu(title: "Regenerate Summary", meetings: meetings, actions: actions, record: record)
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
                speaker: record.hasCallTrack ? segment.track.speakerLabel : nil,
                text: segment.text
            )
        }
    }
}

/// Summary, Notes, Transcript in one native segmented control, whose Summary
/// segment is off while the meeting records.
private struct MeetingTabs: NSViewRepresentable {
    @Binding var selection: MeetingTab
    let summaryEnabled: Bool

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: MeetingTab.allCases.map(\.title),
            trackingMode: .selectOne,
            target: context.coordinator,
            action: #selector(Coordinator.changed(_:))
        )
        control.segmentDistribution = .fit
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        control.setEnabled(summaryEnabled, forSegment: MeetingTab.summary.rawValue)
        control.selectedSegment = selection.rawValue
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    final class Coordinator: NSObject {
        var selection: Binding<MeetingTab>

        init(selection: Binding<MeetingTab>) {
            self.selection = selection
        }

        @objc func changed(_ sender: NSSegmentedControl) {
            if let tab = MeetingTab(rawValue: sender.selectedSegment) {
                selection.wrappedValue = tab
            }
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
    let meetings: MeetingCoordinator
    @State private var showsCallProblem = false

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
            track(session.changedInput ?? MeetingTrack.you.speakerLabel, level: session.youLevel, problem: session.failedTracks[.you])
            if session.hasCallTrack {
                if let problem = session.callAudioProblem {
                    Button {
                        showsCallProblem = true
                    } label: {
                        Label("No sound", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.borderless)
                    .popover(isPresented: $showsCallProblem, arrowEdge: .bottom) {
                        CallProblemPopover(problem: problem, meetings: meetings)
                    }
                } else {
                    track(MeetingTrack.them.speakerLabel, level: session.themLevel, problem: session.failedTracks[.them])
                }
            }
        }
        .font(AppTypography.body)
        .foregroundStyle(MainWindowPalette.secondaryText)
    }

    @ViewBuilder
    private func track(_ name: String, level: Float, problem: String?) -> some View {
        if let problem {
            Label(name, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .help(problem)
        } else {
            HStack(spacing: 6) {
                Text(name)
                    .lineLimit(1)
                MeetingLevelMeter(level: session.isPaused ? 0 : level)
            }
        }
    }
}

private struct CallProblemPopover: View {
    let problem: MeetingSession.CallAudioProblem
    let meetings: MeetingCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch problem {
            case .neverHeard:
                Text("No sound from the call for \(MeetingDurationText.spelledOut(MeetingRecorder.callSilenceLimit))")
                    .font(AppTypography.bodyMedium)
                Text("If people are talking, Suniye may need permission to record system audio.")
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open System Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                }
            case let .stopped(since):
                Text("Call audio stopped")
                    .font(AppTypography.bodyMedium)
                Text("No sound from the call since \(MeetingTranscript.clock(since)).")
                Button("Restart Call Audio") {
                    meetings.restartCallAudio()
                }
            }
        }
        .padding(14)
        .frame(width: 280, alignment: .leading)
    }
}

/// A short bar for a track's level, 0...1.
struct MeetingLevelMeter: View {
    let level: Float

    var body: some View {
        Capsule()
            .fill(MainWindowPalette.divider)
            .frame(width: 36, height: 4)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.55))
                    .frame(width: 36 * CGFloat(min(max(level, 0), 1)), height: 4)
            }
            .animation(.linear(duration: 0.066), value: level)
            .accessibilityHidden(true)
    }
}
