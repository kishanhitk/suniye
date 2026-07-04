import XCTest
@testable import Suniye

final class GeneralSettingsStoreMoreTests: XCTestCase {
    func testLoadReturnsDefaultsWhenNothingIsStored() {
        let suite = "dev.suniye.tests.general.more.empty.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = GeneralSettingsStore(userDefaults: defaults, storageKey: "general")

        XCTAssertEqual(store.load(), GeneralSettings())
    }

    func testSaveSilentlySkipsUnencodableSettings() {
        let suite = "dev.suniye.tests.general.more.unencodable.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = GeneralSettingsStore(userDefaults: defaults, storageKey: "general")

        // Infinity is not representable by the JSON encoder, so save must
        // bail out without writing anything.
        let unencodable = GeneralSettings(
            floatingIndicatorPlacement: FloatingIndicatorPlacement(centerXRatio: .infinity, bottomYRatio: 0.5)
        )

        store.save(unencodable)

        XCTAssertNil(defaults.data(forKey: "general"))
        XCTAssertEqual(store.load(), GeneralSettings())
    }
}
