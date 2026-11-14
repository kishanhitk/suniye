import AppKit
import SwiftUI

struct MeetingTranscriptLine: Equatable {
    let id: UUID
    let time: String
    /// Nil when the meeting had no call track, so no line has a speaker.
    let speaker: MeetingTrack?
    let text: String
}

/// The notes that the user types. Each edit hands its text to `save`, which
/// stages it with the meeting's text saves.
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
            .onChange(of: draft.text) {
                if let text = draft.takeUnsaved() {
                    save(text)
                }
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
/// speaker cannot, and Return ends the edit. While the meeting's audio is on
/// the Mac, a click on a time plays from there, and the lines that play are
/// marked.
struct MeetingTranscriptView: NSViewRepresentable {
    let lines: [MeetingTranscriptLine]
    /// False while a transcript pass or a summary runs.
    var isEditable = false
    /// The lines that play.
    var marked: Set<UUID> = []
    /// Changes at each start of the playback and each move of its position,
    /// so the view follows the marked lines again after the user scrolled.
    var follow = 0
    /// Plays from the line with this id; nil when no audio can play.
    var seek: ((UUID) -> Void)?
    /// The text of each line that the user touched since the lines were last
    /// drawn, and whether the edit ended. An empty text is a line to delete
    /// when the edit ends.
    var edited: (_ texts: [UUID: String], _ ended: Bool) -> Void = { _, _ in }

    /// The text starts this far in from each side, so the band of a marked
    /// line reaches past the text. The page puts the view as far out.
    static let markOverhang: CGFloat = 6

    static func scrollView() -> NSScrollView {
        MeetingTextView.scrollable(MeetingTranscriptTextView(usingTextLayoutManager: true))
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = Self.scrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        if let textView = scrollView.documentView as? MeetingTranscriptTextView {
            context.coordinator.attach(to: textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MeetingTranscriptTextView else { return }
        context.coordinator.edited = edited
        context.coordinator.seek = seek
        textView.isEditable = isEditable
        context.coordinator.render(lines, canSeek: seek != nil, into: textView)
        context.coordinator.mark(marked, follow: follow, in: textView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var edited: (_ texts: [UUID: String], _ ended: Bool) -> Void = { _, _ in }
        var seek: ((UUID) -> Void)?
        /// The lines as the text view shows them.
        private var rendered: [MeetingTranscriptLine] = []
        /// The times are links that play.
        private var canSeek = false
        /// The lines that the user touched since the last full draw.
        private var touched: Set<UUID> = []
        private var marked: Set<UUID> = []
        private var follow = 0
        /// False after the user scrolls, until the playback starts or moves.
        private var following = true
        private weak var textView: MeetingTranscriptTextView?

        /// Sets up the text view and follows its edits, also those that an
        /// undo or a redo makes: the text view sends no change notice for them.
        func attach(to textView: MeetingTranscriptTextView) {
            Self.configure(textView)
            textView.delegate = self
            self.textView = textView
            NotificationCenter.default.addObserver(self, selector: #selector(undoManagerChanged(_:)), name: .NSUndoManagerDidUndoChange, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(undoManagerChanged(_:)), name: .NSUndoManagerDidRedoChange, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(scrolledByUser), name: NSScrollView.willStartLiveScrollNotification, object: textView.enclosingScrollView)
        }

        @objc private func undoManagerChanged(_ notification: Notification) {
            guard let textView, let undoManager = textView.undoManager, notification.object as AnyObject? === undoManager else { return }
            report(textView, ended: false)
        }

        @objc private func scrolledByUser() {
            following = false
        }

        private static func configure(_ textView: NSTextView) {
            textView.isEditable = false
            textView.isSelectable = true
            textView.isRichText = false
            textView.allowsUndo = true
            textView.drawsBackground = false
            textView.usesFindBar = true
            textView.isIncrementalSearchingEnabled = true
            textView.textContainerInset = NSSize(width: MeetingTranscriptView.markOverhang, height: 4)
            textView.textContainer?.lineFragmentPadding = 0
            // A time keeps its own look as a link; only the pointer changes,
            // and the tooltip is its own, not the link's address.
            textView.linkTextAttributes = [.cursor: NSCursor.pointingHand]
            textView.displaysLinkToolTips = false
        }

        /// Draws the lines again when they changed. The lines that the user
        /// edits come back the same, so typing never redraws.
        func render(_ lines: [MeetingTranscriptLine], canSeek: Bool, into textView: MeetingTranscriptTextView) {
            guard lines != rendered || canSeek != self.canSeek, let storage = textView.textStorage else { return }
            storage.setAttributedString(Self.text(for: lines, canSeek: canSeek))
            rendered = lines
            self.canSeek = canSeek
            touched = []
            textView.undoManager?.removeAllActions(withTarget: textView)
            textView.undoManager?.removeAllActions(withTarget: storage)
            textView.marked = Self.ranges(of: marked, in: storage)
        }

        /// Marks the lines that play. The view scrolls to them when they
        /// change or the playback moves, unless the user scrolled since the
        /// playback last started or moved.
        func mark(_ lines: Set<UUID>, follow: Int, in textView: MeetingTranscriptTextView) {
            let moved = follow != self.follow
            if moved {
                self.follow = follow
                following = true
            }
            let changed = lines != marked
            if changed, let storage = textView.textStorage {
                marked = lines
                textView.marked = Self.ranges(of: lines, in: storage)
            }
            if following, moved || changed {
                textView.scrollToMarked()
            }
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = link as? URL, let id = Self.lineID(seeking: url) else { return false }
            seek?(id)
            return true
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
            // An edit moves the lines after it.
            self.textView?.marked = Self.ranges(of: marked, in: storage)
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

        static func text(for lines: [MeetingTranscriptLine], canSeek: Bool) -> NSAttributedString {
            let output = NSMutableAttributedString()
            for line in lines {
                let time: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: bodyFont.pointSize, weight: .regular),
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .paragraphStyle: paragraph,
                    lineID: line.id,
                ]
                var label = time
                if canSeek {
                    label[.link] = seekURL(line.id)
                    label[.toolTip] = "Play from \(line.time)"
                }
                output.append(NSAttributedString(string: line.time, attributes: label))
                output.append(NSAttributedString(string: "\t", attributes: time))
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
            forEachLine(in: storage) { id, paragraph in
                if let range = textRange(ofParagraph: paragraph, in: string) {
                    texts[id] = string.substring(with: range)
                }
            }
            return texts
        }

        /// The ranges of the lines with these ids, each line with its time
        /// and speaker.
        static func ranges(of ids: Set<UUID>, in storage: NSTextStorage) -> [NSRange] {
            guard !ids.isEmpty else { return [] }
            var ranges: [NSRange] = []
            forEachLine(in: storage) { id, paragraph in
                if ids.contains(id) {
                    ranges.append(paragraph)
                }
            }
            return ranges
        }

        private static func forEachLine(in storage: NSTextStorage, _ body: (UUID, NSRange) -> Void) {
            let string = storage.string as NSString
            var location = 0
            while location < string.length {
                let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
                if let id = storage.attribute(lineID, at: paragraph.location, effectiveRange: nil) as? UUID {
                    body(id, paragraph)
                }
                location = NSMaxRange(paragraph)
            }
        }

        private static let seekScheme = "suniye-play"

        static func seekURL(_ id: UUID) -> URL {
            URL(string: "\(seekScheme):\(id.uuidString)")!
        }

        static func lineID(seeking url: URL) -> UUID? {
            guard url.scheme == seekScheme else { return nil }
            return UUID(uuidString: String(url.absoluteString.dropFirst(seekScheme.count + 1)))
        }
    }
}

/// The transcript's text view. It draws a band behind each line that plays.
final class MeetingTranscriptTextView: MeetingTextView {
    /// The ranges of the lines that play.
    var marked: [NSRange] = [] {
        didSet {
            if marked != oldValue {
                needsDisplay = true
            }
        }
    }

    private static let markColor = NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSColor.controlAccentColor.withAlphaComponent(dark ? 0.2 : 0.09)
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        Self.markColor.setFill()
        for band in bands(layingOut: false) where band.intersects(rect) {
            NSBezierPath(roundedRect: band, xRadius: 6, yRadius: 6).fill()
        }
    }

    /// Scrolls a marked line that is out of sight to a third of the way down.
    func scrollToMarked() {
        guard let band = bands(layingOut: true).first, let visible = enclosingScrollView?.documentVisibleRect, !visible.contains(band) else { return }
        // The view grows to the laid-out text only when its viewport lays
        // out; until then the scroll stops at its old height.
        textLayoutManager?.textViewportLayoutController.layoutViewport()
        scroll(NSPoint(x: 0, y: max(0, band.minY - visible.height / 3)))
    }

    /// Each marked line across the whole view, 5 pt above its first row and
    /// below its last, so two marked lines in a row meet. A drawing lays out
    /// no text: the lines that it shows are laid out. Text laid out alone
    /// gets an estimated place until the text above it is laid out, so a
    /// layout runs from the start.
    func bands(layingOut: Bool) -> [NSRect] {
        guard let layoutManager = textLayoutManager, let content = layoutManager.textContentManager else { return [] }
        let top = textContainerOrigin.y
        return marked.compactMap { range in
            guard let start = content.location(content.documentRange.location, offsetBy: range.location),
                  let end = content.location(start, offsetBy: range.length),
                  let textRange = NSTextRange(location: start, end: end)
            else { return nil }
            if layingOut, let fromStart = NSTextRange(location: content.documentRange.location, end: end) {
                layoutManager.ensureLayout(for: fromStart)
            }
            var rows = NSRect.null
            layoutManager.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, frame, _, _ in
                rows = rows.union(frame)
                return true
            }
            guard !rows.isNull else { return nil }
            return NSRect(x: bounds.minX, y: top + rows.minY - 5, width: bounds.width, height: rows.height + 10)
        }
    }
}
