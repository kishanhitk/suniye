import XCTest
@testable import Suniye

@MainActor
final class AppStateMeetingTests: XCTestCase {
    func testAFinishedSummaryIsAToastAndARecordingNoticeNeedsARecording() {
        let toasts = SpyLearningToastPresenter()
        let appState = makeTestAppState(learningToastPresenter: toasts)

        appState.showMeetingNotice(.microphoneChanged("AirPods Pro"))
        appState.showMeetingNotice(.summaryReady(UUID()))

        XCTAssertEqual(toasts.shownMessages, ["Summary ready"])
    }

    func testAQuitWaitsForTheTextThatAPageHasNotSaved() async {
        let appState = makeTestAppState()
        var saved = false
        appState.meetings.textSaves.stage(.notes, of: UUID()) { saved = true }

        let reply = appState.terminateReplyForMeeting()
        let done = await waitUntil { saved && appState.meetings.textSaves.isIdle }

        XCTAssertEqual(reply, .terminateLater)
        XCTAssertTrue(done)
    }

    func testAQuitWithNothingToSaveEndsAtOnce() {
        let appState = makeTestAppState()

        XCTAssertEqual(appState.terminateReplyForMeeting(), .terminateNow)
    }

    func testTranscribeAgainShowsWhenItEndsAndWhenItFails() {
        let toasts = SpyLearningToastPresenter()
        let appState = makeTestAppState(learningToastPresenter: toasts)

        appState.showMeetingNotice(.transcribedAgain(UUID()))
        appState.showMeetingNotice(.notTranscribedAgain(UUID()))

        XCTAssertEqual(toasts.shownMessages, ["Transcript ready", "Couldn’t transcribe again"])
    }

    func testATranscriptModelThatIsNotOnTheMacDownloadsWithoutBecomingTheDictationModel() async {
        let modelManager = StubModelManager()
        let appState = makeTestAppState(modelManager: modelManager)
        appState.phase = .ready
        appState.loadedASRModelID = .parakeetV3
        let dictationModel = appState.selectedASRModelID

        appState.useForMeetingTranscripts(.moonshineBase)
        let chosen = await waitUntil { appState.meetings.settings.transcriptModel == .moonshineBase }

        XCTAssertTrue(chosen)
        XCTAssertTrue(modelManager.installedModelIDs.contains(.moonshineBase))
        XCTAssertEqual(appState.loadedASRModelID, .parakeetV3, "dictation keeps its model")
        XCTAssertEqual(appState.selectedASRModelID, dictationModel)
        XCTAssertEqual(appState.phase, .ready)
    }

    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0 ..< 200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}
