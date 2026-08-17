import AppKit
import XCTest
@testable import Suniye

@MainActor
final class AppIconCacheTests: XCTestCase {
    private func makeCache(installed: Set<String>) -> AppIconCache {
        AppIconCache { bundleID in
            installed.contains(bundleID) ? NSImage(size: NSSize(width: 1, height: 1)) : nil
        }
    }

    func testResolvesOncePerBundleID() {
        let cache = makeCache(installed: ["com.example.app"])

        let first = cache.icon(for: "com.example.app")
        let second = cache.icon(for: "com.example.app")

        XCTAssertNotNil(first)
        XCTAssertTrue(first === second, "the same instance is handed back, not a fresh resolve")
        XCTAssertEqual(cache.resolveCount, 1)
    }

    func testCachesNegativeLookups() {
        // The bug this guards against: an uninstalled app being re-queried
        // through Launch Services on every row body evaluation.
        let cache = makeCache(installed: [])

        XCTAssertNil(cache.icon(for: "com.example.gone"))
        XCTAssertNil(cache.icon(for: "com.example.gone"))
        XCTAssertNil(cache.icon(for: "com.example.gone"))

        XCTAssertEqual(cache.resolveCount, 1)
    }

    func testDistinctBundleIDsResolveIndependently() {
        let cache = makeCache(installed: ["com.example.a"])

        XCTAssertNotNil(cache.icon(for: "com.example.a"))
        XCTAssertNil(cache.icon(for: "com.example.b"))
        XCTAssertNotNil(cache.icon(for: "com.example.a"))
        XCTAssertNil(cache.icon(for: "com.example.b"))

        XCTAssertEqual(cache.resolveCount, 2)
    }
}
