import XCTest
@testable import Suniye

final class HistoryStoreTests: XCTestCase {
    func testRoundTripPersistsDurationAndOrdering() {
        let suite = "dev.suniye.tests.history.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = HistoryStore(userDefaults: defaults, storageKey: "history")

        let results = [
            RecentResult(
                id: UUID(),
                text: "hello world",
                createdAt: Date(timeIntervalSince1970: 1_700_000_000.123),
                durationSeconds: 1.7,
                wasLLMPolished: false
            ),
            RecentResult(
                id: UUID(),
                text: "second",
                createdAt: Date(timeIntervalSince1970: 1_699_999_880.456),
                durationSeconds: 3.4,
                wasLLMPolished: true
            )
        ]

        store.save(results)

        let loaded = store.load()
        XCTAssertEqual(loaded.count, results.count)

        for (loadedResult, expectedResult) in zip(loaded, results) {
            XCTAssertEqual(loadedResult.id, expectedResult.id)
            XCTAssertEqual(loadedResult.text, expectedResult.text)
            XCTAssertEqual(loadedResult.durationSeconds, expectedResult.durationSeconds, accuracy: 0.0001)
            XCTAssertEqual(loadedResult.wasLLMPolished, expectedResult.wasLLMPolished)
            XCTAssertEqual(
                loadedResult.createdAt.timeIntervalSince1970,
                expectedResult.createdAt.timeIntervalSince1970,
                accuracy: 0.001
            )
        }
    }

    func testLoadFallsBackToLegacyISO8601Encoding() throws {
        let suite = "dev.suniye.tests.history.legacy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = HistoryStore(userDefaults: defaults, storageKey: "history")
        let legacyEncoder = JSONEncoder()
        legacyEncoder.dateEncodingStrategy = .iso8601

        let result = RecentResult(
            id: UUID(),
            text: "legacy",
            createdAt: Date(timeIntervalSince1970: 1_700_000_500),
            durationSeconds: 2.2,
            wasLLMPolished: true
        )

        defaults.set(try legacyEncoder.encode([result]), forKey: "history")

        let loaded = store.load()
        XCTAssertEqual(loaded.count, 1)
        guard let loadedResult = loaded.first else {
            return XCTFail("Expected a migrated legacy result")
        }

        XCTAssertEqual(loadedResult.id, result.id)
        XCTAssertEqual(loadedResult.text, result.text)
        XCTAssertEqual(loadedResult.durationSeconds, result.durationSeconds, accuracy: 0.0001)
        XCTAssertEqual(loadedResult.wasLLMPolished, result.wasLLMPolished)
        XCTAssertEqual(loadedResult.createdAt.timeIntervalSince1970, result.createdAt.timeIntervalSince1970, accuracy: 0.001)
    }
}
