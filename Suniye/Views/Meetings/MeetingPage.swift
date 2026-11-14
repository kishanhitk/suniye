import AppKit
import SuniyeAnalytics
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
    /// The parts of the text that the user changed in this visit of the page.
    @State private var editedParts: Set<MeetingEditedText> = []

    init(meetings: MeetingCoordinator, appState: AppState, id: UUID) {
        self.meetings = meetings
        self.appState = appState
        self.id = id
        _tab = State(initialValue: meetings.live?.id == id ? .notes : .summary)
    }

    var body: some View {
        if let record = meetings.record(id) {
            VStack(alignment: .leading, spacing: 14) {
                backLink
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
                        tint: .red,
                        title: failure.outOfSpace ? "Recording stopped because the disk is full" : "Recording stopped because the audio could not be saved",
                        detail: "Everything up to \(MeetingTranscript.clock(duration)) is saved." + (failure.outOfSpace ? " Free up space to record again." : "")
                    )
                }
                if live == nil {
                    HStack(spacing: 12) {
                        MeetingTabs(selection: $tab)
                            .fixedSize()
                        Spacer(minLength: 12)
                        HStack(spacing: 4) {
                            if tab == .summary {
                                MeetingRegenerateMenu(meetings: meetings, actions: actions, record: record)
                            }
                            MeetingCopyButton(title: "Copy \(tab.title)", hasText: hasCopyText) {
                                copyText(record)
                            }
                            .id(tab)
                        }
                    }
                }
                content(record)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, AppMetrics.detailPaddingHorizontal)
            .padding(.top, AppMetrics.detailPaddingTop)
            .padding(.bottom, AppMetrics.detailPaddingBottom)
            .meetingActionDialogs(actions, meetings: meetings)
            // A new status brings new text: a finished transcript or summary.
            // The user's own edits change the record too, and must not read
            // back older text over what they type.
            .task(id: record.status) {
                segments = await meetings.transcript(of: id)
                summary = await meetings.summary(of: id)
            }
            .task(id: meetings.transcriptPasses[id]?.kind == .again) {
                segments = await meetings.transcript(of: id)
            }
            .task(id: id) {
                let saved = await meetings.notes(of: id)
                notes = saved.map(MeetingNotesDraft.init(saved:))
                notesUnreadable = saved == nil
            }
            .onAppear { meetings.pageOnScreen = id }
            .onDisappear {
                meetings.textSaves.saveNow(id)
                meetings.playback.close(id)
                if meetings.pageOnScreen == id {
                    meetings.pageOnScreen = nil
                }
            }
            .onChange(of: tab) {
                meetings.textSaves.saveNow(id)
                // The controls are on the Transcript tab: no sound plays
                // without them in sight.
                if tab != .transcript {
                    meetings.playback.pause()
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

    /// "‹ Meetings" above the title, back to the list.
    private var backLink: some View {
        Button {
            meetings.openMeetingID = nil
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 10, weight: .semibold))
                Text("Meetings")
            }
            .font(AppTypography.body)
            .foregroundStyle(Color.accentColor)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("[", modifiers: .command)
        .accessibilityLabel("Back to Meetings")
    }

    private func header(_ record: MeetingRecord) -> some View {
        HStack(alignment: .center, spacing: 10) {
            // The hidden text gives the row the height and the room that the
            // title text had before it could be edited; the text view draws
            // the title on top, a little taller, so no letter is cut.
            Text(record.title)
                .font(AppTypography.transcriptsHeadline)
                .lineLimit(1)
                .hidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .topLeading) {
                    MeetingTitleField(title: record.title) { title in
                        noteEdit(.title)
                        meetings.textSaves.save(.title, of: id) {
                            await meetings.rename(id, to: title)
                        }
                    }
                    .frame(height: MeetingTitleField.height)
                }
                .padding(.trailing, 22)

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
            }

            Menu {
                MeetingMenuItems(record: record, meetings: meetings, actions: actions, isLive: live != nil)
            } label: {
                MeetingIcon(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
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

    /// Each update of the page reads this, so it does not build the
    /// transcript text, which can be long. A click builds it.
    private var hasCopyText: Bool {
        switch tab {
        case .summary:
            return !(summary ?? "").allSatisfy(\.isWhitespace)
        case .notes:
            return !(notes?.text ?? "").allSatisfy(\.isWhitespace)
        case .transcript:
            return segments.contains { !$0.text.allSatisfy(\.isWhitespace) }
        }
    }

    private func copyText(_ record: MeetingRecord) -> String {
        switch tab {
        case .summary:
            return summary ?? ""
        case .notes:
            return notes?.text ?? ""
        case .transcript:
            return MeetingExport.transcript(record: record, segments: segments)
        }
    }

    // MARK: - Content

    /// While the meeting records, the page shows only the notes.
    @ViewBuilder
    private func content(_ record: MeetingRecord) -> some View {
        switch live == nil ? tab : .notes {
        case .summary:
            MeetingSummaryTab(
                meetings: meetings,
                appState: appState,
                actions: actions,
                record: record,
                summary: summary,
                isEditable: canEditText(record) && record.status == .done
            ) { markdown, ended in
                editSummary(markdown, ended: ended)
            }
        case .notes:
            if let draft = Binding($notes) {
                MeetingNotesEditor(draft: draft) { text in
                    meetings.textSaves.stage(.notes, of: id) {
                        await meetings.saveNotes(text, for: id)
                    }
                }
            } else if notesUnreadable {
                Text("Couldn’t read the notes.")
                    .foregroundStyle(MainWindowPalette.secondaryText)
            }
        case .transcript:
            if record.status == .finishing {
                MeetingTranscriptProgressView(progress: meetings.transcriptPasses[id]?.progress, isWaiting: meetings.transcriptPasses[id]?.waiting ?? false)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    if let pass = meetings.transcriptPasses[id], pass.kind == .again {
                        MeetingTranscriptProgressView(progress: pass.progress, isWaiting: pass.waiting, title: "Transcribing again…")
                    }
                    MeetingTranscriptPane(
                        playback: meetings.playback,
                        id: id,
                        segments: segments,
                        lines: transcriptLines(record),
                        timeline: MeetingTimeline(pauses: record.pauses),
                        hasAudio: meetings.audioOnMac.contains(id) && record.status.hasFinalTranscript,
                        canPlay: meetings.live == nil,
                        isEditable: canEditText(record)
                    ) { texts, ended in
                        editTranscript(texts, ended: ended)
                    }
                }
            }
        }
    }

    /// No edit while a transcript or a summary is written: either would
    /// replace the text under the user.
    private func canEditText(_ record: MeetingRecord) -> Bool {
        live == nil && record.status.hasFinalTranscript && record.status != .summarizing && meetings.transcriptPasses[id] == nil
    }

    /// The page shows the edit at once; the save waits for a pause in the
    /// typing, and an emptied line goes only when the edit ends.
    private func editTranscript(_ texts: [UUID: String], ended: Bool) {
        noteEdit(.transcript)
        segments = segments.compactMap { segment in
            guard let text = texts[segment.id] else { return segment }
            return text.isEmpty && ended ? nil : segment.withText(text)
        }
        let save: () async -> Void = { [meetings, id] in
            await meetings.editTranscript(id, texts: texts, deleteEmpty: ended)
        }
        if ended {
            meetings.textSaves.save(.transcript, of: id, save: save)
        } else {
            meetings.textSaves.stage(.transcript, of: id, save: save)
        }
    }

    private func editSummary(_ markdown: String, ended: Bool) {
        noteEdit(.summary)
        summary = markdown
        let save: () async -> Void = { [meetings, id] in
            await meetings.editSummary(id, markdown: markdown)
        }
        if ended {
            meetings.textSaves.save(.summary, of: id, save: save)
        } else {
            meetings.textSaves.stage(.summary, of: id, save: save)
        }
    }

    private func noteEdit(_ part: MeetingEditedText) {
        if editedParts.insert(part).inserted {
            meetings.textEdited(part)
        }
    }

    private func transcriptLines(_ record: MeetingRecord) -> [MeetingTranscriptLine] {
        let timeline = MeetingTimeline(pauses: record.pauses)
        return segments.map { segment in
            MeetingTranscriptLine(
                id: segment.id,
                time: MeetingTranscript.clock(timeline.wallSeconds(forSample: segment.audioStart)),
                speaker: record.hasCallTrack ? segment.track : nil,
                text: segment.text
            )
        }
    }
}

/// Summary, Notes and Transcript in one native segmented control.
private struct MeetingTabs: NSViewRepresentable {
    @Binding var selection: MeetingTab

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
            guard let tab = MeetingTab(rawValue: sender.selectedSegment) else { return }
            selection.wrappedValue = tab
        }
    }
}

/// The copy icon of the open tab, a checkmark for a moment after a copy.
struct MeetingCopyButton: View {
    let title: String
    let hasText: Bool
    let text: () -> String
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            copied = NSPasteboard.general.setString(text(), forType: .string)
            if copied {
                AccessibilityNotification.Announcement("Copied").post()
            }
        } label: {
            MeetingIcon(systemName: copied ? "checkmark" : "doc.on.doc")
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .disabled(!hasText)
        .help(title)
        .accessibilityLabel(title)
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

/// An icon button label of the meeting page: a square of the same size for
/// each symbol, so icons of different widths line up by their centers. Its
/// control uses the plain style: the borderless styles draw a menu's image
/// themselves and leave out this frame.
struct MeetingIcon: View {
    let systemName: String
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Image(systemName: systemName)
            .foregroundStyle(isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            .frame(width: AppMetrics.iconButtonSize, height: AppMetrics.iconButtonSize)
            .contentShape(Rectangle())
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
                MeetingLevelMeter(level: level, tint: track == .you ? .accentColor : MainWindowPalette.secondaryText, isPaused: session.isPaused)
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
    var restTint = MainWindowPalette.divider
    var barWidth: CGFloat = 3
    var height: CGFloat = 14
    /// While paused the bars rest. A pause sends one zero, so the bars before
    /// it would otherwise stay up for the whole pause.
    var isPaused = false
    @State private var levels = [Float](repeating: 0, count: 5)

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(levels.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: barWidth / 2)
                    .fill(levels[index] > 0.02 ? tint : restTint)
                    .frame(width: barWidth, height: 3 + (height - 3) * CGFloat(min(max(levels[index], 0), 1)))
            }
        }
        .frame(height: height, alignment: .bottom)
        .animation(.linear(duration: 0.066), value: levels)
        .onChange(of: level) { _, newLevel in
            guard !isPaused else { return }
            levels = Array((levels + [newLevel]).suffix(5))
        }
        .onChange(of: isPaused) { _, paused in
            if paused {
                levels = [Float](repeating: 0, count: 5)
            }
        }
        .accessibilityHidden(true)
    }
}
