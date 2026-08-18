import AppKit
import ApplicationServices
import XCTest
@testable import Suniye

/// KIS-205: Chromium browsers keep their renderer accessibility tree switched
/// off until a real assistive technology enables it, and answer every focus
/// query with `kAXErrorNoValue`. That is a different situation from a non-text
/// control holding focus, and the two must not share an outcome.
final class TextInsertionColdTreeTests: XCTestCase {
    private func makeService(_ pasteboard: NSPasteboard) -> TextInsertionService {
        let service = TextInsertionService()
        service.pasteboardProvider = { pasteboard }
        service.focusedElementRetryIntervalNanoseconds = 0
        service.clipboardRestoreDelay = 0
        service.pasteKeyCodeProvider = { 9 }
        return service
    }

    private func makePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("dev.suniye.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("previous", forType: .string)
        return pasteboard
    }

    @MainActor
    func testPastesBlindWhenTheAppExposesNoFocusedElement() async throws {
        let pasteboard = makePasteboard()
        let service = makeService(pasteboard)
        var postedKeys: [(CGKeyCode, CGEventFlags)] = []

        service.focusedElementLookupProvider = { .unavailable }
        service.keyPoster = { key, flags in postedKeys.append((key, flags)) }

        let outcome = try await service.insertText("dictated text")

        XCTAssertEqual(outcome, .unverified)
        XCTAssertEqual(postedKeys.count, 1)
        XCTAssertEqual(postedKeys.first?.0, 9)
        XCTAssertEqual(postedKeys.first?.1, .maskCommand)
    }

    @MainActor
    func testBlindPasteRestoresThePreviousClipboard() async throws {
        let pasteboard = makePasteboard()
        let service = makeService(pasteboard)
        service.focusedElementLookupProvider = { .unavailable }
        service.keyPoster = { _, _ in }

        _ = try await service.insertText("dictated text")

        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(pasteboard.string(forType: .string), "previous")
    }

    @MainActor
    func testStillRefusesWhenAKnownNonTextControlHasFocus() async {
        let pasteboard = makePasteboard()
        let service = makeService(pasteboard)

        service.focusedElementLookupProvider = { .notTextInput }
        service.keyPoster = { _, _ in
            XCTFail("A paste must not be posted at a control we can see is not text")
        }

        do {
            _ = try await service.insertText("dictated text")
            XCTFail("Expected noFocusedTextInput")
        } catch {
            guard case TextInsertionService.InsertError.noFocusedTextInput = error else {
                return XCTFail("Expected noFocusedTextInput, got \(error)")
            }
        }
        // The clipboard is left alone so ⌃⌘V still recovers the transcript.
        XCTAssertEqual(pasteboard.string(forType: .string), "previous")
    }

    @MainActor
    func testAVisibleTextFieldReportsAVerifiedInsertion() async throws {
        let pasteboard = makePasteboard()
        let service = makeService(pasteboard)
        let element = AXUIElementCreateSystemWide()

        service.focusedElementLookupProvider = { .found(element) }
        service.focusedTextSnapshotProvider = { _ in
            (value: "hello", selectedText: nil, selectedRange: NSRange(location: 5, length: 0))
        }
        service.selectedTextSetter = { _, _ in false }
        service.keyPoster = { _, _ in }

        let outcome = try await service.insertText("dictated text")

        XCTAssertEqual(outcome, .intoFocusedElement)
    }

    /// An Electron composer reports `unavailable` only until its tree hydrates,
    /// so the retries must still prefer a real element over a blind paste.
    @MainActor
    func testHydrationStillWinsOverTheBlindPath() async throws {
        let pasteboard = makePasteboard()
        let service = makeService(pasteboard)
        let element = AXUIElementCreateSystemWide()
        var lookups = 0

        service.focusedElementLookupProvider = {
            lookups += 1
            return lookups < 3 ? .unavailable : .found(element)
        }
        service.focusedTextSnapshotProvider = { _ in
            (value: nil, selectedText: nil, selectedRange: nil)
        }
        service.selectedTextSetter = { _, _ in false }
        service.keyPoster = { _, _ in }

        let outcome = try await service.insertText("dictated text")

        XCTAssertEqual(lookups, 3)
        XCTAssertEqual(outcome, .intoFocusedElement)
    }

    /// The retry loop must report what the app last said, not a stale default:
    /// a control that stays non-text across every attempt is still a refusal.
    @MainActor
    func testRepeatedNonTextLookupsDoNotDecayIntoABlindPaste() async {
        let pasteboard = makePasteboard()
        let service = makeService(pasteboard)
        var lookups = 0

        service.focusedElementLookupProvider = {
            lookups += 1
            return .notTextInput
        }
        service.keyPoster = { _, _ in XCTFail("Must not paste blind") }

        do {
            _ = try await service.insertText("dictated text")
            XCTFail("Expected noFocusedTextInput")
        } catch {
            guard case TextInsertionService.InsertError.noFocusedTextInput = error else {
                return XCTFail("Expected noFocusedTextInput, got \(error)")
            }
        }
        XCTAssertEqual(lookups, 8)
    }
}
