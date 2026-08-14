import XCTest
@testable import Suniye

/// TTS must never read markup aloud ("asterisk asterisk").
final class SpokenTextSanitizerTests: XCTestCase {
    func testStripsEmphasisAndInlineCode() {
        XCTAssertEqual(
            SpokenTextSanitizer.plainSpeech(from: "**Battery:** at *91%*, condition `Normal`."),
            "Battery: at 91%, condition Normal."
        )
    }

    func testHeadingsAndBulletsBecomeProse() {
        let markdown = """
        ## Battery Status
        - Charge: 91%
        - Condition: Normal
        """
        XCTAssertEqual(
            SpokenTextSanitizer.plainSpeech(from: markdown),
            "Battery Status. Charge: 91%. Condition: Normal"
        )
    }

    func testLinksKeepLabelDropURL() {
        XCTAssertEqual(
            SpokenTextSanitizer.plainSpeech(from: "See [the report](https://example.com/x) for details."),
            "See the report for details."
        )
    }

    func testFencedCodeBlocksAreDropped() {
        let markdown = "Done.\n```bash\npmset -g batt\n```\nBattery is fine."
        XCTAssertEqual(
            SpokenTextSanitizer.plainSpeech(from: markdown),
            "Done. Battery is fine."
        )
    }

    func testPlainTextPassesThroughUnchanged() {
        XCTAssertEqual(
            SpokenTextSanitizer.plainSpeech(from: "Your battery is at 91 percent."),
            "Your battery is at 91 percent."
        )
    }

    func testNumberedListsAndTables() {
        let markdown = """
        1. Open Terminal
        2. Run the check

        | App | State |
        |-----|-------|
        | Mail | open |
        """
        let spoken = SpokenTextSanitizer.plainSpeech(from: markdown)
        XCTAssertFalse(spoken.contains("|"))
        XCTAssertFalse(spoken.contains("1."))
        XCTAssertTrue(spoken.contains("Open Terminal"))
        XCTAssertTrue(spoken.contains("Mail"))
    }
}
