import AppKit

/// A text view of the meeting page. A text view that leaves its window
/// during an edit does not end the edit, so this one ends it first: the page
/// would otherwise drop what the user typed.
class MeetingTextView: NSTextView {
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, window?.firstResponder === self {
            window?.makeFirstResponder(nil)
        }
        super.viewWillMove(toWindow: newWindow)
    }

    /// `textView` in a scroll view that grows down with its text, as
    /// `NSTextView.scrollableTextView()` builds it.
    static func scrollable(_ textView: MeetingTextView) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        let size = scrollView.contentSize
        textView.frame = NSRect(origin: .zero, size: size)
        textView.minSize = NSSize(width: 0, height: size.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: size.width, height: CGFloat.greatestFiniteMagnitude)
        scrollView.documentView = textView
        return scrollView
    }
}
