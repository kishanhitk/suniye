import Foundation

private let computerUseLaunchWindowPollIntervalNanoseconds: UInt64 = 100_000_000
private let computerUseLaunchWindowPollAttempts = 20

final class ComputerUseObservationService: ComputerUseObservationServicing {
    private let applicationCatalog: ComputerUseApplicationCatalog
    private let windowDiscovery: ComputerUseWindowDiscovering
    private let windowActivator: ComputerUseWindowActivating
    private let accessibilityReader: ComputerUseAccessibilityReading
    private let screenshotCapturer: ComputerUseScreenshotCapturing
    private let permissionManager: ComputerUsePermissionManaging
    private let dateProvider: () -> Date
    private let launchWindowPollIntervalNanoseconds: UInt64
    private let launchWindowPollAttempts: Int
    private var nextGeneration: UInt64 = 0

    init(
        applicationCatalog: ComputerUseApplicationCatalog = SystemComputerUseApplicationCatalog(),
        windowDiscovery: ComputerUseWindowDiscovering = SystemComputerUseWindowDiscovery(),
        windowActivator: ComputerUseWindowActivating = SystemComputerUseWindowActivator(),
        accessibilityReader: ComputerUseAccessibilityReading = SystemComputerUseAccessibilityReader(),
        screenshotCapturer: ComputerUseScreenshotCapturing = CoreGraphicsComputerUseScreenshotService(),
        permissionManager: ComputerUsePermissionManaging = SystemComputerUsePermissionService(),
        dateProvider: @escaping () -> Date = Date.init,
        launchWindowPollIntervalNanoseconds: UInt64 = computerUseLaunchWindowPollIntervalNanoseconds,
        launchWindowPollAttempts: Int = computerUseLaunchWindowPollAttempts
    ) {
        self.applicationCatalog = applicationCatalog
        self.windowDiscovery = windowDiscovery
        self.windowActivator = windowActivator
        self.accessibilityReader = accessibilityReader
        self.screenshotCapturer = screenshotCapturer
        self.permissionManager = permissionManager
        self.dateProvider = dateProvider
        self.launchWindowPollIntervalNanoseconds = launchWindowPollIntervalNanoseconds
        self.launchWindowPollAttempts = max(1, launchWindowPollAttempts)
    }

    func observe(
        applicationID: String,
        configuration: ComputerUseObservationConfiguration = .default,
        cancellation: ComputerUseCancellationToken = ComputerUseCancellationToken()
    ) throws -> ComputerUseObservation {
        guard let application = applicationCatalog.application(withID: applicationID) else {
            throw ComputerUseObservationError.applicationNotFound(applicationID)
        }
        return try observe(
            application: application,
            configuration: configuration,
            cancellation: cancellation
        )
    }

    func observeTarget(
        applicationIdentifier: String?,
        configuration: ComputerUseObservationConfiguration,
        cancellation: ComputerUseCancellationToken
    ) async throws -> ComputerUseObservation {
        guard !cancellation.isCancelled else {
            throw ComputerUseObservationError.cancelled
        }

        let application: ComputerUseApplication
        var wasLaunched = false
        if let applicationIdentifier {
            if let resolvedApplication = applicationCatalog.resolveApplication(
                identifier: applicationIdentifier
            ) {
                if resolvedApplication.isRunning {
                    application = resolvedApplication
                } else if let launchedApplication = await applicationCatalog.launchApplication(
                    identifier: applicationIdentifier
                ) {
                    application = launchedApplication
                    wasLaunched = true
                } else {
                    throw ComputerUseObservationError.applicationNotRunning(applicationIdentifier)
                }
            } else if let launchedApplication = await applicationCatalog.launchApplication(
                identifier: applicationIdentifier
            ) {
                application = launchedApplication
                wasLaunched = true
            } else {
                throw ComputerUseObservationError.applicationNotFound(applicationIdentifier)
            }
        } else if let activeApplication = applicationCatalog.activeApplication() {
            application = activeApplication
        } else {
            throw ComputerUseObservationError.applicationNotFound("frontmost application")
        }

        if wasLaunched {
            try await waitForVisibleWindow(application: application, cancellation: cancellation)
        }

        return try observe(
            application: application,
            configuration: configuration,
            cancellation: cancellation
        )
    }

    private func waitForVisibleWindow(
        application: ComputerUseApplication,
        cancellation: ComputerUseCancellationToken
    ) async throws {
        for attempt in 0..<launchWindowPollAttempts {
            guard !Task.isCancelled, !cancellation.isCancelled else {
                throw ComputerUseObservationError.cancelled
            }

            if !windowDiscovery.listWindows(for: application).isEmpty {
                return
            }

            guard attempt + 1 < launchWindowPollAttempts else {
                throw ComputerUseObservationError.noWindow(application.id)
            }

            do {
                try await Task.sleep(nanoseconds: launchWindowPollIntervalNanoseconds)
            } catch is CancellationError {
                throw ComputerUseObservationError.cancelled
            }
        }
    }

    private func observe(
        application: ComputerUseApplication,
        configuration: ComputerUseObservationConfiguration,
        cancellation: ComputerUseCancellationToken
    ) throws -> ComputerUseObservation {
        guard application.isRunning else {
            throw ComputerUseObservationError.applicationNotRunning(application.bundleIdentifier)
        }

        let permissions = permissionManager.snapshot()
        guard permissions.canReadAccessibility else {
            throw ComputerUseObservationError.accessibilityNotTrusted
        }

        let windows = windowDiscovery.listWindows(for: application)
        let window: ComputerUseWindow
        if let keyWindow = windows.first(where: \.isKeyWindow) {
            window = keyWindow
        } else if let firstWindow = windows.first {
            window = firstWindow
        } else {
            throw ComputerUseObservationError.noWindow(application.id)
        }

        if configuration.activateTarget {
            let target = ComputerUseTarget(application: application, window: window)
            guard windowActivator.activate(target: target) else {
                throw ComputerUseObservationError.targetActivationFailed(application.bundleIdentifier)
            }
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

        guard permissions.canCaptureScreen else {
            throw ComputerUseObservationError.screenRecordingNotGranted
        }
        let screenshot = try screenshotCapturer.capture(window: window)

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
