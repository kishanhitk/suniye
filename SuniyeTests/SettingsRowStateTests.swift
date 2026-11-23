import XCTest
@testable import Suniye

@MainActor
final class SettingsRowStateTests: XCTestCase {
    func testPermissionRowsShowOnlyWhileTheGrantIsMissing() {
        let appState = makeTestAppState()
        appState.hasMicPermission = false
        XCTAssertTrue(SettingsRowID.microphonePermission.isAvailable(in: appState))
        XCTAssertTrue(SettingsRowID.microphonePermission.isSearchable(in: appState))

        appState.hasMicPermission = true
        XCTAssertFalse(SettingsRowID.microphonePermission.isAvailable(in: appState))
        XCTAssertFalse(SettingsRowID.microphonePermission.isSearchable(in: appState))
    }

    /// While Magic Format is off its rows are hidden, but search still lists
    /// them and opens the page at its switch.
    func testMagicFormatRowsStaySearchableWhileOff() {
        let appState = makeTestAppState()
        appState.llmEnabled = false
        XCTAssertFalse(SettingsRowID.vocabulary.isAvailable(in: appState))
        XCTAssertTrue(SettingsRowID.vocabulary.isSearchable(in: appState))
        XCTAssertEqual(SettingsRowID.vocabulary.searchTarget(in: appState), .magicFormat)

        appState.llmEnabled = true
        XCTAssertTrue(SettingsRowID.vocabulary.isAvailable(in: appState))
        XCTAssertEqual(SettingsRowID.vocabulary.searchTarget(in: appState), .vocabulary)
    }

    /// A build without updates hides the controls that would do nothing and
    /// says why on the Version row.
    func testUpdateRowsFollowTheUpdateController() {
        let disabled = makeTestAppState(appUpdateController: DisabledUpdateController())
        XCTAssertFalse(disabled.updatesEnabled)
        XCTAssertFalse(SettingsRowID.updateChannel.isAvailable(in: disabled))
        XCTAssertFalse(SettingsRowID.checkAutomatically.isAvailable(in: disabled))
        XCTAssertEqual(SettingsRowID.version.currentInfo(in: disabled), "Updates are off in this build.")

        let enabled = makeTestAppState(appUpdateController: StubAppUpdateController())
        XCTAssertTrue(enabled.updatesEnabled)
        XCTAssertTrue(SettingsRowID.updateChannel.isAvailable(in: enabled))
        XCTAssertNil(SettingsRowID.version.currentInfo(in: enabled))
    }

    /// Live preview needs a model that writes text while you speak.
    func testLivePreviewNeedsAStreamingModel() {
        let appState = makeTestAppState()

        appState.selectedASRModelID = .appleSpeech
        XCTAssertFalse(SettingsRowID.liveTranscriptionPreview.isEnabled(in: appState))
        XCTAssertEqual(
            SettingsRowID.liveTranscriptionPreview.currentInfo(in: appState),
            "Not available with Apple Speech."
        )

        appState.selectedASRModelID = .parakeetV3
        XCTAssertTrue(SettingsRowID.liveTranscriptionPreview.isEnabled(in: appState))
        XCTAssertNil(SettingsRowID.liveTranscriptionPreview.currentInfo(in: appState))
    }

    /// The Meeting files hint says when audio goes, from the retention chosen.
    func testMeetingFilesHintFollowsTheRetention() {
        let appState = makeTestAppState()

        appState.meetings.updateSettings { $0.audioRetention = .sevenDays }
        XCTAssertEqual(SettingsRowID.meetingFiles.currentInfo(in: appState), "Audio is deleted 7 days after the meeting.")

        appState.meetings.updateSettings { $0.audioRetention = .untilTranscript }
        XCTAssertEqual(SettingsRowID.meetingFiles.currentInfo(in: appState), "Audio is deleted when the transcript is ready.")
    }

    func testOtherRowsAreEnabledAndKeepTheirCatalogHint() {
        let appState = makeTestAppState()
        XCTAssertTrue(SettingsRowID.echoCancellation.isEnabled(in: appState))
        XCTAssertEqual(SettingsRowID.echoCancellation.currentInfo(in: appState), SettingsRowID.echoCancellation.info)
    }

    /// A search result opens its pane and row; a Magic Format row opens the
    /// Magic Format page.
    func testRowDestinations() {
        XCTAssertEqual(
            MainWindowDestination.row(.holdToDictate),
            MainWindowDestination(section: .settings, pane: .shortcuts, row: .holdToDictate)
        )
        XCTAssertEqual(
            MainWindowDestination.row(.vocabulary),
            MainWindowDestination(section: .style, row: .vocabulary)
        )
        XCTAssertEqual(MainWindowDestination.settingsSearch.section, .settings)
        XCTAssertTrue(MainWindowDestination.settingsSearch.focusesSearch)
    }
}
