import SwiftUI
import XCTest
@testable import Suniye

final class NumberRunsTests: XCTestCase {
    private func numbers(in string: String) -> [String] {
        NumberRuns.split(string).filter(\.isNumber).map(\.text)
    }

    func testSplitKeepsEveryCharacterInOrder() {
        for string in ["", "Recording", "Today · 2:06 PM · 38 min · Zoom", "45% downloaded • 1.2 GB of 3,1 GB", "v0.0.75 (212) Tip"] {
            XCTAssertEqual(NumberRuns.split(string).map(\.text).joined(), string)
        }
    }

    func testTimesCountsSizesAndPercentagesAreNumbers() {
        XCTAssertEqual(numbers(in: "Today · 2:06 PM · 38 min"), ["2:06", "38"])
        XCTAssertEqual(numbers(in: "1:04:05 / 2:00:00"), ["1:04:05", "2:00:00"])
        XCTAssertEqual(numbers(in: "1,204 dictations"), ["1", "204"])
        XCTAssertEqual(numbers(in: "45% downloaded • 1.2 GB of 3.1 GB"), ["45%", "1.2", "3.1"])
        XCTAssertEqual(numbers(in: "2h 14m saved"), ["2", "14"])
        XCTAssertEqual(numbers(in: "Latency 0.8 s"), ["0.8"])
    }

    func testSeparatorWithoutADigitAfterItStaysText() {
        XCTAssertEqual(numbers(in: "Recording stops in 5 s."), ["5"])
        XCTAssertEqual(numbers(in: "Saved at 10:02, 42 minutes."), ["10:02", "42"])
        XCTAssertEqual(numbers(in: "2026-11-22"), ["2026", "11", "22"])
    }

    func testDigitsThatEndAWordArePartOfTheName() {
        XCTAssertEqual(numbers(in: "Qwen3-ASR 1.7B"), ["1.7"])
        XCTAssertEqual(numbers(in: "Gemma 4 E2B Instruct Q4_K_M"), ["4"])
        XCTAssertEqual(numbers(in: "F5"), [])
    }

    func testVersionPrefixKeepsTheNumber() {
        XCTAssertEqual(numbers(in: "v0.0.75 (212)"), ["0.0.75", "212"])
        XCTAssertEqual(numbers(in: "Whisper Large v3"), ["3"])
        XCTAssertEqual(numbers(in: "Dev3"), [])
    }

    func testAttributedTextUsesAFixedPitchFontOnlyForNumbers() {
        let font = NSFont.menuFont(ofSize: 0)
        let text = NumberRuns.attributed("Recording · 12:04", font: font)
        XCTAssertEqual(text.string, "Recording · 12:04")

        let word = text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let number = text.attribute(.font, at: text.length - 1, effectiveRange: nil) as? NSFont
        XCTAssertEqual(word, font)
        XCTAssertEqual(number?.isFixedPitch, true)
        XCTAssertEqual(number?.pointSize, font.pointSize)
    }

    @MainActor
    func testNumberTextChangesOnlyTheWidthOfNumbers() {
        func width(_ text: Text) -> CGFloat {
            NSHostingView(rootView: text.font(.system(size: 20)).fixedSize()).fittingSize.width
        }

        XCTAssertEqual(width(Text(numbers: "Recording")), width(Text(verbatim: "Recording")))
        XCTAssertNotEqual(width(Text(numbers: "11:11")), width(Text(verbatim: "11:11")))
        XCTAssertEqual(width(Text(numbers: "11:11")), width(Text(verbatim: "11:11").monospaced()))
    }
}
