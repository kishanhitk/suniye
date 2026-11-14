import AppKit
import SwiftUI

/// The meeting title, edited where it stands. A click puts the caret where
/// you click. Return or a click elsewhere keeps the new title, Esc drops it,
/// and an empty title goes back to the old one.
///
/// A one-line text view, not a text field: a text field in this window draws
/// its text twice, darker than the label it replaces.
struct MeetingTitleField: NSViewRepresentable {
    let title: String
    let rename: (String) -> Void

    static let font = NSFont.preferredFont(forTextStyle: .largeTitle)
    static let height = ceil(font.ascender - font.descender + font.leading)

    static var attributes: [NSAttributedString.Key: Any] {
        [.font: font, .kern: AppTypography.transcriptsHeadlineTracking, .foregroundColor: NSColor.labelColor]
    }

    func makeNSView(context: Context) -> NSScrollView {
        Self.makeView(title: title, delegate: context.coordinator)
    }

    static func makeView(title: String, delegate: NSTextViewDelegate) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        let textView = TitleTextView()
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.maximumNumberOfLines = 1
        textView.typingAttributes = attributes
        textView.textStorage?.setAttributedString(NSAttributedString(string: title, attributes: attributes))
        textView.setAccessibilityLabel("Title")
        textView.delegate = delegate
        scrollView.documentView = textView
        textView.showsWholeTitle(false)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.title = title
        context.coordinator.rename = rename
        guard let textView = scrollView.documentView as? TitleTextView else { return }
        textView.showsWholeTitle(textView.window?.firstResponder === textView)
        guard textView.window?.firstResponder !== textView, textView.string != title else { return }
        // A new title fades in, as when the summary names the meeting.
        let fade = CATransition()
        fade.type = .fade
        fade.duration = 0.2
        textView.wantsLayer = true
        textView.layer?.add(fade, forKey: "title")
        textView.textStorage?.setAttributedString(NSAttributedString(string: title, attributes: Self.attributes))
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: Self.height)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(title: title, rename: rename)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var title: String
        var rename: (String) -> Void
        private var dropping = false
        /// The user typed in this edit. A summary can set a new title while
        /// the field has focus; a click in and out keeps that title.
        private var changed = false

        init(title: String, rename: @escaping (String) -> Void) {
            self.title = title
            self.rename = rename
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertLineBreak(_:)),
                 #selector(NSResponder.insertParagraphSeparator(_:)):
                textView.window?.makeFirstResponder(nil)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                dropping = true
                textView.window?.makeFirstResponder(nil)
                return true
            case #selector(NSResponder.insertTab(_:)):
                textView.window?.selectNextKeyView(nil)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                textView.window?.selectPreviousKeyView(nil)
                return true
            default:
                return false
            }
        }

        /// A pasted title with line breaks becomes one line.
        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString text: String?) -> Bool {
            guard let text, text.contains(where: \.isNewline) else { return true }
            textView.insertText(text.split(whereSeparator: \.isNewline).joined(separator: " "), replacementRange: range)
            return false
        }

        func textDidChange(_ notification: Notification) {
            changed = true
        }

        func textDidEndEditing(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let typed = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if dropping || !changed || typed.isEmpty || typed == title {
                textView.textStorage?.setAttributedString(NSAttributedString(string: title, attributes: MeetingTitleField.attributes))
            } else {
                rename(typed)
            }
            dropping = false
            changed = false
        }
    }
}

/// Shows the whole title on one line while it is edited, scrolled to the
/// caret, and cuts it with "…" at the end otherwise.
final class TitleTextView: MeetingTextView {
    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            showsWholeTitle(true)
        }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            showsWholeTitle(false)
        }
        return resigned
    }

    func showsWholeTitle(_ whole: Bool) {
        guard let container = textContainer, let clip = enclosingScrollView?.contentView else { return }
        container.lineBreakMode = whole ? .byClipping : .byTruncatingTail
        container.widthTracksTextView = !whole
        isHorizontallyResizable = whole
        autoresizingMask = whole ? [] : [.width]
        isVerticallyResizable = false
        if whole {
            container.size = NSSize(width: CGFloat.greatestFiniteMagnitude, height: MeetingTitleField.height)
            maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: MeetingTitleField.height)
            minSize = NSSize(width: clip.bounds.width, height: MeetingTitleField.height)
            sizeToFit()
            scrollRangeToVisible(selectedRange())
        } else {
            setFrameSize(NSSize(width: clip.bounds.width, height: MeetingTitleField.height))
            container.size = NSSize(width: clip.bounds.width, height: MeetingTitleField.height)
            clip.scroll(to: .zero)
        }
    }
}
