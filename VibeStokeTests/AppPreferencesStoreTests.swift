import Foundation
import XCTest
@testable import VibeStoke

final class AppPreferencesStoreTests: XCTestCase {
    func testRoundTripPersistsPreferences() throws {
        let temp = try makeTempDirectory()
        let store = AppPreferencesStore(baseDirectoryURL: temp)

        let preferences = AppPreferences(
            hotkeyShortcut: HotkeyShortcut(keyCode: 49, modifiers: [.command, .shift]),
            selectedInputDeviceUID: "mic-1",
            launchAtLoginEnabled: true
        )

        store.save(preferences)
        let loaded = store.load()

        XCTAssertEqual(loaded, preferences)
    }

    func testLoadMissingFileReturnsDefaults() throws {
        let temp = try makeTempDirectory()
        let store = AppPreferencesStore(baseDirectoryURL: temp)

        XCTAssertEqual(store.load(), AppPreferences())
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
