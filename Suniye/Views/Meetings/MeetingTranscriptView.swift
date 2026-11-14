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
    /// The transcript waits for the transcript of another meeting: no bar yet.
    var isWaiting = false
    var title = "Finishing the transcript…"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(isWaiting ? "Waiting for another transcript…" : title)
                    .font(AppTypography.body)
                    .foregroundStyle(MainWindowPalette.secondaryText)
            }
            if !isWaiting {
                ProgressView(value: progress?.fraction ?? 0)
                    .progressViewStyle(.linear)
                    .frame(width: 280)
            }
            if !isWaiting, let progress {
                Text(progress.minutesText)
                    .font(AppTypography.caption)
                    .foregroundStyle(MainWindowPalette.secondaryText)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The transcript as one text view, so a selection can cross lines and ⌘F
/// opens the native find bar. The text of a line can be edited; its time and
/// speaker cannot, and Return ends the edit.
struct MeetingTranscriptView: NSViewRepresentable {
    let lines: [MeetingTranscriptLine]
    /// False while a transcript pass or a summary runs.
    var isEditable = false
    /// The text of each line that the user touched since the lines were last
    /// drawn, and whether the edit ended. An empty text is a line to delete
    /// when the edit ends.
    var edited: (_ texts: [UUID: String], _ ended: Bool) -> Void = { _, _ in }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = MeetingTextView.scrollable()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        if let textView = scrollView.documentView as? NSTextView {
            context.coordinator.attach(to: textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.edited = edited
        textView.isEditable = isEditable
        context.coordinator.render(lines, into: textView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var edited: (_ texts: [UUID: String], _ ended: Bool) -> Void = { _, _ in }
        /// The lines as the text view shows them.
        private var rendered: [MeetingTranscriptLine] = []
        /// The lines that the user touched since the last full draw.
        private var touched: Set<UUID> = []
        private weak var textView: NSTextView?

        /// Sets up the text view and follows its edits, also those that an
        /// undo or a redo makes: the text view sends no change notice for them.
        func attach(to textView: NSTextView) {
            Self.configure(textView)
            textView.delegate = self
            self.textView = textView
            NotificationCenter.default.addObserver(self, selector: #selector(undoManagerChanged(_:)), name: .NSUndoManagerDidUndoChange, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(undoManagerChanged(_:)), name: .NSUndoManagerDidRedoChange, object: nil)
        }

        @objc private func undoManagerChanged(_ notification: Notification) {
            guard let textView, let undoManager = textView.undoManager, notification.object as AnyObject? === undoManager else { return }
            report(textView, ended: false)
        }

        private static func configure(_ textView: NSTextView) {
            textView.isEditable = false
            textView.isSelectable = true
            textView.isRichText = false
            textView.allowsUndo = true
            textView.drawsBackground = false
            textView.usesFindBar = true
            textView.isIncrementalSearchingEnabled = true
            textView.textContainerInset = NSSize(width: 0, height: 4)
            textView.textContainer?.lineFragmentPadding = 0
        }

        /// Draws the lines again when they changed. The lines that the user
        /// edits come back the same, so typing never redraws.
        func render(_ lines: [MeetingTranscriptLine], into textView: NSTextView) {
            guard lines != rendered, let storage = textView.textStorage else { return }
            storage.setAttributedString(Self.text(for: lines))
            rendered = lines
            touched = []
            textView.undoManager?.removeAllActions(withTarget: textView)
            textView.undoManager?.removeAllActions(withTarget: storage)
        }

        // MARK: - Edits

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString text: String?) -> Bool {
            guard let text else { return true }
            let string = textView.string as NSString
            guard let editable = Self.editableRange(in: string, around: range), NSMaxRange(range) <= NSMaxRange(editable), range.location >= editable.location else {
                NSSound.beep()
                return false
            }
            if text.contains(where: \.isNewline) {
                let line = text.split(whereSeparator: \.isNewline).joined(separator: " ")
                textView.insertText(line, replacementRange: range)
                return false
            }
            textView.typingAttributes = Self.textAttributes
            return true
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertLineBreak(_:)),
                 #selector(NSResponder.insertParagraphSeparator(_:)), #selector(NSResponder.cancelOperation(_:)):
                textView.window?.makeFirstResponder(nil)
                return true
            default:
                return false
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            report(textView, ended: false)
        }

        func textDidEndEditing(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, !touched.isEmpty else { return }
            report(textView, ended: true)
        }

        private func report(_ textView: NSTextView, ended: Bool) {
            guard let storage = textView.textStorage else { return }
            let current = Self.lineTexts(in: storage)
            for (id, text) in current where rendered.first(where: { $0.id == id })?.text != text {
                touched.insert(id)
            }
            guard !touched.isEmpty else { return }
            let texts = current.filter { touched.contains($0.key) }
            rendered = rendered.map { line in
                guard let text = texts[line.id] else { return line }
                return MeetingTranscriptLine(id: line.id, time: line.time, speaker: line.speaker, text: text)
            }
            edited(texts, ended)
        }

        // MARK: - Text

        private static let lineID = NSAttributedString.Key("SuniyeMeetingLineID")

        private static let paragraph: NSParagraphStyle = {
            let paragraph = NSMutableParagraphStyle()
            paragraph.tabStops = [NSTextTab(textAlignment: .left, location: 64), NSTextTab(textAlignment: .left, location: 116)]
            paragraph.headIndent = 116
            paragraph.paragraphSpacing = 10
            return paragraph
        }()

        private static var bodyFont: NSFont {
            NSFont.preferredFont(forTextStyle: .body)
        }

        static var textAttributes: [NSAttributedString.Key: Any] {
            [.font: bodyFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
        }

        static func text(for lines: [MeetingTranscriptLine]) -> NSAttributedString {
            let output = NSMutableAttributedString()
            for line in lines {
                output.append(NSAttributedString(string: line.time + "\t", attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: bodyFont.pointSize, weight: .regular),
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .paragraphStyle: paragraph,
                    lineID: line.id,
                ]))
                output.append(NSAttributedString(string: (line.speaker?.speakerLabel ?? "") + "\t", attributes: [
                    .font: NSFont.systemFont(ofSize: bodyFont.pointSize, weight: .semibold),
                    .foregroundColor: line.speaker == .you ? NSColor.controlAccentColor : NSColor.secondaryLabelColor,
                    .paragraphStyle: paragraph,
                ]))
                output.append(NSAttributedString(string: line.text + "\n", attributes: textAttributes))
            }
            return output
        }

        /// The text of the line that holds `range`: from after the speaker's
        /// tab to the line end. Nil when `range` is in more than one line.
        static func editableRange(in string: NSString, around range: NSRange) -> NSRange? {
            let start = string.paragraphRange(for: NSRange(location: range.location, length: 0))
            let end = string.paragraphRange(for: NSRange(location: NSMaxRange(range), length: 0))
            guard start == end else { return nil }
            return textRange(ofParagraph: start, in: string)
        }

        private static func textRange(ofParagraph paragraph: NSRange, in string: NSString) -> NSRange? {
            let first = string.range(of: "\t", range: paragraph)
            guard first.location != NSNotFound else { return nil }
            let afterFirst = NSRange(location: NSMaxRange(first), length: NSMaxRange(paragraph) - NSMaxRange(first))
            let second = string.range(of: "\t", range: afterFirst)
            guard second.location != NSNotFound else { return nil }
            var end = NSMaxRange(paragraph)
            if end > paragraph.location, string.character(at: end - 1) == 0x0A {
                end -= 1
            }
            return NSRange(location: NSMaxRange(second), length: end - NSMaxRange(second))
        }

        /// The text of each line, by line id.
        static func lineTexts(in storage: NSTextStorage) -> [UUID: String] {
            let string = storage.string as NSString
            var texts: [UUID: String] = [:]
            var location = 0
            while location < string.length {
                let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
                if let id = storage.attribute(lineID, at: paragraph.location, effectiveRange: nil) as? UUID,
                   let range = textRange(ofParagraph: paragraph, in: string) {
                    texts[id] = string.substring(with: range)
                }
                location = NSMaxRange(paragraph)
            }
            return texts
        }
    }
}
