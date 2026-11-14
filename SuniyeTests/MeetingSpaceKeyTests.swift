import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Suniye

@MainActor
final class MeetingSpaceKeyTests: XCTestCase {
    func testSpacePlaysOnlyWhileNoTextThatCanBeEditedHasTheKeyboard() {
        let window = offScreenWindow()
        let other = offScreenWindow()
        defer {
            window.close()
            other.close()
        }
        let monitor = MeetingSpaceKey.MonitorView(frame: .zero)
        let text = NSTextView(frame: CGRect(x: 0, y: 0, width: 100, height: 40))
        window.contentView?.addSubview(monitor)
        window.contentView?.addSubview(text)

        func key(_ modifiers: NSEvent.ModifierFlags = [], code: Int = kVK_Space, in target: NSWindow? = nil) -> NSEvent {
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                windowNumber: (target ?? window).windowNumber, context: nil,
                characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: UInt16(code)
            )!
        }

        window.makeFirstResponder(nil)
        XCTAssertTrue(monitor.handles(key()), "no focus")
        XCTAssertFalse(monitor.handles(key(.command)), "⌘Space")
        XCTAssertFalse(monitor.handles(key(code: kVK_Return)), "another key")
        XCTAssertFalse(monitor.handles(key(in: other)), "another window")
        XCTAssertTrue(window.makeFirstResponder(text))
        XCTAssertFalse(monitor.handles(key()), "a text that can be edited takes the space")
        text.isEditable = false
        XCTAssertTrue(monitor.handles(key()), "a read-only text does not take it")
    }

    private func offScreenWindow() -> NSWindow {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        return window
    }
}
