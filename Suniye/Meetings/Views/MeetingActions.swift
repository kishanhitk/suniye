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
    var renaming: MeetingRecord?
    var renameText = ""
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

    func rename(_ record: MeetingRecord) {
        renameText = record.title
        renaming = record
    }

    func export(_ record: MeetingRecord, meetings: MeetingCoordinator) {
        Task {
            let markdown = MeetingExport.markdown(
                record: record,
                summary: await meetings.summary(of: record.id),
                notes: await meetings.notes(of: record.id) ?? "",
                segments: await meetings.transcript(of: record.id)
            )
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "\(record.title).md"
            panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                AppLogger.shared.log(.error, "meeting export failed error=\(error.localizedDescription)")
                failure = MeetingActionFailure(title: "Couldn’t export the meeting", message: error.localizedDescription)
            }
        }
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
                "Rename Meeting",
                isPresented: Binding(get: { actions.renaming != nil }, set: { if !$0 { actions.renaming = nil } }),
                presenting: actions.renaming
            ) { record in
                TextField("Title", text: $actions.renameText)
                Button("Rename") {
                    let title = actions.renameText
                    Task { await meetings.rename(record.id, to: title) }
                }
                Button("Cancel", role: .cancel) {}
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
    /// What Copy Notice puts on the clipboard, for the user to tell the
    /// other people in the call.
    static let noticeSentence = "I’m recording this call to take notes. The recording stays on my computer."

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
        if isLive {
            Button("Copy Notice") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(Self.noticeSentence, forType: .string)
            }
        } else {
            Button("Export as Markdown…") { actions.export(record, meetings: meetings) }
        }
        Button("Rename…") { actions.rename(record) }
        Button("Show in Finder") { actions.revealInFinder(record, meetings: meetings) }
        if !isLive {
            Divider()
            Button("Delete Meeting…") { actions.confirmDelete(record) }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(record.status == .finishing)
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
