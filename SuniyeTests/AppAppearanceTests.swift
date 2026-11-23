import AppKit
import XCTest
@testable import Suniye

@MainActor
final class AppAppearanceTests: XCTestCase {
    /// Settings saved before the theme existed, or with a value a later build
    /// added, load as System.
    func testStoredAppearanceDecodesWithASafeDefault() throws {
        func decode(_ json: String) throws -> GeneralSettings {
            try JSONDecoder().decode(GeneralSettings.self, from: Data(json.utf8))
        }

        XCTAssertEqual(try decode("{}").appearance, .system)
        XCTAssertEqual(try decode(#"{"appearance":"dark"}"#).appearance, .dark)
        XCTAssertEqual(try decode(#"{"appearance":"sepia"}"#).appearance, .system)
    }

    func testChosenAppearanceIsSaved() {
        let store = TestGeneralSettingsStore()
        let appState = makeTestAppState(generalSettingsStore: store)

        appState.appearance = .dark

        XCTAssertEqual(appState.appearance, .dark)
        XCTAssertEqual(store.latest.appearance, .dark)
    }
}
