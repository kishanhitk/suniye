import XCTest
@testable import Suniye

final class ComputerUseTextSelectionTests: XCTestCase {
    func testResolvesUTF16TextAndCursorRanges() throws {
        let selected = try ComputerUseTextSelectionResolver.resolve(
            text: "🙂",
            prefix: "A",
            suffix: "B",
            selectionType: .text,
            in: "A🙂B🙂C"
        )
        let cursor = try ComputerUseTextSelectionResolver.resolve(
            text: "🙂",
            prefix: "A",
            suffix: "B",
            selectionType: .cursorAfter,
            in: "A🙂B🙂C"
        )

        XCTAssertEqual(selected.location, 1)
        XCTAssertEqual(selected.length, 2)
        XCTAssertEqual(cursor.location, 3)
        XCTAssertEqual(cursor.length, 0)
    }

    func testResolvesCursorBefore() throws {
        let range = try ComputerUseTextSelectionResolver.resolve(
            text: "world",
            prefix: "hello ",
            suffix: nil,
            selectionType: .cursorBefore,
            in: "hello world"
        )

        XCTAssertEqual(range.location, 6)
        XCTAssertEqual(range.length, 0)
    }

    func testRejectsMissingAndAmbiguousText() {
        XCTAssertThrowsError(
            try ComputerUseTextSelectionResolver.resolve(
                text: "missing",
                prefix: nil,
                suffix: nil,
                selectionType: .text,
                in: "value"
            )
        ) { error in
            XCTAssertEqual(error as? ComputerUseActionError, .textNotFound("missing"))
        }
        XCTAssertThrowsError(
            try ComputerUseTextSelectionResolver.resolve(
                text: "same",
                prefix: nil,
                suffix: nil,
                selectionType: .text,
                in: "same same"
            )
        ) { error in
            XCTAssertEqual(error as? ComputerUseActionError, .textAmbiguous("same"))
        }
    }

    func testContextMustBeImmediatelyAdjacent() {
        XCTAssertThrowsError(
            try ComputerUseTextSelectionResolver.resolve(
                text: "target",
                prefix: "prefix",
                suffix: "suffix",
                selectionType: .text,
                in: "prefix target suffix"
            )
        ) { error in
            XCTAssertEqual(error as? ComputerUseActionError, .textNotFound("target"))
        }
    }
}
