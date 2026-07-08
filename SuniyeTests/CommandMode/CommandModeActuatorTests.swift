import XCTest
import CoreGraphics
import ApplicationServices
@testable import Suniye

@MainActor
final class CommandModeActuatorTests: XCTestCase {
    // MARK: KeyChord (pure)

    func testKeyChordParsesModifierAndLetter() {
        let parsed = KeyChord.parse("cmd+t")
        XCTAssertEqual(parsed?.keyCode, 17)
        XCTAssertTrue(parsed?.flags.contains(.maskCommand) ?? false)
    }

    func testKeyChordParsesMultipleModifiersAndNamedKeys() {
        let combo = KeyChord.parse("shift+cmd+4")
        XCTAssertEqual(combo?.keyCode, 21)
        XCTAssertTrue(combo?.flags.contains(.maskShift) ?? false)
        XCTAssertTrue(combo?.flags.contains(.maskCommand) ?? false)
        XCTAssertEqual(KeyChord.parse("return")?.keyCode, 36)
        XCTAssertEqual(KeyChord.parse("cmd+space")?.keyCode, 49)
    }

    func testKeyChordRejectsUnknown() {
        XCTAssertNil(KeyChord.parse("hyper+t"))
        XCTAssertNil(KeyChord.parse("cmd+😀"))
    }

    // MARK: Click/Focus (arg + unknown-element paths; a live AX press needs integration)

    private struct NilResolver: ElementResolving {
        func element(forId id: String) -> AXUIElement? { nil }
    }

    func testClickRejectsMissingId() async {
        do {
            _ = try await ClickTool(resolver: NilResolver()).execute([:])
            XCTFail("expected malformedToolCall")
        } catch {
            XCTAssertEqual(error as? CommandModeError, .malformedToolCall("click needs 'element_id'"))
        }
    }

    func testClickReportsUnknownElement() async throws {
        let result = try await ClickTool(resolver: NilResolver()).execute(["element_id": "e9"])
        XCTAssertTrue(result.output.contains("no element"))
        XCTAssertFalse(result.isTerminal)
    }

    // MARK: PressKeys posts the parsed chord

    private final class Sink: @unchecked Sendable { var code: CGKeyCode? }
    private struct RecordingPoster: KeyChordPosting {
        let sink: Sink
        func post(keyCode: CGKeyCode, flags: CGEventFlags) { sink.code = keyCode }
    }

    func testPressKeysPostsParsedChord() async throws {
        let sink = Sink()
        _ = try await PressKeysTool(poster: RecordingPoster(sink: sink)).execute(["keys": "cmd+t"])
        XCTAssertEqual(sink.code, 17)
    }

    func testPressKeysRejectsMissingKeys() async {
        do {
            _ = try await PressKeysTool(poster: RecordingPoster(sink: Sink())).execute([:])
            XCTFail("expected malformedToolCall")
        } catch {
            XCTAssertEqual(error as? CommandModeError, .malformedToolCall("press_keys needs 'keys'"))
        }
    }
}
