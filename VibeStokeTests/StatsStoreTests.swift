import Foundation
import XCTest
@testable import VibeStoke

final class StatsStoreTests: XCTestCase {
    func testRoundTripPersistsSnapshot() throws {
        let temp = try makeTempDirectory()
        let store = StatsStore(baseDirectoryURL: temp)
        let snapshot = StatsSnapshot(sessionCount: 5, wordsTranscribed: 123, totalDictationSeconds: 44)

        store.save(snapshot)
        let loaded = store.load()

        XCTAssertEqual(loaded, snapshot)
    }

    func testLoadMissingFileReturnsZero() throws {
        let temp = try makeTempDirectory()
        let store = StatsStore(baseDirectoryURL: temp)

        XCTAssertEqual(store.load(), .zero)
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
