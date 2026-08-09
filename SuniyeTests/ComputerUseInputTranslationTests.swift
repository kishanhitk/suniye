import CoreGraphics
import XCTest
@testable import Suniye

final class ComputerUseInputTranslationTests: XCTestCase {
    func testScrollDirectionsProducePageScaledAxes() {
        XCTAssertEqual(
            ComputerUseScrollDirection.up.eventDelta(pages: 1.5),
            ComputerUseScrollDelta(horizontal: 0, vertical: -600)
        )
        XCTAssertEqual(
            ComputerUseScrollDirection.down.eventDelta(pages: 1.5),
            ComputerUseScrollDelta(horizontal: 0, vertical: 600)
        )
        XCTAssertEqual(
            ComputerUseScrollDirection.left.eventDelta(pages: 1.5),
            ComputerUseScrollDelta(horizontal: -600, vertical: 0)
        )
        XCTAssertEqual(
            ComputerUseScrollDirection.right.eventDelta(pages: 1.5),
            ComputerUseScrollDelta(horizontal: 600, vertical: 0)
        )
    }

    func testUnicodeChunksRespectEventLimitWithoutSplittingCharacters() {
        let text = String(repeating: "a", count: 19) + "🙂" + "b"
        let chunks = ComputerUseUnicodeEventChunker.chunks(in: text)

        XCTAssertEqual(chunks, [String(repeating: "a", count: 19), "🙂" + "b"])
        XCTAssertEqual(chunks.joined(), text)
        XCTAssertTrue(chunks.allSatisfy { $0.utf16.count <= 20 })
    }

    func testUnicodeChunksHandleEmptyAndCustomLimit() {
        XCTAssertEqual(ComputerUseUnicodeEventChunker.chunks(in: ""), [])
        XCTAssertEqual(
            ComputerUseUnicodeEventChunker.chunks(in: "abcdef", maximumUTF16Units: 2),
            ["ab", "cd", "ef"]
        )
    }

    func testKeyChordSupportsDocumentedNamesAndAliases() throws {
        XCTAssertEqual(
            try ComputerUseKeyChord.parse("Control_L + Shift + a"),
            .init(keyCode: 0, flags: [.maskControl, .maskShift])
        )
        XCTAssertEqual(
            try ComputerUseKeyChord.parse("Super_L+d"),
            .init(keyCode: 2, flags: .maskCommand)
        )
        XCTAssertEqual(
            try ComputerUseKeyChord.parse("KP_0"),
            .init(keyCode: 82, flags: [])
        )
        XCTAssertEqual(
            try ComputerUseKeyChord.parse("Return"),
            .init(keyCode: 36, flags: [])
        )
    }

    func testKeyChordRejectsMalformedOrUnknownNames() {
        XCTAssertThrowsError(try ComputerUseKeyChord.parse("Control++a"))
        XCTAssertThrowsError(try ComputerUseKeyChord.parse("Hyper_L+a"))
        XCTAssertThrowsError(try ComputerUseKeyChord.parse("not-a-key"))
    }
}
