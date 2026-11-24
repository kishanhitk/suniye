import AppKit
import SwiftUI

/// Tells whether the user works in this window by keyboard. A key press sets
/// it and a click clears it: the rule browsers use to show a focus ring only
/// to keyboard users. Shortcuts with ⌘, ⌃ or ⌥ change nothing.
struct KeyboardUseMonitor: NSViewRepresentable {
    @Binding var isUsingKeyboard: Bool

    func makeNSView(context: Context) -> MonitorView {
        MonitorView()
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.report = { usesKeyboard in
            if isUsingKeyboard != usesKeyboard {
                isUsingKeyboard = usesKeyboard
            }
        }
    }

    final class MonitorView: NSView {
        var report: (Bool) -> Void = { _ in }
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] event in
                if let self, let usesKeyboard = self.usesKeyboard(after: event) {
                    self.report(usesKeyboard)
                }
                return event
            }
        }

        /// True after a key press, false after a click, and nil for an event
        /// that says nothing about it: a shortcut, or an event in another window.
        private func usesKeyboard(after event: NSEvent) -> Bool? {
            guard let window, event.window === window else { return nil }
            switch event.type {
            case .keyDown:
                return event.modifierFlags.isDisjoint(with: [.command, .control, .option]) ? true : nil
            case .leftMouseDown, .rightMouseDown, .otherMouseDown:
                return false
            default:
                return nil
            }
        }
    }
}
