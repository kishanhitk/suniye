import AppKit
import SwiftUI

struct MeetingTranscriptLine: Equatable {
    let id: UUID
    let time: String
    /// Nil when the meeting had no call track, so no line has a speaker.
    let speaker: MeetingTrack?
    let text: String
}

/// The notes that the user types, saved a moment after each edit and when
/// the editor goes away.
struct MeetingNotesEditor: View {
    @Binding var draft: MeetingNotesDraft
    let save: (String) -> Void

    /// TextEditor's text view starts its text this far in, so the notes
    /// would sit right of the tabs above them.
    private static let textInset = NSTextContainer().lineFragmentPadding

    var body: some View {
        TextEditor(text: $draft.text)
            .font(AppTypography.body)
            .foregroundStyle(.primary)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, -Self.textInset)
            .overlay(alignment: .topLeading) {
                if draft.text.isEmpty {
                    Text("Notes")
                        .font(AppTypography.body)
                        .foregroundStyle(MainWindowPalette.tertiaryText)
                        .allowsHitTesting(false)
                }
            }
            .task(id: draft.text) {
                try? await Task.sleep(for: .milliseconds(750))
                guard !Task.isCancelled else { return }
                saveUnsaved()
            }
            .onDisappear {
                saveUnsaved()
            }
    }

    private func saveUnsaved() {
        if let text = draft.takeUnsaved() {
            save(text)
        }
    }
}

/// "Finishing the transcript…" and the minutes of audio done, while the
/// transcript is written after the recording.
struct MeetingTranscriptProgressView: View {
    /// Nil until the transcript reports its first step.
    let progress: MeetingTranscriptProgress?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Finishing the transcript…")
                    .font(AppTypography.body)
                    .foregroundStyle(MainWindowPalette.secondaryText)
            }
            ProgressView(value: progress?.fraction ?? 0)
                .progressViewStyle(.linear)
                .frame(width: 280)
            if let progress {
                Text(progress.minutesText)
                    .font(AppTypography.caption)
                    .foregroundStyle(MainWindowPalette.secondaryText)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The transcript as one read-only text view, so a selection can cross lines
/// and ⌘F opens the native find bar.
struct MeetingTranscriptView: NSViewRepresentable {
    let lines: [MeetingTranscriptLine]

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        if let textView = scrollView.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.drawsBackground = false
            textView.usesFindBar = true
            textView.isIncrementalSearchingEnabled = true
            textView.textContainerInset = NSSize(width: 0, height: 4)
            textView.textContainer?.lineFragmentPadding = 0
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.render(lines, into: textView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        private var rendered: [UUID] = []

        /// Draws the lines again when they changed.
        func render(_ lines: [MeetingTranscriptLine], into textView: NSTextView) {
            let ids = lines.map(\.id)
            guard ids != rendered, let storage = textView.textStorage else { return }
            storage.setAttributedString(Self.text(for: lines))
            rendered = ids
        }

        private static func text(for lines: [MeetingTranscriptLine]) -> NSAttributedString {
            let paragraph = NSMutableParagraphStyle()
            paragraph.tabStops = [NSTextTab(textAlignment: .left, location: 64), NSTextTab(textAlignment: .left, location: 116)]
            paragraph.headIndent = 116
            paragraph.paragraphSpacing = 10
            let body = NSFont.preferredFont(forTextStyle: .body)
            let output = NSMutableAttributedString()
            for line in lines {
                output.append(NSAttributedString(string: line.time + "\t", attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: body.pointSize, weight: .regular),
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .paragraphStyle: paragraph,
                ]))
                output.append(NSAttributedString(string: (line.speaker?.speakerLabel ?? "") + "\t", attributes: [
                    .font: NSFont.systemFont(ofSize: body.pointSize, weight: .semibold),
                    .foregroundColor: line.speaker == .you ? NSColor.controlAccentColor : NSColor.secondaryLabelColor,
                    .paragraphStyle: paragraph,
                ]))
                output.append(NSAttributedString(string: line.text + "\n", attributes: [
                    .font: body,
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: paragraph,
                ]))
            }
            return output
        }
    }
}
