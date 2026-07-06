import XCTest
@testable import SuniyeAnalytics

final class SafeLabelTests: XCTestCase {
    func testLowercasesAndKeepsAllowedChars() {
        XCTAssertEqual(SafeLabel("Parakeet-V3.1_en").value, "parakeet-v3.1_en")
    }

    func testCollapsesSeparatorsToDash() {
        XCTAssertEqual(SafeLabel("Apple M3 Pro").value, "apple-m3-pro")
        XCTAssertEqual(SafeLabel("nemo/transducer").value, "nemo-transducer")
    }

    func testStripsPunctuationAndUnicode() {
        // A sentence of user content cannot survive as a label.
        let leaked = SafeLabel("Hey, remember to call Dr. Smith at 5pm!")
        XCTAssertFalse(leaked.value.contains(" "))
        XCTAssertFalse(leaked.value.contains(","))
        XCTAssertFalse(leaked.value.contains("!"))
    }

    func testLengthCapped() {
        let long = String(repeating: "a", count: 500)
        XCTAssertLessThanOrEqual(SafeLabel(long).value.count, SafeLabel.maxLength)
    }

    func testEmptyBecomesUnknown() {
        XCTAssertEqual(SafeLabel("").value, "unknown")
        XCTAssertEqual(SafeLabel("!!!").value, "unknown")
        XCTAssertEqual(SafeLabel("   ").value, "unknown")
    }

    func testTrimsLeadingTrailingSeparators() {
        XCTAssertEqual(SafeLabel("--edge._").value, "edge")
    }
}
