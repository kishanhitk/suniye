import Foundation
import XCTest
@testable import Suniye

@MainActor
final class AppStateUpdateTests: XCTestCase {
    func testBackgroundCheckSetsAvailableWhenUpdateExists() async {
        let updateRelease = UpdateRelease(
            versionTag: "v0.0.2",
            publishedAt: nil,
            notes: "notes",
            htmlURL: URL(string: "https://example.test/release")!,
            assets: []
        )
        let updateService = StubUpdateService(checkResult: .success(.updateAvailable(updateRelease)))
        let appState = makeAppState(updateService: updateService)

        await appState.checkForUpdates(background: true)

        XCTAssertEqual(appState.updateStatus, .available)
        XCTAssertEqual(appState.availableUpdateVersion, "v0.0.2")
    }

    func testBackgroundCheckFailureStaysSilent() async {
        let updateService = StubUpdateService(checkResult: .failure(UpdateError.network("offline")))
        let appState = makeAppState(updateService: updateService)

        await appState.checkForUpdates(background: true)

        XCTAssertEqual(appState.updateStatus, .idle)
        XCTAssertNil(appState.availableUpdateVersion)
    }

    func testManualCheckFailureShowsError() async {
        let updateService = StubUpdateService(checkResult: .failure(UpdateError.network("offline")))
        let appState = makeAppState(updateService: updateService)

        await appState.checkForUpdates(background: false)

        XCTAssertEqual(appState.updateStatus, .error)
        XCTAssertEqual(appState.updateStatusText, "offline")
    }

    func testManualCheckUpToDateSetsStatus() async {
        let updateService = StubUpdateService(checkResult: .success(.upToDate))
        let appState = makeAppState(updateService: updateService)

        await appState.checkForUpdates(background: false)

        XCTAssertEqual(appState.updateStatus, .upToDate)
        XCTAssertEqual(appState.updateStatusText, "You're up to date.")
    }

    func testCheckIsIgnoredWhileAlreadyChecking() async {
        let updateService = StubUpdateService(checkResult: .success(.upToDate))
        let appState = makeAppState(updateService: updateService)
        appState.updateStatus = .checking

        await appState.checkForUpdates(background: false)

        XCTAssertEqual(updateService.checkCallCount, 0)
    }

    func testDownloadWithoutAvailableReleaseShowsError() async {
        let updateService = StubUpdateService(checkResult: .success(.upToDate))
        let appState = makeAppState(updateService: updateService)

        await appState.downloadAndOpenUpdate()

        XCTAssertEqual(appState.updateStatus, .error)
        XCTAssertEqual(appState.updateStatusText, "No update is currently available.")
    }

    func testDownloadAndOpenUpdateSetsErrorWhenOpenFails() async {
        let updateRelease = UpdateRelease(
            versionTag: "v0.0.2",
            publishedAt: nil,
            notes: "notes",
            htmlURL: URL(string: "https://example.test/release")!,
            assets: []
        )
        let tempArchiveURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let updateService = StubUpdateService(checkResult: .success(.updateAvailable(updateRelease)))
        updateService.downloadResult = .success(tempArchiveURL)
        let appState = makeAppState(updateService: updateService, fileOpener: { _ in false })

        await appState.checkForUpdates(background: false)
        await appState.downloadAndOpenUpdate()

        XCTAssertEqual(appState.updateStatus, .error)
        XCTAssertEqual(appState.updateStatusText, "Update downloaded, but failed to open installer.")
        XCTAssertEqual(appState.updateDownloadProgress, 0)
    }

    func testDownloadAndOpenUpdateMarksSuccessWhenOpenSucceeds() async {
        let updateRelease = UpdateRelease(
            versionTag: "v0.0.2",
            publishedAt: nil,
            notes: "notes",
            htmlURL: URL(string: "https://example.test/release")!,
            assets: []
        )
        let tempArchiveURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let updateService = StubUpdateService(checkResult: .success(.updateAvailable(updateRelease)))
        updateService.downloadResult = .success(tempArchiveURL)
        let appState = makeAppState(updateService: updateService, fileOpener: { _ in true })

        await appState.checkForUpdates(background: false)
        await appState.downloadAndOpenUpdate()

        XCTAssertEqual(appState.updateStatus, .available)
        XCTAssertEqual(appState.updateStatusText, "Update downloaded. Installer opened.")
        XCTAssertEqual(appState.updateDownloadProgress, 1)
    }

    private func makeAppState(
        updateService: StubUpdateService,
        fileOpener: @escaping (URL) -> Bool = { _ in true }
    ) -> AppState {
        makeTestAppState(
            llmSettingsStore: TestLLMSettingsStore(),
            generalSettingsStore: TestGeneralSettingsStore(),
            historyStore: TestHistoryStore(),
            keychainService: TestKeychainService(value: nil),
            updateService: updateService,
            launchAtLoginService: StubLaunchAtLoginService(),
            fileOpener: fileOpener
        )
    }
}
