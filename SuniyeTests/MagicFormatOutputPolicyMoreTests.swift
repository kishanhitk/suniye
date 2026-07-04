import XCTest
@testable import Suniye

final class MagicFormatOutputPolicyMoreTests: XCTestCase {
    // MARK: - isValidPlainText

    func testWhitespaceOnlyOutputIsInvalid() {
        XCTAssertFalse(MagicFormatOutputSanitizer.isValidPlainText("   \n ", for: "hello"))
    }

    func testCodeFenceOutputIsInvalid() {
        XCTAssertFalse(MagicFormatOutputSanitizer.isValidPlainText("```\nhello\n```", for: "hello"))
    }

    func testExcessivelyLongOutputIsInvalid() {
        let output = String(repeating: "a", count: 300)
        XCTAssertFalse(MagicFormatOutputSanitizer.isValidPlainText(output, for: "hi"))
    }

    func testMultilineOutputWithTooManyLinesIsInvalid() {
        let input = "make a list of everything we packed for the trip"
        let output = (1 ... 21).map { "- item \($0)" }.joined(separator: "\n")
        XCTAssertFalse(MagicFormatOutputSanitizer.isValidPlainText(output, for: input))
    }

    func testMultilineOutputWithBlankLineIsInvalid() {
        let input = "make a list of chores"
        XCTAssertFalse(MagicFormatOutputSanitizer.isValidPlainText("- one\n\n- two", for: input))
    }

    // MARK: - MagicFormatPipeline

    func testPipelineRejectsWhitespaceOnlyInput() async {
        do {
            _ = try await MagicFormatPipeline.polish(
                text: "   \n ",
                systemPrompt: "prompt",
                keywords: []
            ) { _ in
                XCTFail("generate must not run for empty input")
                return "unused"
            }
            XCTFail("Expected empty output")
        } catch let error as LLMPostProcessorError {
            XCTAssertEqual(error.logValue, LLMPostProcessorError.emptyOutput.logValue)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Formatting intent detection

    func testOrdinalSequenceWithoutOtherTriggersIsMultilineList() {
        XCTAssertEqual(
            MagicFormatFormattingIntentDetector.detect(in: "first rinse the cup second dry it third put it away"),
            .multilineList
        )
    }

    func testTriggerWordEmbeddedInsideLargerWordDoesNotTrigger() {
        // "stylists" contains "list" only as a substring; boundary matching must
        // advance past it and report single-line intent.
        XCTAssertEqual(
            MagicFormatFormattingIntentDetector.detect(in: "the stylists were busy all day"),
            .singleLine
        )
    }

    // MARK: - Prompt composer retry corrections

    func testRetryCorrectionForMultilineIntentAsksForPlainTextList() {
        let instructions = MagicFormatPromptComposer.makeInstructions(
            systemPrompt: "prompt",
            keywords: [],
            text: "make a list water snacks sunscreen",
            retrying: true
        )

        XCTAssertTrue(instructions.contains("Retry correction: return only the cleaned transcript text as a plain-text list."))
        XCTAssertFalse(instructions.contains("One line."))
    }

    func testRetryCorrectionForSingleLineIntentAsksForOneLine() {
        let instructions = MagicFormatPromptComposer.makeInstructions(
            systemPrompt: "prompt",
            keywords: [],
            text: "just a normal sentence",
            retrying: true
        )

        XCTAssertTrue(instructions.contains("Retry correction: return only the cleaned transcript text. One line."))
    }
}
