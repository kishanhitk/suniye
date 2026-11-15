import AppKit
import SwiftUI

/// A thinner, quieter overlay scroller.
///
/// AppKit exposes no app-wide scroller appearance, and SwiftUI's `ScrollView`
/// only offers show/hide. So the knob is drawn here and installed on the
/// `NSScrollView`s SwiftUI creates.
final class SubtleScroller: NSScroller {
    private static let trackWidth: CGFloat = 9
    private static let knobWidth: CGFloat = 4

    override class func scrollerWidth(
        for controlSize: NSControl.ControlSize,
        scrollerStyle: NSScroller.Style
    ) -> CGFloat {
        trackWidth
    }

    override class var isCompatibleWithOverlayScrollers: Bool { true }

    /// No track: the slot is what makes a scrollbar read as a piece of chrome.
    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}

    override func drawKnob() {
        let knobRect = rect(for: .knob)
        guard knobRect.width > 0, knobRect.height > 0 else {
            return
        }

        // NSScroller does not publish its orientation; the track's own shape is
        // the only thing that says which way it runs.
        let isVertical = bounds.height >= bounds.width
        let rect = isVertical
            ? NSRect(
                x: knobRect.midX - Self.knobWidth / 2,
                y: knobRect.minY + 2,
                width: Self.knobWidth,
                height: max(Self.knobWidth, knobRect.height - 4)
            )
            : NSRect(
                x: knobRect.minX + 2,
                y: knobRect.midY - Self.knobWidth / 2,
                width: max(Self.knobWidth, knobRect.width - 4),
                height: Self.knobWidth
            )

        knobColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: Self.knobWidth / 2, yRadius: Self.knobWidth / 2).fill()
    }

    private var knobColor: NSColor {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark
            ? NSColor.white.withAlphaComponent(0.28)
            : NSColor.black.withAlphaComponent(0.24)
    }

    /// Restyles every scroll view in a window, including the ones inside
    /// `TextEditor`, which SwiftUI never exposes.
    static func apply(in view: NSView) {
        if let scrollView = view as? NSScrollView {
            scrollView.scrollerStyle = .overlay

            if scrollView.hasVerticalScroller, !(scrollView.verticalScroller is SubtleScroller) {
                scrollView.verticalScroller = SubtleScroller()
            }

            if scrollView.hasHorizontalScroller, !(scrollView.horizontalScroller is SubtleScroller) {
                scrollView.horizontalScroller = SubtleScroller()
            }
        }

        for subview in view.subviews {
            apply(in: subview)
        }
    }
}

/// Walks up to the scroll view this sits inside. Used where the scroll view is
/// created later than the window sweep runs — switching to a settings page, for
/// instance, builds its scroll view long after the window appeared.
private struct EnclosingScrollerInstaller: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            var ancestor = nsView.superview
            while let current = ancestor {
                if let scrollView = current as? NSScrollView {
                    SubtleScroller.apply(in: scrollView)
                    return
                }
                ancestor = current.superview
            }
        }
    }
}

private struct SubtleScrollerInstaller: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // After this pass of layout, so the scroll views exist to be found.
        DispatchQueue.main.async {
            guard let root = nsView.window?.contentView else {
                return
            }
            SubtleScroller.apply(in: root)
        }
    }
}

extension View {
    /// Applies the thin scroller to every scroll view in this view's window.
    /// Attach once per window or sheet root.
    func subtleScrollers() -> some View {
        background(SubtleScrollerInstaller().frame(width: 0, height: 0))
    }

    /// Applies it to the scroll view this content is inside. Attach to scrolling
    /// content that appears after its window does.
    func subtleEnclosingScroller() -> some View {
        background(EnclosingScrollerInstaller().frame(width: 0, height: 0))
    }
}
