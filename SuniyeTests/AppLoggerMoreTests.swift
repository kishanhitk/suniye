import XCTest
@testable import Suniye

final class AppLoggerMoreTests: XCTestCase {
    func testLogRotatesFileOnceItExceedsSizeLimit() throws {
        let logger = AppLogger.shared
        let logURL = logger.logFileURL
        let rotatedURL = logURL.deletingLastPathComponent().appendingPathComponent("app.log.1")
        try? FileManager.default.removeItem(at: rotatedURL)

        // Grow the current log beyond the 2 MB rotation threshold, then log.
        try Data(count: 2_100_000).write(to: logURL)
        logger.log(.info, "rotation trigger")

        // Logging is asynchronous on a private queue; poll for the rotation.
        var attempts = 0
        while !FileManager.default.fileExists(atPath: rotatedURL.path), attempts < 150 {
            usleep(20_000)
            attempts += 1
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: rotatedURL.path))
        let rotatedSize = try FileManager.default.attributesOfItem(atPath: rotatedURL.path)[.size] as? UInt64
        XCTAssertGreaterThanOrEqual(rotatedSize ?? 0, 2_100_000)
        XCTAssertTrue(FileManager.default.fileExists(atPath: logURL.path))
    }
}
