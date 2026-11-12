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

    func testSpokenNewParagraphsAllowOneBlankLineEach() {
        let input = "Hi Nora, new paragraph. The lease is signed. New paragraph. Thanks, new line, Omar"
        XCTAssertTrue(MagicFormatOutputSanitizer.isValidPlainText("Hi Nora,\n\nThe lease is signed.\n\nThanks,\nOmar", for: input))
    }

    func testBlankLinesBeyondTheDictatedParagraphsAreInvalid() {
        let input = "hi nora new paragraph the lease is signed"
        XCTAssertFalse(MagicFormatOutputSanitizer.isValidPlainText("Sure, here it is:\n\nHi Nora,\n\nThe lease is signed.", for: input))
    }

    func testPreambleLineBeforeDictatedParagraphsIsInvalid() {
        let input = "hi nora new paragraph the lease is signed"
        XCTAssertTrue(MagicFormatOutputSanitizer.isValidPlainText("Hi Nora,\n\nThe lease is signed.", for: input))
        XCTAssertFalse(MagicFormatOutputSanitizer.isValidPlainText("Here is the cleaned text:\nHi Nora,\n\nThe lease is signed.", for: input))
    }

    // MARK: - MagicFormatPipeline

    func testPipelineSendsDictatedParagraphsAsBlankLinesAndAcceptsThem() async throws {
        var prompts: [String] = []
        let output = try await MagicFormatPipeline.polish(
            text: "the movers arrive in the morning new paragraph tape the fragile boxes first",
            systemPrompt: "prompt",
            keywords: []
        ) { request in
            prompts.append(request.prompt)
            return "The movers arrive in the morning.\n\nTape the fragile boxes first."
        }

        XCTAssertEqual(output, "The movers arrive in the morning.\n\nTape the fragile boxes first.")
        XCTAssertEqual(prompts, ["<transcript>\nthe movers arrive in the morning\n\ntape the fragile boxes first\n</transcript>"])
    }

    func testPipelineTurnsALineBreakAtADictatedParagraphIntoABlankLine() async throws {
        let output = try await MagicFormatPipeline.polish(
            text: "the bakery sold out by noon new paragraph we baked more bread new paragraph we open earlier tomorrow",
            systemPrompt: "prompt",
            keywords: []
        ) { _ in
            "The bakery sold out by noon.  \nWe baked more bread.\nWe open earlier tomorrow."
        }

        XCTAssertEqual(output, "The bakery sold out by noon.\n\nWe baked more bread.\n\nWe open earlier tomorrow.")
    }

    func testPipelineLeavesAParagraphStartWithAnInnerCapitalAsWritten() async throws {
        let output = try await MagicFormatPipeline.polish(
            text: "my phone died new paragraph iPhone repairs take a week",
            systemPrompt: "prompt",
            keywords: []
        ) { _ in
            "My phone died.\n\niPhone repairs take a week."
        }

        XCTAssertEqual(output, "My phone died.\n\niPhone repairs take a week.")
    }

    func testPipelineKeepsLineBreaksWhenTheModelMergedADictatedParagraph() async throws {
        let output = try await MagicFormatPipeline.polish(
            text: "the bakery sold out by noon new paragraph we baked more bread new paragraph we open earlier tomorrow",
            systemPrompt: "prompt",
            keywords: []
        ) { _ in
            "The bakery sold out by noon. We baked more bread.\nWe open earlier tomorrow."
        }

        XCTAssertEqual(output, "The bakery sold out by noon. We baked more bread.\nWe open earlier tomorrow.")
    }

    func testPipelineKeepsLineBreaksWhenTheDictationAlsoAsksForLines() async throws {
        let output = try await MagicFormatPipeline.polish(
            text: "hi grace thanks new line sam new paragraph p s call me",
            systemPrompt: "prompt",
            keywords: []
        ) { _ in
            "Hi Grace, thanks,\nSam P.S. call me."
        }

        XCTAssertEqual(output, "Hi Grace, thanks,\nSam P.S. call me.")
    }

    func testPipelineKeepsNewParagraphAsWordsWhenItNamesAThing() async throws {
        for phrase in ["please add a new paragraph about pricing", "the docs need new paragraph spacing"] {
            var prompts: [String] = []
            _ = try await MagicFormatPipeline.polish(text: phrase, systemPrompt: "prompt", keywords: []) { request in
                prompts.append(request.prompt)
                return "Cleaned."
            }

            XCTAssertEqual(prompts, ["<transcript>\n\(phrase)\n</transcript>"])
        }
    }

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

    func testRetryCorrectionForDictatedParagraphsAsksForThoseBlankLinesOnly() {
        let instructions = MagicFormatPromptComposer.makeInstructions(
            systemPrompt: "prompt",
            keywords: [],
            text: "dear team comma new paragraph the offsite moves to friday new paragraph regards comma new line mia",
            retrying: true
        )

        XCTAssertTrue(instructions.contains("Put an empty line only where the speaker said \"new paragraph\"."))
        XCTAssertFalse(instructions.contains("One line."))
        XCTAssertFalse(instructions.contains("as a plain-text list"))
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
