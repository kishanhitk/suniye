import AppKit
import SwiftUI

struct MeetingActionFailure: Equatable {
    let title: String
    let message: String
}

/// Meeting commands for the list and the page, and the dialogs they open.
@MainActor
@Observable
final class MeetingActions {
    var deleting: MeetingRecord?
    var askingTranscribeAgain: MeetingRecord?
    var failure: MeetingActionFailure?
    var editingTemplates = false

    func startMeeting(_ meetings: MeetingCoordinator) {
        Task {
            do {
                try await meetings.startMeeting(source: .manual)
                if let live = meetings.live {
                    meetings.openMeetingID = live.id
                }
            } catch {
                failure = MeetingActionFailure(title: "Couldn’t start the recording", message: error.localizedDescription)
            }
        }
    }

    func confirmDelete(_ record: MeetingRecord) {
        deleting = record
    }

    /// Asks once the typed text is saved, so the question knows about the
    /// edits that a new transcript would replace.
    func askTranscribeAgain(_ record: MeetingRecord, meetings: MeetingCoordinator) {
        Task {
            await meetings.textSaves.finish(record.id)
            askingTranscribeAgain = meetings.record(record.id) ?? record
        }
    }

    func export(_ record: MeetingRecord, meetings: MeetingCoordinator) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(record.title).md"
        panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                try await meetings.export(record, to: url)
            } catch {
                AppLogger.shared.log(.error, "meeting export failed error=\(error.localizedDescription)")
                failure = MeetingActionFailure(title: "Couldn’t export the meeting", message: error.localizedDescription)
            }
        }
    }

    static func transcribeAgainMessage(model: String?, edited: Bool) -> String {
        let transcript = model.map { "A new transcript from \($0)" } ?? "A new transcript"
        let replaced = edited ? "replaces the current one and your edits to it." : "replaces the current one."
        return "\(transcript) \(replaced) Notes and the summary stay."
    }

    func revealInFinder(_ record: MeetingRecord, meetings: MeetingCoordinator) {
        NSWorkspace.shared.activateFileViewerSelecting([meetings.store.folder(for: record.id)])
    }
}

extension View {
    func meetingActionDialogs(_ actions: MeetingActions, meetings: MeetingCoordinator) -> some View {
        modifier(MeetingActionDialogs(actions: actions, meetings: meetings))
    }
}

private struct MeetingActionDialogs: ViewModifier {
    @Bindable var actions: MeetingActions
    let meetings: MeetingCoordinator

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                actions.deleting.map { "Delete “\($0.title)”?" } ?? "",
                isPresented: Binding(get: { actions.deleting != nil }, set: { if !$0 { actions.deleting = nil } }),
                presenting: actions.deleting
            ) { record in
                Button("Delete", role: .destructive) {
                    Task {
                        do {
                            try await meetings.delete(record.id)
                            if meetings.openMeetingID == record.id {
                                meetings.openMeetingID = nil
                            }
                        } catch {
                            AppLogger.shared.log(.error, "meeting delete failed id=\(record.id.uuidString) error=\(error.localizedDescription)")
                            actions.failure = MeetingActionFailure(title: "Couldn’t delete the meeting", message: error.localizedDescription)
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("This deletes the summary, notes, transcript and audio. You can’t undo it.")
            }
            .alert(
                actions.askingTranscribeAgain.map { "Transcribe “\($0.title)” again?" } ?? "",
                isPresented: Binding(get: { actions.askingTranscribeAgain != nil }, set: { if !$0 { actions.askingTranscribeAgain = nil } }),
                presenting: actions.askingTranscribeAgain
            ) { record in
                Button("Transcribe Again") { meetings.transcribeAgain(record.id) }
                Button("Cancel", role: .cancel) {}
            } message: { record in
                Text(MeetingActions.transcribeAgainMessage(model: meetings.transcriptModelName, edited: record.transcriptEditedAt != nil))
            }
            .alert(
                actions.failure?.title ?? "",
                isPresented: Binding(get: { actions.failure != nil }, set: { if !$0 { actions.failure = nil } }),
                presenting: actions.failure
            ) { _ in
                Button("OK") {}
            } message: { failure in
                Text(failure.message)
            }
            .sheet(isPresented: $actions.editingTemplates) {
                MeetingTemplateEditor(meetings: meetings)
            }
    }
}

/// The More menu of a meeting, and the context menu of its row.
struct MeetingMenuItems: View {
    let record: MeetingRecord
    let meetings: MeetingCoordinator
    let actions: MeetingActions
    let isLive: Bool
    var includesOpen = false

    var body: some View {
        if includesOpen {
            Button("Open Meeting") { meetings.openMeetingID = record.id }
            Divider()
        }
        if !isLive {
            Button("Export as Markdown…") { actions.export(record, meetings: meetings) }
            if meetings.audioOnMac.contains(record.id), record.status.hasFinalTranscript {
                Button("Transcribe Again…") { actions.askTranscribeAgain(record, meetings: meetings) }
                    .disabled(!meetings.canTranscribeAgain(record))
            }
        }
        Button("Show in Finder") { actions.revealInFinder(record, meetings: meetings) }
        if !isLive {
            Divider()
            Button("Delete Meeting…") { actions.confirmDelete(record) }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(meetings.transcriptPasses[record.id] != nil)
        }
    }
}

/// Recorded time, without the pauses: "12:04", or "1:02:31".
struct MeetingTimer: View {
    let session: MeetingSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(MeetingTranscript.clock(session.elapsed(at: context.date)))
                .font(AppTypography.body.monospacedDigit())
        }
    }
}
