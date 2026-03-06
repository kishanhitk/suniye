import Foundation
import XCTest
@testable import Suniye

final class HistoryStoreTests: XCTestCase {
    func testRoundTripPersistsEntries() throws {
        let temp = try makeTempDirectory()
        let store = HistoryStore(baseDirectoryURL: temp, maxEntries: 500)

        let input = [
            HistoryEntry(durationSeconds: 1.2, wordCount: 2, text: "hello world", submitted: false),
            HistoryEntry(durationSeconds: 2.4, wordCount: 3, text: "second", submitted: true)
        ]

        store.save(input)
        let loaded = store.load()

        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded.map(\.text), ["hello world", "second"])
    }

    func testRetentionCapAppliesOnSaveAndLoad() throws {
        let temp = try makeTempDirectory()
        let store = HistoryStore(baseDirectoryURL: temp, maxEntries: 3)

        let entries = (0..<6).map { index in
            HistoryEntry(durationSeconds: 1, wordCount: 1, text: "item-\(index)", submitted: false)
        }

        store.save(entries)
        let loaded = store.load()

        XCTAssertEqual(loaded.count, 3)
        XCTAssertEqual(loaded.map(\.text), ["item-0", "item-1", "item-2"])
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
