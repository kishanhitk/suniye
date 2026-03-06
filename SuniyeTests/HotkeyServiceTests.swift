import XCTest
@testable import Suniye

final class HotkeyServiceTests: XCTestCase {
    func testKeyComboPressAndReleaseTransitions() {
        let shortcut = HotkeyShortcut(keyCode: 49, modifiers: [.command])
        let machine = HotkeyStateMachine(shortcut: shortcut)

        let press = machine.process(
            HotkeyInputEvent(type: .keyDown, keyCode: 49, modifiers: [.command])
        )
        XCTAssertEqual(press, .pressed)

        let release = machine.process(
            HotkeyInputEvent(type: .keyUp, keyCode: 49, modifiers: [])
        )
        XCTAssertEqual(release, .released)
    }

    func testModifierOnlyShortcutPressAndRelease() {
        let machine = HotkeyStateMachine(shortcut: .defaultHoldToTalk)

        let press = machine.process(
            HotkeyInputEvent(type: .flagsChanged, keyCode: 63, modifiers: [.function])
        )
        XCTAssertEqual(press, .pressed)

        let release = machine.process(
            HotkeyInputEvent(type: .flagsChanged, keyCode: 63, modifiers: [])
        )
        XCTAssertEqual(release, .released)
    }

    func testUpdateShortcutReevaluatesCurrentState() {
        let machine = HotkeyStateMachine(shortcut: .defaultHoldToTalk)
        _ = machine.process(
            HotkeyInputEvent(type: .flagsChanged, keyCode: 63, modifiers: [.function])
        )

        let transition = machine.updateShortcut(HotkeyShortcut(keyCode: 49, modifiers: [.command]))

        XCTAssertEqual(transition, .released)
    }
}
