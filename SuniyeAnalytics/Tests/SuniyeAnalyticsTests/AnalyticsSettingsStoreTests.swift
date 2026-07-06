import XCTest
@testable import SuniyeAnalytics

final class AnalyticsSettingsStoreTests: XCTestCase {
    func testLoadOrCreateGeneratesAndPersists() {
        let defaults = TestFixtures.scratchDefaults()
        let store = AnalyticsSettingsStore(userDefaults: defaults, storageKey: "k")
        XCTAssertNil(store.peek())

        var n = 0
        let created = store.loadOrCreate(makeInstallID: { n += 1; return "uuid-\(n)" }, now: { Date(timeIntervalSince1970: 100) })
        XCTAssertEqual(created.installID, "uuid-1")
        XCTAssertTrue(created.enabled)
        XCTAssertEqual(store.peek()?.installID, "uuid-1")
    }

    func testInstallIDIsStableAcrossCalls() {
        let defaults = TestFixtures.scratchDefaults()
        let store = AnalyticsSettingsStore(userDefaults: defaults, storageKey: "k")
        let first = store.loadOrCreate(makeInstallID: { "A" })
        let second = store.loadOrCreate(makeInstallID: { "B" }) // must NOT regenerate
        XCTAssertEqual(first.installID, "A")
        XCTAssertEqual(second.installID, "A")
    }

    func testSetEnabledPersists() {
        let defaults = TestFixtures.scratchDefaults()
        let store = AnalyticsSettingsStore(userDefaults: defaults, storageKey: "k")
        _ = store.loadOrCreate(makeInstallID: { "A" })
        store.setEnabled(false)
        XCTAssertEqual(store.peek()?.enabled, false)
        store.setEnabled(true)
        XCTAssertEqual(store.peek()?.enabled, true)
    }

    func testResetIdentityRotatesInstallID() {
        let defaults = TestFixtures.scratchDefaults()
        let store = AnalyticsSettingsStore(userDefaults: defaults, storageKey: "k")
        _ = store.loadOrCreate(makeInstallID: { "A" })
        let rotated = store.resetIdentity(makeInstallID: { "B" })
        XCTAssertEqual(rotated.installID, "B")
        XCTAssertEqual(store.peek()?.installID, "B")
    }

    func testDirectiveDecodesWithoutDisabledField() throws {
        // A `{ "sample_rate": ... }`-only response must still decode.
        let data = Data(#"{"sample_rate":0.5}"#.utf8)
        let directive = try JSONDecoder().decode(KillSwitchDirective.self, from: data)
        XCTAssertFalse(directive.disabled)
        XCTAssertEqual(directive.sampleRate, 0.5)
    }

    func testDirectivePersistAndClear() {
        let defaults = TestFixtures.scratchDefaults()
        let store = AnalyticsSettingsStore(userDefaults: defaults, storageKey: "k")
        XCTAssertNil(store.loadDirective())
        store.saveDirective(KillSwitchDirective(disabled: true, sampleRate: 0.5))
        XCTAssertEqual(store.loadDirective(), KillSwitchDirective(disabled: true, sampleRate: 0.5))
        store.saveDirective(nil)
        XCTAssertNil(store.loadDirective())
    }
}
