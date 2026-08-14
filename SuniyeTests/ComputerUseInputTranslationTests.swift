import CoreGraphics
import XCTest
@testable import Suniye

final class ComputerUseInputTranslationTests: XCTestCase {
    func testScrollDirectionsProducePageScaledAxes() {
        XCTAssertEqual(
            ComputerUseScrollDirection.up.eventDelta(pages: 1.5),
            ComputerUseScrollDelta(horizontal: 0, vertical: 600)
        )
        XCTAssertEqual(
            ComputerUseScrollDirection.down.eventDelta(pages: 1.5),
            ComputerUseScrollDelta(horizontal: 0, vertical: -600)
        )
        XCTAssertEqual(
            ComputerUseScrollDirection.left.eventDelta(pages: 1.5),
            ComputerUseScrollDelta(horizontal: 600, vertical: 0)
        )
        XCTAssertEqual(
            ComputerUseScrollDirection.right.eventDelta(pages: 1.5),
            ComputerUseScrollDelta(horizontal: -600, vertical: 0)
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

    func testTypingEventsConvertNewlinesToReturnKeystrokes() {
        XCTAssertEqual(ComputerUseUnicodeEventChunker.typingEvents(in: ""), [])
        XCTAssertEqual(ComputerUseUnicodeEventChunker.typingEvents(in: "hello"), [.text("hello")])
        XCTAssertEqual(
            ComputerUseUnicodeEventChunker.typingEvents(in: "hello\n"),
            [.text("hello"), .returnKey]
        )
        XCTAssertEqual(
            ComputerUseUnicodeEventChunker.typingEvents(in: "a\n\nb"),
            [.text("a"), .returnKey, .returnKey, .text("b")]
        )
        XCTAssertEqual(
            ComputerUseUnicodeEventChunker.typingEvents(in: "a\r\nb"),
            [.text("a"), .returnKey, .text("b")]
        )
        XCTAssertEqual(ComputerUseUnicodeEventChunker.typingEvents(in: "\r"), [.returnKey])
        XCTAssertEqual(
            ComputerUseUnicodeEventChunker.typingEvents(in: "\n\n"),
            [.returnKey, .returnKey]
        )
    }

    func testTypingEventsPreserveUnicodeChunkingWithinLines() {
        let line = String(repeating: "a", count: 19) + "🙂" + "b"

        XCTAssertEqual(
            ComputerUseUnicodeEventChunker.typingEvents(in: line + "\n"),
            [.text(String(repeating: "a", count: 19)), .text("🙂" + "b"), .returnKey]
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

    func testSystemKeyChordParsingHopsToMainActor() async throws {
        let parsed = try await Task.detached {
            try await SystemComputerUseInputEvents.parseKeyChord("super+a")
        }.value

        XCTAssertEqual(parsed, .init(keyCode: 0, flags: .maskCommand))
    }
}
