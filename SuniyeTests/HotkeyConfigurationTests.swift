import AppKit
import Carbon
import XCTest
@testable import Suniye

final class HotkeyConfigurationTests: XCTestCase {
    func testKeyComboDisplayIncludesAllModifierLabelsInOrder() {
        let combo = HotkeyConfiguration.keyCombo(
            keyCode: UInt32(kVK_ANSI_A),
            carbonModifiers: UInt32(controlKey) | UInt32(optionKey) | UInt32(shiftKey) | UInt32(cmdKey)
        )

        XCTAssertEqual(combo.modifierLabels, ["Control", "Option", "Shift", "Command"])
        XCTAssertEqual(combo.displayString, "Control + Option + Shift + Command + A")
        XCTAssertEqual(combo.exampleDescription, combo.displayString)
    }

    func testFromFlagsChangedFunctionKeyEventIsGlobe() throws {
        let event = try XCTUnwrap(makeKeyEvent(type: .flagsChanged, flags: .function, keyCode: UInt16(kVK_Function)))

        XCTAssertEqual(HotkeyConfiguration.from(event: event), .globe)
    }

    func testFromFlagsChangedWithOtherModifiersIsNil() throws {
        let event = try XCTUnwrap(makeKeyEvent(type: .flagsChanged, flags: .shift, keyCode: UInt16(kVK_Shift)))

        XCTAssertNil(HotkeyConfiguration.from(event: event))
    }

    func testFromKeyDownOnBareModifierKeyIsNil() throws {
        let event = try XCTUnwrap(makeKeyEvent(type: .keyDown, flags: [], keyCode: UInt16(kVK_Shift)))

        XCTAssertNil(HotkeyConfiguration.from(event: event))
    }

    func testFromKeyDownProducesKeyCombo() throws {
        let event = try XCTUnwrap(makeKeyEvent(type: .keyDown, flags: [.command, .shift], keyCode: UInt16(kVK_ANSI_A)))

        XCTAssertEqual(
            HotkeyConfiguration.from(event: event),
            .keyCombo(keyCode: UInt32(kVK_ANSI_A), carbonModifiers: UInt32(cmdKey) | UInt32(shiftKey))
        )
    }

    func testCarbonModifiersMapsEachFlag() {
        XCTAssertEqual(HotkeyConfiguration.carbonModifiers(from: []), 0)
        XCTAssertEqual(HotkeyConfiguration.carbonModifiers(from: .control), UInt32(controlKey))
        XCTAssertEqual(HotkeyConfiguration.carbonModifiers(from: .option), UInt32(optionKey))
        XCTAssertEqual(HotkeyConfiguration.carbonModifiers(from: .shift), UInt32(shiftKey))
        XCTAssertEqual(HotkeyConfiguration.carbonModifiers(from: .command), UInt32(cmdKey))
        XCTAssertEqual(
            HotkeyConfiguration.carbonModifiers(from: [.control, .option, .shift, .command]),
            UInt32(controlKey) | UInt32(optionKey) | UInt32(shiftKey) | UInt32(cmdKey)
        )
    }

    func testKeyNameFallsBackToNumericDescription() {
        XCTAssertEqual(HotkeyConfiguration.keyName(for: 999), "Key 999")
    }

    private func makeKeyEvent(
        type: NSEvent.EventType,
        flags: NSEvent.ModifierFlags,
        keyCode: UInt16
    ) -> NSEvent? {
        NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        )
    }
}
