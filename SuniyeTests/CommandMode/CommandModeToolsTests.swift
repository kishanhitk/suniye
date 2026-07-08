import XCTest
@testable import Suniye

@MainActor
final class CommandModeToolsTests: XCTestCase {
    private final class StringSink: @unchecked Sendable {
        var value: String?
    }

    private struct FakeLauncher: AppLaunching {
        let sink: StringSink
        func launchOrActivate(_ name: String) -> Bool { sink.value = name; return true }
    }

    private struct FakeTyper: TextTyping {
        let sink: StringSink
        func type(_ text: String) { sink.value = text }
    }

    private struct FakeScreen: ScreenReading {
        func readScreen() async -> String { "Frontmost app: Finder" }
    }

    func testOpenAppInvokesLauncher() async throws {
        let sink = StringSink()
        let tool = OpenAppTool(launcher: FakeLauncher(sink: sink))
        let result = try await tool.execute(["name": "Safari"])
        XCTAssertEqual(sink.value, "Safari")
        XCTAssertFalse(result.isTerminal)
    }

    func testOpenAppRejectsMissingName() async {
        let tool = OpenAppTool(launcher: FakeLauncher(sink: StringSink()))
        do {
            _ = try await tool.execute([:])
            XCTFail("expected malformedToolCall")
        } catch {
            XCTAssertEqual(error as? CommandModeError, .malformedToolCall("open_app needs 'name'"))
        }
    }

    func testTypeTextInvokesTyper() async throws {
        let sink = StringSink()
        let tool = TypeTextTool(typer: FakeTyper(sink: sink))
        _ = try await tool.execute(["text": "hello"])
        XCTAssertEqual(sink.value, "hello")
    }

    func testReadScreenReturnsObservation() async throws {
        let tool = ReadScreenTool(reader: FakeScreen())
        let result = try await tool.execute([:])
        XCTAssertTrue(result.output.contains("Finder"))
        XCTAssertFalse(result.isTerminal)
    }

    func testFinishIsTerminal() async throws {
        let result = try await FinishTool().execute(["summary": "done"])
        XCTAssertTrue(result.isTerminal)
        XCTAssertEqual(result.output, "done")
    }
}
