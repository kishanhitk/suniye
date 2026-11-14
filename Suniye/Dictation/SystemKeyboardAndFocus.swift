import ApplicationServices
import CoreGraphics

enum SystemKeyboard {
    /// Posts a key press and its release. Returns false when macOS cannot create the events.
    static func post(_ keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            return false
        }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}

enum SystemFocus {
    /// The element with keyboard focus in any app, and the status of the query.
    /// `.noValue` means the app publishes no focus information at all.
    static func focusedElement() -> (status: AXError, element: AXUIElement?) {
        var focusedElement: AnyObject?
        let status = AXUIElementCopyAttributeValue(
            AXUIElementCreateSystemWide(),
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        guard status == .success,
              let focusedElement,
              CFGetTypeID(focusedElement) == AXUIElementGetTypeID() else {
            return (status, nil)
        }
        return (status, (focusedElement as! AXUIElement))
    }
}
