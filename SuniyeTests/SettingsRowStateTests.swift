import SwiftUI
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

    /// While Magic Format is on, search leaves out a row that the page hides:
    /// opening it would find nothing.
    func testMagicFormatRowsHiddenWhileOnAreNotListed() {
        let appState = makeTestAppState()
        appState.llmProvider = .openAICompatible
        appState.llmEnabled = true
        XCTAssertFalse(SettingsRowID.keepAlive.isSearchable(in: appState))

        appState.llmEnabled = false
        XCTAssertTrue(SettingsRowID.keepAlive.isSearchable(in: appState))
        XCTAssertEqual(SettingsRowID.keepAlive.searchTarget(in: appState), .magicFormat)
    }

    func testNeverAskForOpensNothingWhileTheListIsEmpty() {
        let appState = makeTestAppState()

        appState.meetings.updateSettings { $0.neverAskBundleIDs = [] }
        XCTAssertFalse(SettingsRowID.neverAskFor.isEnabled(in: appState))

        appState.meetings.updateSettings { $0.neverAskBundleIDs = ["us.zoom.xos"] }
        XCTAssertTrue(SettingsRowID.neverAskFor.isEnabled(in: appState))
    }

    /// A row built from the catalog shows the hint that search matches and is
    /// dimmed when its control can change nothing.
    func testCatalogRowsShowTheirCurrentState() {
        let appState = makeTestAppState()
        appState.meetings.updateSettings {
            $0.audioRetention = .thirtyDays
            $0.neverAskBundleIDs = []
        }

        let files = ControlSettingRow(.meetingFiles, in: appState) { EmptyView() }
        XCTAssertEqual(files.title, "Meeting files")
        XCTAssertEqual(files.info, "Audio is deleted 30 days after the meeting.")
        XCTAssertEqual(files.anchor, .meetingFiles)

        let neverAsk = DisclosureSettingRow(.neverAskFor, in: appState, value: "None")
        XCTAssertFalse(neverAsk.isEnabled)
        XCTAssertEqual(neverAsk.anchor, .neverAskFor)
    }
}
