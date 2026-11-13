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
}
