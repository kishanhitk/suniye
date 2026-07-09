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

    // MARK: Click/Focus (arg guard + delegation; the native/browser action lives in the surface)

    func testClickRejectsMissingId() async {
        do {
            _ = try await ClickTool(surface: FakeCommandSurface()).execute([:])
            XCTFail("expected malformedToolCall")
        } catch {
            XCTAssertEqual(error as? CommandModeError, .malformedToolCall("click needs 'element_id'"))
        }
    }

    func testClickDelegatesToSurface() async throws {
        let surface = FakeCommandSurface()
        let result = try await ClickTool(surface: surface).execute(["element_id": "e9"])
        XCTAssertEqual(surface.clicks, ["e9"])
        XCTAssertEqual(result.output, "clicked e9")
        XCTAssertFalse(result.isTerminal)
    }

    // MARK: PressKeys posts the parsed chord

    private final class Sink: @unchecked Sendable { var code: CGKeyCode?; var text: String? }
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

    // MARK: Closure adapters forward to their backing calls

    func testClosureAdaptersForward() async throws {
        let generator = ClosureAgentTextGenerator { instructions, userText in "\(instructions)|\(userText)" }
        let out = try await generator.generate(instructions: "a", userText: "b")
        XCTAssertEqual(out, "a|b")

        let sink = Sink()
        let typer = ClosureTextTyping { sink.text = $0 }
        typer.type("hi")
        XCTAssertEqual(sink.text, "hi")
    }
}
