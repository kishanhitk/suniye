import XCTest
@testable import Suniye

final class PartialTranscriptStabilizerTests: XCTestCase {
    func testKeepsShownPrefixAndAppendsNewTailWhenMajorityMatches() {
        let result = PartialTranscriptStabilizer.stabilize(
            previous: "hello world how are",
            current: "hello world how art thou"
        )

        // 3 of 4 previous words match (> half): shown prefix stays, new tail appended.
        XCTAssertEqual(result, "hello world how art thou")
    }

    func testPreservesPreviouslyDisplayedFormsInStablePrefix() {
        let result = PartialTranscriptStabilizer.stabilize(
            previous: "Okay, so we",
            current: "okay so we begin"
        )

        XCTAssertEqual(result, "Okay, so we begin")
    }

    func testAcceptsFullRewriteWhenHypothesisDiverges() {
        let result = PartialTranscriptStabilizer.stabilize(
            previous: "completely different words here",
            current: "nothing matches at all"
        )

        XCTAssertEqual(result, "nothing matches at all")
    }

    func testExactlyHalfOverlapIsNotEnoughToKeepPrefix() {
        let result = PartialTranscriptStabilizer.stabilize(
            previous: "alpha beta gamma delta",
            current: "alpha beta zeta eta"
        )

        // 2 of 4 is not > half: rewrite wins.
        XCTAssertEqual(result, "alpha beta zeta eta")
    }

    func testPunctuationAndCaseDifferencesDoNotBreakThePrefix() {
        let result = PartialTranscriptStabilizer.stabilize(
            previous: "Send the report, please, before",
            current: "send the report please before noon"
        )

        XCTAssertEqual(result, "Send the report, please, before noon")
    }

    func testEmptyPreviousReturnsCurrent() {
        XCTAssertEqual(
            PartialTranscriptStabilizer.stabilize(previous: "", current: "first words"),
            "first words"
        )
        XCTAssertEqual(PartialTranscriptStabilizer.stabilize(previous: "   ", current: "x"), "x")
    }

    func testShorterHypothesisKeepsOnlyTheCommonPrefix() {
        let result = PartialTranscriptStabilizer.stabilize(
            previous: "one two three four five",
            current: "one two three four"
        )

        XCTAssertEqual(result, "one two three four")
    }
}
