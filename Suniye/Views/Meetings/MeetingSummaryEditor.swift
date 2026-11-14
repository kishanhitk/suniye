import AppKit
import SwiftUI

/// The summary as one text view: "## " headings, paragraphs and "- " items,
/// laid out as the page drew them before they could be edited. It uses
/// TextKit 1, which keeps a list going when you press Return in an item and
/// ends it at Return in an empty item. Each edit comes back as Markdown.
struct MeetingSummaryEditor: NSViewRepresentable {
    let markdown: String
    var isEditable = false
    var edited: (_ markdown: String, _ ended: Bool) -> Void = { _, _ in }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = MeetingTextView.scrollable(textKit2: false)
        scrollView.drawsBackground = false
        if let textView = scrollView.documentView as? NSTextView {
            context.coordinator.attach(to: textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.edited = edited
        textView.isEditable = isEditable
        context.coordinator.render(markdown, into: textView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, NSLayoutManagerDelegate {
        var edited: (_ markdown: String, _ ended: Bool) -> Void = { _, _ in }
        /// The Markdown that the page passed in last; the page passes each
        /// edit back, so an edit draws nothing again.
        private var source: String?
        /// The Markdown of the text as drawn, and as the user left it.
        private var drawn = ""
        private var shown = ""

        func attach(to textView: NSTextView) {
            textView.isEditable = false
            textView.isSelectable = true
            textView.isRichText = true
            textView.allowsUndo = true
            textView.drawsBackground = false
            textView.usesFindBar = true
            textView.isIncrementalSearchingEnabled = true
            textView.textContainerInset = NSSize(width: 0, height: 4)
            textView.textContainer?.lineFragmentPadding = 0
            textView.typingAttributes = Style.paragraph
            textView.delegate = self
            textView.layoutManager?.delegate = self
        }

        func render(_ markdown: String, into textView: NSTextView) {
            guard markdown != source, let storage = textView.textStorage else { return }
            storage.setAttributedString(Style.text(for: MeetingSummaryBlock.parse(markdown)))
            source = markdown
            drawn = Style.markdown(from: storage)
            shown = drawn
            textView.undoManager?.removeAllActions(withTarget: textView)
            textView.undoManager?.removeAllActions(withTarget: storage)
        }

        /// A line with emoji or another script keeps the body's baseline,
        /// as the page drew it: TextKit 1 would set it by the taller font.
        nonisolated func layoutManager(
            _ layoutManager: NSLayoutManager,
            shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
            lineFragmentUsedRect: UnsafeMutablePointer<NSRect>,
            baselineOffset: UnsafeMutablePointer<CGFloat>,
            in textContainer: NSTextContainer,
            forGlyphRange glyphRange: NSRange
        ) -> Bool {
            guard let storage = layoutManager.textStorage else { return false }
            let characters = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            var base: NSFont?
            var fallback = false
            storage.enumerateAttribute(.font, in: characters) { value, _, _ in
                guard let font = value as? NSFont else { return }
                if base == nil {
                    base = font
                } else if font.familyName != base?.familyName {
                    fallback = true
                }
            }
            guard fallback, let base else { return false }
            let above = lineFragmentUsedRect.pointee.minY - lineFragmentRect.pointee.minY
            baselineOffset.pointee = above + layoutManager.defaultBaselineOffset(for: base)
            return true
        }

        // MARK: - Edits

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                // Return at the end of a heading starts a paragraph, not a
                // second heading.
                guard Style.isHeading(textView.textStorage, at: textView.selectedRange().location) else { return false }
                textView.insertText("\n", replacementRange: textView.selectedRange())
                textView.typingAttributes = Style.paragraph
                return true
            case #selector(NSResponder.cancelOperation(_:)):
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
            guard let textView = notification.object as? NSTextView else { return }
            report(textView, ended: true)
        }

        /// A change reports the new Markdown; the end of an edit reports it
        /// again only when the user changed something, so a click in and out
        /// does not count as an edit.
        private func report(_ textView: NSTextView, ended: Bool) {
            guard let storage = textView.textStorage else { return }
            Style.colorMarkers(in: storage)
            let markdown = Style.markdown(from: storage)
            if markdown != shown {
                shown = markdown
                source = markdown
                edited(markdown, ended)
            } else if ended, shown != drawn {
                edited(shown, true)
            }
        }
    }

    /// The fonts, colors and spacing of the summary blocks, and the way back
    /// to Markdown.
    enum Style {
        static let heading = NSAttributedString.Key("SuniyeSummaryHeading")
        static let bodyFont = NSFont.preferredFont(forTextStyle: .body)
        static let headingFont = NSFont.preferredFont(forTextStyle: .headline)
        /// The page drew 8 pt between blocks, and 10 pt more above a heading.
        static let blockSpacing: CGFloat = 8
        static let headingTop: CGFloat = 10
        /// The bullet, then 8 pt, then the item text.
        static let itemIndent = ceil(("•" as NSString).size(withAttributes: [.font: bodyFont]).width * 2) / 2 + 8
        /// The page kept every line at the body's height, also a line with
        /// emoji or another script, and moved a word down rather than leave
        /// it alone on the last line.
        static let lineHeight = NSLayoutManager().defaultLineHeight(for: bodyFont)

        static func style(spacingBefore: CGFloat = 0) -> NSMutableParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.paragraphSpacing = blockSpacing
            style.paragraphSpacingBefore = spacingBefore
            style.maximumLineHeight = lineHeight
            style.lineBreakStrategy = .standard
            return style
        }

        static var paragraph: [NSAttributedString.Key: Any] {
            [.font: bodyFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: style()]
        }

        static func text(for blocks: [MeetingSummaryBlock]) -> NSAttributedString {
            let output = NSMutableAttributedString()
            for (index, block) in blocks.enumerated() {
                let end = index == blocks.count - 1 ? "" : "\n"
                switch block {
                case let .heading(text):
                    output.append(NSAttributedString(string: text + end, attributes: [
                        .font: headingFont, .foregroundColor: NSColor.labelColor,
                        .paragraphStyle: style(spacingBefore: index == 0 ? 0 : headingTop), heading: true,
                    ]))
                case let .item(text):
                    output.append(item(text + end))
                case let .paragraph(text):
                    output.append(NSAttributedString(string: text + end, attributes: paragraph))
                }
            }
            colorMarkers(in: output)
            return output
        }

        private static func item(_ text: String) -> NSAttributedString {
            let style = style()
            style.textLists = [NSTextList(markerFormat: .disc, options: 0)]
            style.tabStops = [NSTextTab(textAlignment: .left, location: 0.01), NSTextTab(textAlignment: .left, location: itemIndent)]
            style.headIndent = itemIndent
            return NSAttributedString(string: "\t•\t" + text, attributes: [.font: bodyFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: style])
        }

        /// The bullets in the secondary color, also those that AppKit adds
        /// for a new item.
        static func colorMarkers(in storage: NSMutableAttributedString) {
            let string = storage.string as NSString
            string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in
                guard range.length > 0,
                      let style = storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle,
                      !style.textLists.isEmpty
                else { return }
                let marker = markerRange(in: string, paragraph: range)
                if marker.length > 0 {
                    storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: marker)
                }
            }
        }

        /// "\t•\t" at the start of an item.
        private static func markerRange(in string: NSString, paragraph: NSRange) -> NSRange {
            let tab = string.range(of: "\t", options: [], range: NSRange(location: paragraph.location + 1, length: max(0, paragraph.length - 1)))
            guard string.length > paragraph.location, string.character(at: paragraph.location) == 0x09, tab.location != NSNotFound else {
                return NSRange(location: paragraph.location, length: 0)
            }
            return NSRange(location: paragraph.location, length: NSMaxRange(tab) - paragraph.location)
        }

        static func isHeading(_ storage: NSTextStorage?, at location: Int) -> Bool {
            guard let storage, storage.length > 0 else { return false }
            let index = min(max(location - 1, 0), storage.length - 1)
            return storage.attribute(heading, at: index, effectiveRange: nil) as? Bool == true
        }

        static func markdown(from storage: NSAttributedString) -> String {
            let string = storage.string as NSString
            var lines: [String] = []
            string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: .byParagraphs) { text, range, _, _ in
                guard let text, range.length > 0 else { return }
                let style = storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
                if let style, !style.textLists.isEmpty {
                    let marker = markerRange(in: string, paragraph: range)
                    let item = string.substring(with: NSRange(location: NSMaxRange(marker), length: NSMaxRange(range) - NSMaxRange(marker)))
                    if !item.trimmingCharacters(in: .whitespaces).isEmpty {
                        lines.append("- " + item)
                    }
                } else if storage.attribute(heading, at: range.location, effectiveRange: nil) as? Bool == true {
                    if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                        lines.append("## " + text)
                    }
                } else if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                    lines.append(text)
                }
            }
            return lines.joined(separator: "\n")
        }
    }
}
