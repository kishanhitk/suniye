import XCTest
@testable import Suniye

final class HotkeyServiceTests: XCTestCase {
    func testDictationCallbacksKeepPressAndReleasePhases() {
        let service = HotkeyService()
        var callbacks: [String] = []
        service.onHotkeyDown = { callbacks.append("down") }
        service.onHotkeyUp = { callbacks.append("up") }

        service.downCallback(for: .dictation)?()
        service.upCallback(for: .dictation)?()

        XCTAssertEqual(callbacks, ["down", "up"])
    }

    func testPasteLastTranscriptCallbackRunsOnKeyRelease() {
        let service = HotkeyService()
        var callbackCount = 0
        service.onPasteLastTranscript = {
            callbackCount += 1
        }

        service.downCallback(for: .pasteLastTranscript)?()
        XCTAssertEqual(callbackCount, 0)

        service.upCallback(for: .pasteLastTranscript)?()
        XCTAssertEqual(callbackCount, 1)
    }
}
