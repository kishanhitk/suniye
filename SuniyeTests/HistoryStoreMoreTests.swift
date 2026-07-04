import XCTest
@testable import Suniye

final class HistoryStoreMoreTests: XCTestCase {
    func testLoadReturnsEmptyWhenNothingIsStored() {
        let suite = "dev.suniye.tests.history.more.empty.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = HistoryStore(userDefaults: defaults, storageKey: "history")

        XCTAssertEqual(store.load(), [])
    }

    func testSaveSilentlySkipsUnencodableResults() {
        let suite = "dev.suniye.tests.history.more.unencodable.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = HistoryStore(userDefaults: defaults, storageKey: "history")

        // Infinity is not representable by the JSON encoder, so save must
        // bail out without writing anything.
        let unencodable = RecentResult(
            id: UUID(),
            text: "bad duration",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            durationSeconds: .infinity,
            wasLLMPolished: false
        )

        store.save([unencodable])

        XCTAssertNil(defaults.data(forKey: "history"))
        XCTAssertEqual(store.load(), [])
    }
}
