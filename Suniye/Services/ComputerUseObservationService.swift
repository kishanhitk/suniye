import Foundation

protocol ComputerUseAccessibilitySnapshotProviding: Sendable {
    func snapshot(processIdentifier: Int32, windowOrdinal: Int) async throws
        -> ComputerUseAXSnapshot
}

protocol ComputerUseScreenshotCapturing: Sendable {
    func capture(windowID: UInt32) async throws -> ComputerUseCapturedScreenshot?
}

protocol ComputerUseObserving: Sendable {
    func observe(
        application: ComputerUseApplicationRecord,
        requestedIdentifier: String,
        disableDiff: Bool
    ) async throws -> ComputerUseObservation
}

struct ComputerUseCapturedScreenshot: Equatable, Sendable {
    let url: URL
    let pixelWidth: Int
    let pixelHeight: Int
    let coordinateScale: Double
    let windowFrame: CGRect
}

struct ComputerUseObservation: Equatable, Sendable {
    let target: ComputerUseObservedTarget
    let state: ComputerUseAppState
    let revision: ComputerUseAccessibilityRevision
    let screenshot: ComputerUseCapturedScreenshot?
}

struct ComputerUseObservedTarget: Equatable, Sendable {
    let application: ComputerUseApplicationRecord
    let window: ComputerUseWindow
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

actor ComputerUseObservationService: ComputerUseObserving {
    private let windows: ComputerUseWindowDiscovering
    private let accessibility: ComputerUseAccessibilitySnapshotProviding
    private let screenshots: ComputerUseScreenshotCapturing
    private let revisions: ComputerUseAccessibilityRevisionStore
    private let guidance: ComputerUseAppGuidanceProviding
    /// Apps whose guidance has already been injected this run, so the hint
    /// appears only on the first observation of each app.
    private var guidedApps: Set<String> = []

    init(
        windows: ComputerUseWindowDiscovering = ComputerUseWindowDiscovery(),
        accessibility: ComputerUseAccessibilitySnapshotProviding =
            SystemComputerUseAccessibilitySnapshotProvider(),
        screenshots: ComputerUseScreenshotCapturing = SystemComputerUseScreenshotCapturer(),
        revisions: ComputerUseAccessibilityRevisionStore = ComputerUseAccessibilityRevisionStore(),
        guidance: ComputerUseAppGuidanceProviding = ComputerUseAppGuidance()
    ) {
        self.windows = windows
        self.accessibility = accessibility
        self.screenshots = screenshots
        self.revisions = revisions
        self.guidance = guidance
    }

    func observe(
        application: ComputerUseApplicationRecord,
        requestedIdentifier: String,
        disableDiff: Bool
    ) async throws -> ComputerUseObservation {
        try Task.checkCancellation()
        guard let processIdentifier = application.processIdentifier else {
            throw ComputerUseObservationError.targetDidNotLaunch(requestedIdentifier)
        }
        let discoveredWindows = try await windows.orderedWindows(
            processIdentifier: processIdentifier
        )
        // Prefer the window the user is actually working in over raw
        // front-to-back CG ordering (panels and palettes can sit in front).
        let window = discoveredWindows.first(where: \.isFocused)
            ?? discoveredWindows.first(where: \.isMain)
            ?? discoveredWindows.first
        guard let window else {
            throw ComputerUseObservationError.noWindow(requestedIdentifier)
        }

        async let snapshot = accessibility.snapshot(
            processIdentifier: processIdentifier,
            windowOrdinal: window.accessibilityOrdinal
        )
        async let screenshot = screenshots.capture(windowID: window.id)
        let capturedSnapshot = try await snapshot
        let capturedScreenshot = try await screenshot
        try Task.checkCancellation()

        let targetKey = "\(application.identityKey)#\(window.id)"
        let revision = await revisions.revision(
            targetKey: targetKey,
            snapshot: capturedSnapshot,
            disableDiff: disableDiff
        )
        return ComputerUseObservation(
            target: ComputerUseObservedTarget(application: application, window: window),
            state: ComputerUseAppState(
                app: requestedIdentifier,
                screenshot: capturedScreenshot?.url,
                text: guidedText(revision.text, for: application)
            ),
            revision: revision,
            screenshot: capturedScreenshot
        )
    }

    /// Prepends the app's navigation hint to its first observation this run,
    /// tagged so the model can tell guidance from observed state. Later
    /// observations of the same app return the raw tree.
    private func guidedText(_ text: String, for application: ComputerUseApplicationRecord) -> String {
        guard guidedApps.insert(application.identityKey).inserted,
              let hint = guidance.instructions(
                  bundleIdentifier: application.bundleIdentifier,
                  displayName: application.displayName
              ) else {
            return text
        }
        return "<app_navigation_hint>\n\(hint)\n</app_navigation_hint>\n\(text)"
    }
}
