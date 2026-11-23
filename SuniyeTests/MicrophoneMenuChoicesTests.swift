import XCTest
@testable import Suniye

@MainActor
final class MicrophoneMenuChoicesTests: XCTestCase {
    /// Both microphone menus list System Default, then each device with its
    /// connection, whether it is the default, and whether it is unavailable.
    func testChoicesNameEachDevice() {
        let appState = makeTestAppState()
        appState.microphone.availableInputDevices = [
            AudioInputDevice(id: "mac", name: "MacBook Air Microphone", isDefault: true, transport: .builtIn),
            AudioInputDevice(id: "usb", name: "Yeti", isDefault: false, transport: .usb),
        ]

        XCTAssertEqual(
            appState.microphone.menuChoices.map(\.title),
            ["System Default", "MacBook Air Microphone - Built-in - Default", "Yeti - USB"]
        )
        XCTAssertEqual(appState.microphone.menuChoices.map(\.id), [nil, "mac", "usb"])
    }

    /// A saved microphone that is disconnected cannot be chosen again; a
    /// built-in one that the closed lid switched off can.
    func testUnavailableDevicesFollowOneRule() {
        let appState = makeTestAppState()
        appState.microphone.availableInputDevices = [
            AudioInputDevice(id: "airpods", name: "AirPods", isDefault: false, transport: .bluetooth, availability: .notConnected),
            AudioInputDevice(id: "mac", name: "MacBook Air Microphone", isDefault: false, transport: .builtIn, availability: .offWithLidClosed),
        ]

        let choices = appState.microphone.menuChoices
        XCTAssertEqual(choices[1].title, "AirPods - Bluetooth - Unavailable")
        XCTAssertFalse(choices[1].isSelectable)
        XCTAssertEqual(choices[2].title, "MacBook Air Microphone - Built-in - Unavailable")
        XCTAssertTrue(choices[2].isSelectable)
        XCTAssertTrue(choices[0].isSelectable, "System Default is always a choice")
    }
}
