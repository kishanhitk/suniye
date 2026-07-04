import XCTest
@testable import Suniye

final class LLMSettingsStoreMoreTests: XCTestCase {
    func testLoadReturnsDefaultsWhenNothingIsStored() {
        let suite = "dev.suniye.tests.llm.more.empty.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = LLMSettingsStore(userDefaults: defaults, storageKey: "llm")

        XCTAssertEqual(store.load(), LLMSettings())
    }

    func testSaveSilentlySkipsUnencodableSettings() {
        let suite = "dev.suniye.tests.llm.more.unencodable.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = LLMSettingsStore(userDefaults: defaults, storageKey: "llm")

        // Bypass the clamping initializer; infinity is not representable by
        // the JSON encoder, so save must bail out without writing anything.
        var unencodable = LLMSettings()
        unencodable.timeoutSeconds = .infinity

        store.save(unencodable)

        XCTAssertNil(defaults.data(forKey: "llm"))
        XCTAssertEqual(store.load(), LLMSettings())
    }
}
