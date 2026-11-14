import XCTest
@testable import Suniye

@MainActor
final class MeetingTextSavesTests: XCTestCase {
    private let meeting = UUID()
    private var saved: [String] = []

    private func save(_ text: String, after delay: Duration = .zero) -> () async -> Void {
        { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            self?.saved.append(text)
        }
    }

    func testABurstOfTypingSavesOnceWithTheNewestText() async throws {
        let saves = MeetingTextSaves(pause: .milliseconds(50))
        saves.stage(.notes, of: meeting, save: save("a"))
        saves.stage(.notes, of: meeting, save: save("ab"))
        saves.stage(.notes, of: meeting, save: save("abc"))

        try await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(saved, ["abc"])
        XCTAssertTrue(saves.isIdle)
    }

    func testAPageChangeSavesBeforeThePauseEnds() async {
        let saves = MeetingTextSaves(pause: .seconds(60))
        saves.stage(.summary, of: meeting, save: save("typed just now"))

        saves.saveNow(meeting)
        await saves.finish()

        XCTAssertEqual(saved, ["typed just now"])
    }

    func testAQuitSavesWaitingTextAndWaitsForASlowSave() async {
        let saves = MeetingTextSaves(pause: .seconds(60))
        saves.save(.title, of: meeting, save: save("New title", after: .milliseconds(200)))
        saves.stage(.transcript, of: meeting, save: save("last words"))

        await saves.finish()

        XCTAssertEqual(Set(saved), ["New title", "last words"])
        XCTAssertTrue(saves.isIdle)
    }

    func testFinishAlsoSavesTextTypedWhileASaveRuns() async {
        for finishesAll in [false, true] {
            saved = []
            let saves = MeetingTextSaves(pause: .seconds(60))
            saves.save(.summary, of: meeting) { [weak self] in
                guard let self else { return }
                saves.stage(.summary, of: meeting, save: save("typed during the save"))
                try? await Task.sleep(for: .milliseconds(100))
                saved.append("first")
            }

            if finishesAll {
                await saves.finish()
            } else {
                await saves.finish(meeting)
            }

            XCTAssertEqual(saved, ["first", "typed during the save"], finishesAll ? "a quit" : "Regenerate or Transcribe Again")
            XCTAssertTrue(saves.isIdle)
        }
    }

    func testTheSavesOfOnePartLandInTheOrderTheyWereAskedFor() async {
        let saves = MeetingTextSaves(pause: .seconds(60))
        saves.save(.notes, of: meeting, save: save("older", after: .milliseconds(200)))
        saves.save(.notes, of: meeting, save: save("newer"))

        await saves.finish()

        XCTAssertEqual(saved, ["older", "newer"])
    }

    func testAPageChangeSavesOnlyItsOwnMeeting() async throws {
        let saves = MeetingTextSaves(pause: .seconds(60))
        saves.stage(.notes, of: meeting, save: save("this meeting"))
        saves.stage(.notes, of: UUID(), save: save("another meeting"))

        saves.saveNow(meeting)
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(saved, ["this meeting"])
        XCTAssertFalse(saves.isIdle)
    }
}
