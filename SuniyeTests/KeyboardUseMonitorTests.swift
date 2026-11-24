import AppKit
import Carbon.HIToolbox
import SwiftUI
import XCTest
@testable import Suniye

/// A focus edge shows only to a keyboard user: a key press shows it and a
/// click hides it.
@MainActor
final class KeyboardUseMonitorTests: XCTestCase {
    func testKeyPressMeansKeyboardAndClickMeansPointer() {
        let window = offScreenWindow()
        let other = offScreenWindow()
        defer {
            window.close()
            other.close()
        }
        let monitor = KeyboardUseMonitor.MonitorView(frame: .zero)
        window.contentView?.addSubview(monitor)

        XCTAssertEqual(monitor.usesKeyboard(after: key(kVK_DownArrow, in: window)), true, "↓")
        XCTAssertEqual(monitor.usesKeyboard(after: key(kVK_Tab, .shift, in: window)), true, "⇧Tab")
        XCTAssertEqual(monitor.usesKeyboard(after: click(.leftMouseDown, in: window)), false, "click")
        XCTAssertEqual(monitor.usesKeyboard(after: click(.rightMouseDown, in: window)), false, "right click")
        XCTAssertNil(monitor.usesKeyboard(after: key(kVK_ANSI_K, .command, in: window)), "⌘K is a shortcut")
        XCTAssertNil(monitor.usesKeyboard(after: key(kVK_DownArrow, in: other)), "another window")
    }

    /// Through the app's own event dispatch: the monitor that the view
    /// installs sets the binding, and it stops when the view leaves the window.
    func testDispatchedEventsSetTheBindingUntilTheViewLeavesTheWindow() {
        let window = offScreenWindow()
        defer { window.close() }
        let state = Flag()
        let host = NSHostingView(rootView: KeyboardUseMonitor(
            isUsingKeyboard: Binding(get: { state.isOn }, set: { state.isOn = $0 })
        ))
        host.frame = CGRect(x: 0, y: 0, width: 100, height: 40)
        window.contentView?.addSubview(host)
        host.layoutSubtreeIfNeeded()

        NSApp.sendEvent(key(kVK_DownArrow, in: window))
        XCTAssertTrue(state.isOn, "a key press")
        NSApp.sendEvent(click(.leftMouseDown, in: window))
        XCTAssertFalse(state.isOn, "a click")
        host.removeFromSuperview()
        NSApp.sendEvent(key(kVK_DownArrow, in: window))
        XCTAssertFalse(state.isOn, "a key press after the view left the window")
    }

    private final class Flag {
        var isOn = false
    }

    private func key(_ code: Int, _ modifiers: NSEvent.ModifierFlags = [], in window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: window.windowNumber, context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: UInt16(code)
        )!
    }

    private func click(_ type: NSEvent.EventType, in window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(
            with: type, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        )!
    }

    private func offScreenWindow() -> NSWindow {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        return window
    }
}
