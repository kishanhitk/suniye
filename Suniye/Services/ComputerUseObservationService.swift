import Foundation

final class ComputerUseObservationService: ComputerUseObservationServicing {
    private let applicationCatalog: ComputerUseApplicationCatalog
    private let windowDiscovery: ComputerUseWindowDiscovering
    private let accessibilityReader: ComputerUseAccessibilityReading
    private let screenshotCapturer: ComputerUseScreenshotCapturing
    private let permissionManager: ComputerUsePermissionManaging
    private let dateProvider: () -> Date
    private var nextGeneration: UInt64 = 0

    init(
        applicationCatalog: ComputerUseApplicationCatalog = SystemComputerUseApplicationCatalog(),
        windowDiscovery: ComputerUseWindowDiscovering = SystemComputerUseWindowDiscovery(),
        accessibilityReader: ComputerUseAccessibilityReading = SystemComputerUseAccessibilityReader(),
        screenshotCapturer: ComputerUseScreenshotCapturing = CoreGraphicsComputerUseScreenshotService(),
        permissionManager: ComputerUsePermissionManaging = SystemComputerUsePermissionService(),
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.applicationCatalog = applicationCatalog
        self.windowDiscovery = windowDiscovery
        self.accessibilityReader = accessibilityReader
        self.screenshotCapturer = screenshotCapturer
        self.permissionManager = permissionManager
        self.dateProvider = dateProvider
    }

    func observe(
        applicationID: String,
        includeScreenshot: Bool = true,
        configuration: ComputerUseObservationConfiguration = .default,
        cancellation: ComputerUseCancellationToken = ComputerUseCancellationToken()
    ) throws -> ComputerUseObservation {
        guard !cancellation.isCancelled else {
            throw ComputerUseObservationError.cancelled
        }

        guard let application = applicationCatalog.application(withID: applicationID) else {
            throw ComputerUseObservationError.applicationNotFound(applicationID)
        }
        guard application.isRunning else {
            throw ComputerUseObservationError.applicationNotRunning(applicationID)
        }

        let permissions = permissionManager.snapshot()
        guard permissions.canReadAccessibility else {
            throw ComputerUseObservationError.accessibilityNotTrusted
        }

        let windows = windowDiscovery.listWindows(for: application)
        let window: ComputerUseWindow
        if let preferredWindowID = configuration.preferredWindowID {
            guard let preferredWindow = windows.first(where: { $0.id == preferredWindowID }) else {
                throw ComputerUseObservationError.windowNotFound(preferredWindowID)
            }
            window = preferredWindow
        } else if let keyWindow = windows.first(where: \.isKeyWindow) {
            window = keyWindow
        } else if let firstWindow = windows.first {
            window = firstWindow
        } else {
            throw ComputerUseObservationError.noWindow(applicationID)
        }

        let accessibility = try accessibilityReader.read(
            application: application,
            window: window,
            configuration: configuration,
            shouldCancel: { cancellation.isCancelled }
        )
        guard !cancellation.isCancelled else {
            throw ComputerUseObservationError.cancelled
        }

        let screenshot: ComputerUseScreenshot?
        if includeScreenshot {
            guard permissions.canCaptureScreen else {
                throw ComputerUseObservationError.screenRecordingNotGranted
            }
            screenshot = try screenshotCapturer.capture(window: window)
        } else {
            screenshot = nil
        }

        guard !cancellation.isCancelled else {
            throw ComputerUseObservationError.cancelled
        }

        nextGeneration &+= 1
        return ComputerUseObservation(
            generation: nextGeneration,
            capturedAt: dateProvider(),
            target: ComputerUseTarget(application: application, window: window),
            accessibility: accessibility,
            screenshot: screenshot
        )
    }
}
