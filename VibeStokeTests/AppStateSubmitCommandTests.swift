import XCTest
@testable import VibeStoke

final class AppStateSubmitCommandTests: XCTestCase {
    func testParseSubmitCommandSendAtEnd() {
        let parsed = AppState.parseSubmitCommand(from: "hello world send")
        XCTAssertEqual(parsed.text, "hello world")
        XCTAssertTrue(parsed.shouldSubmit)
    }

    func testParseSubmitCommandEnterWithPunctuation() {
        let parsed = AppState.parseSubmitCommand(from: "hello world, enter.")
        XCTAssertEqual(parsed.text, "hello world")
        XCTAssertTrue(parsed.shouldSubmit)
    }

    func testParseSubmitCommandOnlyCommand() {
        let parsed = AppState.parseSubmitCommand(from: "send")
        XCTAssertEqual(parsed.text, "")
        XCTAssertTrue(parsed.shouldSubmit)
    }

    func testParseSubmitCommandKeepsNormalMessage() {
        let parsed = AppState.parseSubmitCommand(from: "please send me the notes")
        XCTAssertEqual(parsed.text, "please send me the notes")
        XCTAssertFalse(parsed.shouldSubmit)
    }

    func testDidLLMPolishReturnsFalseWhenOnlySubmitParsingChangedText() {
        XCTAssertFalse(AppState.didLLMPolish(input: "hello world send", output: "hello world send"))
    }

    func testDidLLMPolishReturnsTrueWhenLLMOutputDiffers() {
        XCTAssertTrue(AppState.didLLMPolish(input: "hello world", output: "Hello world."))
    }
}
