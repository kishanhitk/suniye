import AppKit
import SwiftUI

/// Behind-window blur. SwiftUI materials only blur content within the same
/// window; blurring what is *behind* the window needs NSVisualEffectView with
/// `.behindWindow` blending. A non-zero `cornerRadius` masks the blur region via
/// `maskImage` (a plain CALayer mask does not constrain behind-window blur).
struct BehindWindowBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var state: NSVisualEffectView.State = .followsWindowActiveState
    var cornerRadius: CGFloat = 0

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = state
        if cornerRadius > 0 {
            view.maskImage = .roundedRectMask(cornerRadius: cornerRadius)
        }
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private extension NSImage {
    static func roundedRectMask(cornerRadius: CGFloat) -> NSImage {
        let edge = cornerRadius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
        image.resizingMode = .stretch
        return image
    }
}
