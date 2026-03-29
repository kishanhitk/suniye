import Foundation
import XCTest
@testable import Suniye

@MainActor
final class AppStateUpdateTests: XCTestCase {
    func testAutomaticUpdateChecksRunImmediatelyWhenStarted() async {
        let updateService = StubUpdateService(checkResult: .success(.upToDate))
        let clock = TestClock()
        let appState = makeAppState(updateService: updateService, nowProvider: clock.now)

        appState.startAutomaticUpdateChecks()
        await waitForAutomaticCheckToFinish(updateService: updateService, appState: appState)

        XCTAssertEqual(updateService.checkCallCount, 1)
        XCTAssertEqual(appState.updateStatus, .idle)
    }

    func testAutomaticCheckIsSkippedWhenIntervalHasNotElapsed() async {
        let updateService = StubUpdateService(checkResult: .success(.upToDate))
        let clock = TestClock()
        let appState = makeAppState(updateService: updateService, nowProvider: clock.now)

        await appState.performAutomaticUpdateCheckIfEligible()
        clock.advance(hours: 4, minutes: 59)
        await appState.performAutomaticUpdateCheckIfEligible()

        XCTAssertEqual(updateService.checkCallCount, 1)
    }

    func testAutomaticCheckRunsAgainAfterFiveHours() async {
        let updateService = StubUpdateService(checkResult: .success(.upToDate))
        let clock = TestClock()
        let appState = makeAppState(updateService: updateService, nowProvider: clock.now)

        await appState.performAutomaticUpdateCheckIfEligible()
        clock.advance(hours: 5)
        await appState.performAutomaticUpdateCheckIfEligible()

        XCTAssertEqual(updateService.checkCallCount, 2)
    }

    func testAutomaticCheckIsSkippedWhileAlreadyChecking() async {
        let updateService = StubUpdateService(checkResult: .success(.upToDate))
        let clock = TestClock()
        let appState = makeAppState(updateService: updateService, nowProvider: clock.now)
        appState.updateStatus = .checking

        await appState.performAutomaticUpdateCheckIfEligible()

        XCTAssertEqual(updateService.checkCallCount, 0)
    }

    func testAutomaticCheckIsSkippedWhileDownloading() async {
        let updateService = StubUpdateService(checkResult: .success(.upToDate))
        let clock = TestClock()
        let appState = makeAppState(updateService: updateService, nowProvider: clock.now)
        appState.updateStatus = .downloading

        await appState.performAutomaticUpdateCheckIfEligible()

        XCTAssertEqual(updateService.checkCallCount, 0)
    }

    func testAutomaticCheckIsSkippedWhenUpdateIsReadyToInstall() async {
        let updateService = StubUpdateService(checkResult: .success(.upToDate))
        let clock = TestClock()
        let appState = makeAppState(updateService: updateService, nowProvider: clock.now)
        appState.updateStatus = .downloaded

        await appState.performAutomaticUpdateCheckIfEligible()

        XCTAssertEqual(updateService.checkCallCount, 0)
    }

    func testActivationCatchUpRunsOnlyAfterIntervalElapses() async {
        let updateService = StubUpdateService(checkResult: .success(.upToDate))
        let clock = TestClock()
        let appState = makeAppState(updateService: updateService, nowProvider: clock.now)

        await appState.performAutomaticUpdateCheckIfEligible()
        clock.advance(hours: 4)
        await appState.performAutomaticUpdateCheckIfEligible()
        clock.advance(hours: 1, minutes: 1)
        await appState.performAutomaticUpdateCheckIfEligible()

        XCTAssertEqual(updateService.checkCallCount, 2)
    }

    func testAutomaticCheckFailureStaysSilent() async {
        let updateService = StubUpdateService(checkResult: .failure(UpdateError.network("offline")))
        let clock = TestClock()
        let appState = makeAppState(updateService: updateService, nowProvider: clock.now)

        await appState.performAutomaticUpdateCheckIfEligible()

        XCTAssertEqual(appState.updateStatus, .idle)
        XCTAssertNil(appState.availableUpdateVersion)
    }

    func testBackgroundCheckSetsAvailableWhenUpdateExists() async {
        let updateRelease = UpdateRelease(
            versionTag: "v0.0.2",
            publishedAt: nil,
            notes: "notes",
            htmlURL: URL(string: "https://example.test/release")!,
            assets: []
        )
        let updateService = StubUpdateService(checkResult: .success(.updateAvailable(updateRelease)))
        let tempArchiveURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        updateService.downloadResult = .success(tempArchiveURL)
        let appState = makeAppState(updateService: updateService)

        await appState.checkForUpdates(background: true)

        XCTAssertEqual(appState.updateStatus, .downloaded)
        XCTAssertEqual(appState.availableUpdateVersion, "v0.0.2")
    }

    func testBackgroundCheckFailureStaysSilent() async {
        let updateService = StubUpdateService(checkResult: .failure(UpdateError.network("offline")))
        let appState = makeAppState(updateService: updateService)

        await appState.checkForUpdates(background: true)

        XCTAssertEqual(appState.updateStatus, .idle)
        XCTAssertNil(appState.availableUpdateVersion)
    }

    func testBackgroundCheckFailurePreservesAvailableState() async {
        let updateRelease = UpdateRelease(
            versionTag: "v0.0.2",
            publishedAt: nil,
            notes: "notes",
            htmlURL: URL(string: "https://example.test/release")!,
            assets: []
        )
        let updateService = StubUpdateService(checkResult: .success(.updateAvailable(updateRelease)))
        updateService.downloadResult = .failure(UpdateError.network("seed"))
        let appState = makeAppState(updateService: updateService)

        await appState.checkForUpdates(background: false)

        XCTAssertEqual(appState.updateStatus, .available)
        XCTAssertEqual(appState.updateStatusText, "Update available: \(updateRelease.versionTag)")

        updateService.checkResult = .failure(UpdateError.network("offline"))

        await appState.checkForUpdates(background: true)

        XCTAssertEqual(appState.updateStatus, .available)
        XCTAssertEqual(appState.updateStatusText, "Update available: \(updateRelease.versionTag)")
        XCTAssertEqual(appState.availableUpdateVersion, updateRelease.versionTag)
    }

    func testBackgroundCheckPreservesAvailableStateWhenLocalVersionIsMissing() async {
        let updateRelease = UpdateRelease(
            versionTag: "v0.0.2",
            publishedAt: nil,
            notes: "notes",
            htmlURL: URL(string: "https://example.test/release")!,
            assets: []
        )
        var currentVersion: AppVersion? = AppVersion(marketing: SemVer(rawValue: "0.0.1")!, build: 1)
        let updateService = StubUpdateService(checkResult: .success(.updateAvailable(updateRelease)))
        updateService.downloadResult = .failure(UpdateError.network("seed"))
        let appState = makeAppState(
            updateService: updateService,
            currentAppVersionProvider: { currentVersion }
        )

        await appState.checkForUpdates(background: false)

        XCTAssertEqual(appState.updateStatus, .available)

        currentVersion = nil

        await appState.checkForUpdates(background: true)

        XCTAssertEqual(appState.updateStatus, .available)
        XCTAssertEqual(appState.updateStatusText, "Update available: \(updateRelease.versionTag)")
        XCTAssertEqual(updateService.checkCallCount, 1)
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

    func testManualCheckPreservesCachedDownloadedInstaller() async {
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
        let appState = makeAppState(updateService: updateService)

        await appState.checkForUpdates(background: false)

        XCTAssertEqual(appState.updateStatus, .downloaded)
        XCTAssertEqual(appState.updateStatusText, "Update \(updateRelease.versionTag) is ready to install.")
        XCTAssertEqual(updateService.checkCallCount, 1)

        updateService.checkResult = .failure(UpdateError.network("offline"))
        updateService.downloadResult = .failure(UpdateError.network("offline"))

        await appState.checkForUpdates(background: false)

        XCTAssertEqual(appState.updateStatus, .downloaded)
        XCTAssertEqual(appState.updateStatusText, "Update \(updateRelease.versionTag) is ready to install.")
        XCTAssertEqual(appState.availableUpdateVersion, updateRelease.versionTag)
        XCTAssertEqual(updateService.checkCallCount, 1)
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

    func testDownloadAndOpenUpdateKeepsRetryStateWhenOpenFails() async {
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

        XCTAssertEqual(appState.updateStatus, .downloaded)
        XCTAssertEqual(appState.updateStatusText, "Update is ready to install. Failed to open the installer. Try again.")
        XCTAssertEqual(appState.updateDownloadProgress, 1)
    }

    func testDownloadAndOpenUpdateKeepsRetryStateWhenFreshDownloadCannotOpenInstaller() async {
        let updateRelease = UpdateRelease(
            versionTag: "v0.0.2",
            publishedAt: nil,
            notes: "notes",
            htmlURL: URL(string: "https://example.test/release")!,
            assets: []
        )
        let tempArchiveURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let updateService = StubUpdateService(checkResult: .success(.updateAvailable(updateRelease)))
        updateService.downloadResult = .failure(UpdateError.network("temporary"))
        let appState = makeAppState(updateService: updateService, fileOpener: { _ in false })

        await appState.checkForUpdates(background: false)

        XCTAssertEqual(appState.updateStatus, .available)

        updateService.downloadResult = .success(tempArchiveURL)
        await appState.downloadAndOpenUpdate()

        XCTAssertEqual(appState.updateStatus, .downloaded)
        XCTAssertEqual(appState.updateStatusText, "Update downloaded. Failed to open installer. Try again.")
        XCTAssertEqual(appState.updateDownloadProgress, 1)
    }

    func testDownloadAndOpenUpdateKeepsAvailableStateWhenFreshDownloadFails() async {
        let updateRelease = UpdateRelease(
            versionTag: "v0.0.2",
            publishedAt: nil,
            notes: "notes",
            htmlURL: URL(string: "https://example.test/release")!,
            assets: []
        )
        let updateService = StubUpdateService(checkResult: .success(.updateAvailable(updateRelease)))
        updateService.downloadResult = .failure(UpdateError.network("offline"))
        let appState = makeAppState(updateService: updateService)

        await appState.checkForUpdates(background: false)

        XCTAssertEqual(appState.updateStatus, .available)
        XCTAssertEqual(appState.updateStatusText, "Update available: \(updateRelease.versionTag)")

        await appState.downloadAndOpenUpdate()

        XCTAssertEqual(appState.updateStatus, .available)
        XCTAssertEqual(appState.updateStatusText, "offline")
        XCTAssertEqual(appState.updateDownloadProgress, 0)
        XCTAssertEqual(appState.availableUpdateVersion, updateRelease.versionTag)
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

        XCTAssertEqual(appState.updateStatus, .downloaded)
        XCTAssertEqual(appState.updateStatusText, "Installer opened for v0.0.2.")
        XCTAssertEqual(appState.updateDownloadProgress, 1)
    }

    private func makeAppState(
        updateService: StubUpdateService,
        currentAppVersionProvider: @escaping () -> AppVersion? = { AppVersion(marketing: SemVer(rawValue: "0.0.1")!, build: 1) },
        nowProvider: @escaping () -> Date = Date.init,
        fileOpener: @escaping (URL) -> Bool = { _ in true }
    ) -> AppState {
        makeTestAppState(
            llmSettingsStore: TestLLMSettingsStore(),
            generalSettingsStore: TestGeneralSettingsStore(),
            historyStore: TestHistoryStore(),
            keychainService: TestKeychainService(value: nil),
            updateService: updateService,
            launchAtLoginService: StubLaunchAtLoginService(),
            currentAppVersionProvider: currentAppVersionProvider,
            nowProvider: nowProvider,
            fileOpener: fileOpener
        )
    }

    private func waitForAutomaticCheckToFinish(updateService: StubUpdateService, appState: AppState) async {
        for _ in 0..<20 {
            if updateService.checkCallCount == 1 && appState.updateStatus == .idle {
                return
            }
            await Task.yield()
        }
    }
}

private final class TestClock {
    private(set) var current = Date(timeIntervalSince1970: 1_741_337_600)

    func now() -> Date {
        current
    }

    func advance(hours: Int = 0, minutes: Int = 0) {
        current = current.addingTimeInterval(TimeInterval((hours * 60 + minutes) * 60))
    }
}
