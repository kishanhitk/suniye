import XCTest
@testable import VibeStoke

final class AppVersionTests: XCTestCase {
    func testSemVerParsesSupportedFormats() {
        XCTAssertEqual(SemVer(rawValue: "0.1"), SemVer(rawValue: "0.1.0"))
        XCTAssertEqual(SemVer(rawValue: "1"), SemVer(rawValue: "1.0.0"))
        XCTAssertEqual(SemVer(rawValue: "v2.3.4"), SemVer(rawValue: "2.3.4"))
    }

    func testSemVerComparison() {
        XCTAssertLessThan(SemVer(rawValue: "0.0.9")!, SemVer(rawValue: "0.1.0")!)
        XCTAssertLessThan(SemVer(rawValue: "1.9.9")!, SemVer(rawValue: "2.0.0")!)
    }

    func testSemVerRejectsInvalidValues() {
        XCTAssertNil(SemVer(rawValue: ""))
        XCTAssertNil(SemVer(rawValue: "1.2.3.4"))
        XCTAssertNil(SemVer(rawValue: "1.a.0"))
    }
}
