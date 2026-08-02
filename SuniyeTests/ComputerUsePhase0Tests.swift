import CoreGraphics
import Foundation
import XCTest
@testable import Suniye

final class ComputerUsePhase0Tests: XCTestCase {
    func testObservationReturnsBoundedStateAndIncrementsGeneration() throws {
        let application = makeApplication()
        let window = makeWindow(isKeyWindow: true)
        let axSnapshot = ComputerUseAXSnapshot(
            text: "[0] role=AXWindow title=Notes",
            elements: [],
            wasTruncated: false
        )
        let screenshot = ComputerUseScreenshot(
            data: Data([1, 2, 3]),
            mimeType: "image/png",
            width: 20,
            height: 10
        )
        let service = makeObservationService(
            application: application,
            windows: [window],
            axSnapshot: axSnapshot,
            screenshot: screenshot,
            now: Date(timeIntervalSince1970: 123)
        )

        let first = try service.observe(applicationID: application.id, includeScreenshot: true)
        let second = try service.observe(applicationID: application.id, includeScreenshot: false)

        XCTAssertEqual(first.generation, 1)
        XCTAssertEqual(second.generation, 2)
        XCTAssertEqual(first.target.application, application)
        XCTAssertEqual(first.target.window, window)
        XCTAssertEqual(first.accessibility, axSnapshot)
        XCTAssertEqual(first.screenshot, screenshot)
        XCTAssertNil(second.screenshot)
        XCTAssertEqual(first.capturedAt, Date(timeIntervalSince1970: 123))
    }

    func testObservationPrefersKeyWindow() throws {
        let application = makeApplication()
        let backgroundWindow = makeWindow(id: 1, isKeyWindow: false)
        let keyWindow = makeWindow(id: 2, isKeyWindow: true)
        let windowDiscovery = StubWindowDiscovery(windows: [backgroundWindow, keyWindow])
        let axReader = StubAccessibilityReader()
        let service = makeObservationService(
            application: application,
            windows: [backgroundWindow, keyWindow],
            axReader: axReader,
            windowDiscovery: windowDiscovery
        )

        _ = try service.observe(applicationID: application.id, includeScreenshot: false)

        XCTAssertEqual(axReader.lastWindow?.id, keyWindow.id)
        XCTAssertEqual(windowDiscovery.lastApplication?.id, application.id)
    }

    func testObservationFailsBeforeDiscoveryWhenAccessibilityIsMissing() {
        let application = makeApplication()
        let windowDiscovery = StubWindowDiscovery(windows: [makeWindow()])
        let service = makeObservationService(
            application: application,
            windows: [makeWindow()],
            permissionSnapshot: ComputerUsePermissionSnapshot(
                accessibility: .notGranted,
                screenRecording: .granted
            ),
            windowDiscovery: windowDiscovery
        )

        XCTAssertThrowsError(try service.observe(applicationID: application.id, includeScreenshot: false)) { error in
            XCTAssertEqual(error as? ComputerUseObservationError, .accessibilityNotTrusted)
        }
        XCTAssertNil(windowDiscovery.lastApplication)
    }

    func testObservationRequiresScreenRecordingOnlyForScreenshot() throws {
        let application = makeApplication()
        let service = makeObservationService(
            application: application,
            windows: [makeWindow()],
            permissionSnapshot: ComputerUsePermissionSnapshot(
                accessibility: .granted,
                screenRecording: .notGranted
            )
        )

        XCTAssertThrowsError(try service.observe(applicationID: application.id, includeScreenshot: true)) { error in
            XCTAssertEqual(error as? ComputerUseObservationError, .screenRecordingNotGranted)
        }

        let observation = try service.observe(applicationID: application.id, includeScreenshot: false)
        XCTAssertNil(observation.screenshot)
    }

    func testObservationReportsUnknownApplication() {
        let service = ComputerUseObservationService(
            applicationCatalog: StubApplicationCatalog(applications: []),
            windowDiscovery: StubWindowDiscovery(windows: []),
            accessibilityReader: StubAccessibilityReader(),
            screenshotCapturer: StubScreenshotCapturer(),
            permissionManager: StubPermissionManager(snapshot: readyPermissions)
        )

        XCTAssertThrowsError(try service.observe(applicationID: "com.example.missing", includeScreenshot: false)) { error in
            XCTAssertEqual(
                error as? ComputerUseObservationError,
                .applicationNotFound("com.example.missing")
            )
        }
    }

    func testObservationReportsMissingWindow() {
        let application = makeApplication()
        let service = makeObservationService(application: application, windows: [])

        XCTAssertThrowsError(try service.observe(applicationID: application.id, includeScreenshot: false)) { error in
            XCTAssertEqual(error as? ComputerUseObservationError, .noWindow(application.id))
        }
    }

    func testObservationReportsStoppedApplication() {
        var application = makeApplication()
        application = ComputerUseApplication(
            id: application.id,
            bundleIdentifier: application.bundleIdentifier,
            displayName: application.displayName,
            processIdentifier: application.processIdentifier,
            isRunning: false,
            isActive: false,
            launchDate: application.launchDate
        )
        let service = makeObservationService(application: application, windows: [makeWindow()])

        XCTAssertThrowsError(try service.observe(applicationID: application.id, includeScreenshot: false)) { error in
            XCTAssertEqual(error as? ComputerUseObservationError, .applicationNotRunning(application.id))
        }
    }

    func testObservationPropagatesScreenshotFailure() {
        let application = makeApplication()
        let service = ComputerUseObservationService(
            applicationCatalog: StubApplicationCatalog(applications: [application]),
            windowDiscovery: StubWindowDiscovery(windows: [makeWindow()]),
            accessibilityReader: StubAccessibilityReader(),
            screenshotCapturer: StubScreenshotCapturer(error: ComputerUseObservationError.screenshotUnavailable),
            permissionManager: StubPermissionManager(snapshot: readyPermissions)
        )

        XCTAssertThrowsError(try service.observe(applicationID: application.id, includeScreenshot: true)) { error in
            XCTAssertEqual(error as? ComputerUseObservationError, .screenshotUnavailable)
        }
    }

    func testObservationErrorDescriptionsCoverStableFailureCategories() {
        let errors: [ComputerUseObservationError] = [
            .cancelled,
            .applicationNotFound("missing"),
            .applicationNotRunning("stopped"),
            .noWindow("empty"),
            .accessibilityNotTrusted,
            .accessibilityWindowNotFound("untitled"),
            .accessibilityReadFailed("AXRole"),
            .screenRecordingNotGranted,
            .screenshotUnavailable,
        ]

        for error in errors {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    func testPermissionSnapshotComputedProperties() {
        let ready = readyPermissions
        XCTAssertTrue(ready.canReadAccessibility)
        XCTAssertTrue(ready.canCaptureScreen)
        XCTAssertTrue(ready.canObserveWithScreenshot)

        let incomplete = ComputerUsePermissionSnapshot(
            accessibility: .granted,
            screenRecording: .notGranted
        )
        XCTAssertTrue(incomplete.canReadAccessibility)
        XCTAssertFalse(incomplete.canCaptureScreen)
        XCTAssertFalse(incomplete.canObserveWithScreenshot)
    }

    func testRectDetectsEmptyGeometry() {
        XCTAssertTrue(ComputerUseRect(x: 0, y: 0, width: 0, height: 10).isEmpty)
        XCTAssertTrue(ComputerUseRect(x: 0, y: 0, width: 10, height: -1).isEmpty)
        XCTAssertFalse(ComputerUseRect(x: 0, y: 0, width: 10, height: 10).isEmpty)
    }

    func testCancellationBeforeObservationStopsTheLoop() {
        let application = makeApplication()
        let service = makeObservationService(application: application, windows: [makeWindow()])
        let cancellation = ComputerUseCancellationToken()
        cancellation.cancel()

        XCTAssertThrowsError(
            try service.observe(
                applicationID: application.id,
                includeScreenshot: false,
                configuration: .default,
                cancellation: cancellation
            )
        ) { error in
            XCTAssertEqual(error as? ComputerUseObservationError, .cancelled)
        }
    }

    func testCancellationAfterAccessibilityReadDoesNotPublishObservation() {
        let application = makeApplication()
        let cancellation = ComputerUseCancellationToken()
        let axReader = StubAccessibilityReader { cancellation.cancel() }
        let service = makeObservationService(
            application: application,
            windows: [makeWindow()],
            axReader: axReader
        )

        XCTAssertThrowsError(
            try service.observe(
                applicationID: application.id,
                includeScreenshot: false,
                configuration: .default,
                cancellation: cancellation
            )
        ) { error in
            XCTAssertEqual(error as? ComputerUseObservationError, .cancelled)
        }
    }

    func testPermissionServiceReportsStateAndForwardsRequests() {
        var accessibilityPrompted = false
        var screenRecordingRequested = false
        let service = SystemComputerUsePermissionService(
            accessibilityTrustProvider: { false },
            accessibilityPromptRequester: {
                accessibilityPrompted = true
                return true
            },
            screenRecordingAccessProvider: { true },
            screenRecordingRequester: {
                screenRecordingRequested = true
                return false
            }
        )

        XCTAssertEqual(
            service.snapshot(),
            ComputerUsePermissionSnapshot(
                accessibility: .notGranted,
                screenRecording: .granted
            )
        )
        XCTAssertTrue(service.requestAccessibility())
        XCTAssertFalse(service.requestScreenRecording())
        XCTAssertTrue(accessibilityPrompted)
        XCTAssertTrue(screenRecordingRequested)
    }

    func testWindowDiscoveryDecodesWindowInfoAndMarksFrontmostWindow() {
        let application = makeApplication()
        let discovery = SystemComputerUseWindowDiscovery(
            windowInfoProvider: {
                [
                    [
                        kCGWindowOwnerPID as String: NSNumber(value: application.processIdentifier),
                        kCGWindowNumber as String: NSNumber(value: 42),
                        kCGWindowLayer as String: NSNumber(value: 0),
                        kCGWindowName as String: "Main",
                        kCGWindowBounds as String: [
                            "X": CGFloat(10),
                            "Y": CGFloat(20),
                            "Width": CGFloat(300),
                            "Height": CGFloat(200),
                        ],
                    ],
                ]
            },
            frontmostProcessIdentifierProvider: { application.processIdentifier }
        )

        let windows = discovery.listWindows(for: application)

        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].id, 42)
        XCTAssertEqual(windows[0].title, "Main")
        XCTAssertTrue(windows[0].isKeyWindow)
        XCTAssertEqual(windows[0].bounds, ComputerUseRect(x: 10, y: 20, width: 300, height: 200))
    }

    func testScreenshotServiceEncodesInjectedImageAsPNG() throws {
        let image = makeTestImage()
        let service = CoreGraphicsComputerUseScreenshotService { _, _ in image }

        let screenshot = try service.capture(window: makeWindow())

        XCTAssertEqual(screenshot.mimeType, "image/png")
        XCTAssertEqual(screenshot.width, 1)
        XCTAssertEqual(screenshot.height, 1)
        XCTAssertFalse(screenshot.data.isEmpty)
    }

    private var readyPermissions: ComputerUsePermissionSnapshot {
        ComputerUsePermissionSnapshot(accessibility: .granted, screenRecording: .granted)
    }

    private func makeObservationService(
        application: ComputerUseApplication,
        windows: [ComputerUseWindow],
        axSnapshot: ComputerUseAXSnapshot = ComputerUseAXSnapshot(text: "", elements: [], wasTruncated: false),
        screenshot: ComputerUseScreenshot = ComputerUseScreenshot(data: Data(), mimeType: "image/png", width: 1, height: 1),
        permissionSnapshot: ComputerUsePermissionSnapshot = ComputerUsePermissionSnapshot(accessibility: .granted, screenRecording: .granted),
        axReader: StubAccessibilityReader? = nil,
        windowDiscovery: StubWindowDiscovery? = nil,
        now: Date = Date(timeIntervalSince1970: 0)
    ) -> ComputerUseObservationService {
        ComputerUseObservationService(
            applicationCatalog: StubApplicationCatalog(applications: [application]),
            windowDiscovery: windowDiscovery ?? StubWindowDiscovery(windows: windows),
            accessibilityReader: axReader ?? StubAccessibilityReader(snapshot: axSnapshot),
            screenshotCapturer: StubScreenshotCapturer(screenshot: screenshot),
            permissionManager: StubPermissionManager(snapshot: permissionSnapshot),
            dateProvider: { now }
        )
    }

    private func makeApplication() -> ComputerUseApplication {
        ComputerUseApplication(
            id: "com.example.notes",
            bundleIdentifier: "com.example.notes",
            displayName: "Notes",
            processIdentifier: 1234,
            isRunning: true,
            isActive: true,
            launchDate: Date(timeIntervalSince1970: 1)
        )
    }

    private func makeWindow(id: UInt32 = 7, isKeyWindow: Bool = true) -> ComputerUseWindow {
        ComputerUseWindow(
            id: id,
            title: "Main",
            ownerProcessIdentifier: 1234,
            bounds: ComputerUseRect(x: 10, y: 20, width: 300, height: 200),
            layer: 0,
            isOnScreen: true,
            isKeyWindow: isKeyWindow
        )
    }

    private func makeTestImage() -> CGImage {
        let pixel = Data([255, 0, 0, 255])
        let provider = CGDataProvider(data: pixel as CFData)!
        return CGImage(
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }
}

private final class StubApplicationCatalog: ComputerUseApplicationCatalog {
    let applications: [ComputerUseApplication]

    init(applications: [ComputerUseApplication]) {
        self.applications = applications
    }

    func listApplications() -> [ComputerUseApplication] {
        applications
    }

    func application(withID identifier: String) -> ComputerUseApplication? {
        applications.first { $0.id == identifier }
    }
}

private final class StubWindowDiscovery: ComputerUseWindowDiscovering {
    let windows: [ComputerUseWindow]
    private(set) var lastApplication: ComputerUseApplication?

    init(windows: [ComputerUseWindow]) {
        self.windows = windows
    }

    func listWindows(for application: ComputerUseApplication) -> [ComputerUseWindow] {
        lastApplication = application
        return windows
    }
}

private final class StubAccessibilityReader: ComputerUseAccessibilityReading {
    let snapshot: ComputerUseAXSnapshot
    let onRead: (() -> Void)?
    private(set) var lastWindow: ComputerUseWindow?

    init(
        snapshot: ComputerUseAXSnapshot = ComputerUseAXSnapshot(text: "", elements: [], wasTruncated: false),
        onRead: (() -> Void)? = nil
    ) {
        self.snapshot = snapshot
        self.onRead = onRead
    }

    func read(
        application: ComputerUseApplication,
        window: ComputerUseWindow,
        configuration: ComputerUseObservationConfiguration,
        shouldCancel: () -> Bool
    ) throws -> ComputerUseAXSnapshot {
        lastWindow = window
        onRead?()
        if shouldCancel() {
            throw ComputerUseObservationError.cancelled
        }
        return snapshot
    }
}

private final class StubScreenshotCapturer: ComputerUseScreenshotCapturing {
    let screenshot: ComputerUseScreenshot
    let error: Error?

    init(
        screenshot: ComputerUseScreenshot = ComputerUseScreenshot(data: Data(), mimeType: "image/png", width: 1, height: 1),
        error: Error? = nil
    ) {
        self.screenshot = screenshot
        self.error = error
    }

    func capture(window: ComputerUseWindow) throws -> ComputerUseScreenshot {
        if let error {
            throw error
        }
        return screenshot
    }
}

private final class StubPermissionManager: ComputerUsePermissionManaging {
    let permissionSnapshot: ComputerUsePermissionSnapshot

    init(snapshot: ComputerUsePermissionSnapshot) {
        permissionSnapshot = snapshot
    }

    func snapshot() -> ComputerUsePermissionSnapshot {
        permissionSnapshot
    }

    func requestAccessibility() -> Bool { false }
    func requestScreenRecording() -> Bool { false }
}
