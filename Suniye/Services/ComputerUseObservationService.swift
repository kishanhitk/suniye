import Foundation

protocol ComputerUseAccessibilitySnapshotProviding: Sendable {
    func snapshot(processIdentifier: Int32, windowOrdinal: Int) async throws
        -> ComputerUseAXSnapshot
}

protocol ComputerUseScreenshotCapturing: Sendable {
    func capture(windowID: UInt32) async throws -> ComputerUseCapturedScreenshot?
}

struct ComputerUseCapturedScreenshot: Equatable, Sendable {
    let url: URL
    let pixelWidth: Int
    let pixelHeight: Int
    let scale: Double
    let windowFrame: CGRect
}

struct ComputerUseObservation: Equatable, Sendable {
    let state: ComputerUseAppState
    let revision: ComputerUseAccessibilityRevision
    let screenshot: ComputerUseCapturedScreenshot?
}

enum ComputerUseObservationError: LocalizedError, Equatable, Sendable {
    case targetDidNotLaunch(String)
    case noWindow(String)

    var errorDescription: String? {
        switch self {
        case let .targetDidNotLaunch(app):
            "The target application did not finish launching: \(app)."
        case let .noWindow(app):
            "The target application has no observable window: \(app)."
        }
    }
}

actor ComputerUseObservationService {
    private let applications: ComputerUseApplicationCatalogProviding
    private let windows: ComputerUseWindowDiscovering
    private let accessibility: ComputerUseAccessibilitySnapshotProviding
    private let screenshots: ComputerUseScreenshotCapturing
    private let revisions: ComputerUseAccessibilityRevisionStore

    init(
        applications: ComputerUseApplicationCatalogProviding = ComputerUseApplicationCatalog(),
        windows: ComputerUseWindowDiscovering = ComputerUseWindowDiscovery(),
        accessibility: ComputerUseAccessibilitySnapshotProviding =
            SystemComputerUseAccessibilitySnapshotProvider(),
        screenshots: ComputerUseScreenshotCapturing = SystemComputerUseScreenshotCapturer(),
        revisions: ComputerUseAccessibilityRevisionStore = ComputerUseAccessibilityRevisionStore()
    ) {
        self.applications = applications
        self.windows = windows
        self.accessibility = accessibility
        self.screenshots = screenshots
        self.revisions = revisions
    }

    func observe(app: String, disableDiff: Bool) async throws -> ComputerUseObservation {
        try Task.checkCancellation()
        let application = try await applications.resolveOrLaunch(app)
        guard let processIdentifier = application.processIdentifier else {
            throw ComputerUseObservationError.targetDidNotLaunch(app)
        }
        let discoveredWindows = try await windows.orderedWindows(
            processIdentifier: processIdentifier
        )
        guard let window = discoveredWindows.first else {
            throw ComputerUseObservationError.noWindow(app)
        }

        async let snapshot = accessibility.snapshot(
            processIdentifier: processIdentifier,
            windowOrdinal: window.accessibilityOrdinal
        )
        async let screenshot = screenshots.capture(windowID: window.id)
        let capturedSnapshot = try await snapshot
        let capturedScreenshot = try await screenshot
        try Task.checkCancellation()

        let applicationKey = application.bundleIdentifier
            ?? application.applicationURL.standardizedFileURL.path
        let targetKey = "\(applicationKey)#\(window.id)"
        let revision = await revisions.revision(
            targetKey: targetKey,
            snapshot: capturedSnapshot,
            disableDiff: disableDiff
        )
        return ComputerUseObservation(
            state: ComputerUseAppState(
                app: app,
                screenshot: capturedScreenshot?.url,
                text: revision.text
            ),
            revision: revision,
            screenshot: capturedScreenshot
        )
    }
}
