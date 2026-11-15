import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Space plays and pauses while this view is in the key window and no text
/// that can be edited has the keyboard. A key equivalent would take each
/// space from the editors.
struct MeetingSpaceKey: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> MonitorView {
        MonitorView()
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.action = action
    }

    final class MonitorView: NSView {
        var action: () -> Void = {}
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.handles(event) else { return event }
                self.action()
                return nil
            }
        }

        func handles(_ event: NSEvent) -> Bool {
            guard let window, event.window === window, event.keyCode == UInt16(kVK_Space),
                  event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
            else { return false }
            if let text = window.firstResponder as? NSText {
                return !text.isEditable
            }
            return !(window.firstResponder is NSControl)
        }
    }
}
