import AppKit
import XCTest
@testable import Suniye

@MainActor
final class EditModeServiceTests: XCTestCase {
    private enum TestError: Error {
        case keyPostFailed
    }

    // MARK: - Prompt builder

    func testPromptBuilderComposesRewriteUserText() {
        let userText = EditModePromptBuilder.userText(
            instruction: " make this formal ",
            selectedText: "hey what's up"
        )

        XCTAssertEqual(
            userText,
            """
            <instruction>
            make this formal
            </instruction>

            <text>
            hey what's up
            </text>
            """
        )
        XCTAssertEqual(
            EditModePromptBuilder.systemPrompt(selectedText: "hey what's up"),
            EditModePromptBuilder.rewriteSystemPrompt
        )
    }

    func testPromptBuilderFallsBackToWriteModeWithoutSelection() {
        for selection in [nil, "", "   \n"] {
            let userText = EditModePromptBuilder.userText(
                instruction: "write a polite decline",
                selectedText: selection
            )

            XCTAssertEqual(
                userText,
                """
                <instruction>
                write a polite decline
                </instruction>
                """
            )
            XCTAssertEqual(
                EditModePromptBuilder.systemPrompt(selectedText: selection),
                EditModePromptBuilder.writeSystemPrompt
            )
        }
    }

    func testPromptBuilderPreservesSelectedTextVerbatim() {
        let selection = "line one\n\nline two  "
        let userText = EditModePromptBuilder.userText(instruction: "fix grammar", selectedText: selection)

        XCTAssertTrue(userText.contains("<text>\n\(selection)\n</text>"))
    }

    // MARK: - Selection capture

    func testCaptureReturnsNilWithoutAccessibilityTrust() async {
        let service = EditModeService(
            accessibilityTrustProvider: { false },
            focusedElementProvider: {
                XCTFail("AX lookup should not run without accessibility trust")
                return nil
            },
            keyPoster: { _, _ in
                XCTFail("No key events should be posted without accessibility trust")
            }
        )

        let selection = await service.captureSelectedText()

        XCTAssertNil(selection)
    }

    func testCapturePrefersAccessibilitySelectionOverClipboard() async {
        let element = AXUIElementCreateSystemWide()
        var readElement: AXUIElement?
        let service = EditModeService(
            accessibilityTrustProvider: { true },
            focusedElementProvider: { element },
            selectedTextReader: { element in
                readElement = element
                return "selected via ax"
            },
            keyPoster: { _, _ in
                XCTFail("Clipboard fallback should not run when AX selection is available")
            }
        )

        let selection = await service.captureSelectedText()

        XCTAssertEqual(selection, "selected via ax")
        XCTAssertTrue(readElement.map { CFEqual($0, element) } == true)
    }

    func testEmptyAccessibilitySelectionFallsThroughToClipboard() async {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("dev.suniye.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()

        var keyPosted = false
        let service = EditModeService(
            accessibilityTrustProvider: { true },
            focusedElementProvider: { AXUIElementCreateSystemWide() },
            selectedTextReader: { _ in "" },
            pasteboardProvider: { pasteboard },
            keyPoster: { _, _ in keyPosted = true },
            copyWaitPollNanoseconds: 1_000_000,
            copyWaitMaxPolls: 2
        )

        let selection = await service.captureSelectedText()

        XCTAssertNil(selection)
        XCTAssertTrue(keyPosted)
    }

    func testClipboardFallbackRestoresPreviousClipboard() async {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("dev.suniye.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("previous clipboard", forType: .string)

        var postedKeys: [(CGKeyCode, CGEventFlags)] = []
        let service = EditModeService(
            accessibilityTrustProvider: { true },
            focusedElementProvider: { nil },
            pasteboardProvider: { pasteboard },
            keyPoster: { keyCode, flags in
                postedKeys.append((keyCode, flags))
                // Simulate the frontmost app answering Cmd+C.
                pasteboard.clearContents()
                pasteboard.setString("copied selection", forType: .string)
            },
            copyWaitPollNanoseconds: 1_000_000
        )

        let selection = await service.captureSelectedText()

        XCTAssertEqual(selection, "copied selection")
        XCTAssertEqual(postedKeys.count, 1)
        XCTAssertEqual(postedKeys[0].0, TextInsertionService.virtualKeyCode(for: "c") ?? 8)
        XCTAssertEqual(postedKeys[0].1, .maskCommand)
        XCTAssertEqual(pasteboard.string(forType: .string), "previous clipboard")
    }

    func testClipboardFallbackReturnsNilAndKeepsClipboardWhenNothingCopied() async {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("dev.suniye.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("previous clipboard", forType: .string)
        let changeCountBefore = pasteboard.changeCount

        let service = EditModeService(
            accessibilityTrustProvider: { true },
            focusedElementProvider: { nil },
            pasteboardProvider: { pasteboard },
            keyPoster: { _, _ in },
            copyWaitPollNanoseconds: 1_000_000,
            copyWaitMaxPolls: 2
        )

        let selection = await service.captureSelectedText()

        XCTAssertNil(selection)
        XCTAssertEqual(pasteboard.string(forType: .string), "previous clipboard")
        XCTAssertEqual(pasteboard.changeCount, changeCountBefore)
    }

    func testClipboardFallbackRestoresClipboardWhenKeyPostFails() async {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("dev.suniye.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("previous clipboard", forType: .string)

        let service = EditModeService(
            accessibilityTrustProvider: { true },
            focusedElementProvider: { nil },
            pasteboardProvider: { pasteboard },
            keyPoster: { _, _ in
                throw TestError.keyPostFailed
            }
        )

        let selection = await service.captureSelectedText()

        XCTAssertNil(selection)
        XCTAssertEqual(pasteboard.string(forType: .string), "previous clipboard")
    }
}
