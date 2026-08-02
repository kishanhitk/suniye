import Foundation

actor ComputerUsePlatformRunner {
    private let applicationCatalog: ComputerUseApplicationCatalog
    private let windowDiscovery: ComputerUseWindowDiscovering
    private let windowActivator: ComputerUseWindowActivating
    private let permissionManager: ComputerUsePermissionManaging
    private let approvalStore: ComputerUseApprovalStoring
    private let observationService: ComputerUseObservationServicing
    private let actionService: ComputerUseActionServicing

    init(
        applicationCatalog: ComputerUseApplicationCatalog,
        windowDiscovery: ComputerUseWindowDiscovering,
        windowActivator: ComputerUseWindowActivating,
        permissionManager: ComputerUsePermissionManaging,
        approvalStore: ComputerUseApprovalStoring,
        observationService: ComputerUseObservationServicing,
        actionService: ComputerUseActionServicing
    ) {
        self.applicationCatalog = applicationCatalog
        self.windowDiscovery = windowDiscovery
        self.windowActivator = windowActivator
        self.permissionManager = permissionManager
        self.approvalStore = approvalStore
        self.observationService = observationService
        self.actionService = actionService
    }

    func listApplications() -> [ComputerUseApplication] {
        applicationCatalog.listApplications()
    }

    func permissionSnapshot() -> ComputerUsePermissionSnapshot {
        permissionManager.snapshot()
    }

    func listAlwaysApprovals() -> [ComputerUseApprovalRecord] {
        approvalStore.listAlwaysApprovals(now: Date())
    }

    func revokeAlwaysApproval(_ record: ComputerUseApprovalRecord) {
        approvalStore.revoke(
            applicationBundleIdentifier: record.applicationBundleIdentifier,
            risk: record.risk
        )
    }

    func listWindows(applicationID: String) -> [ComputerUseWindow] {
        guard let application = applicationCatalog.application(withID: applicationID) else {
            return []
        }
        return windowDiscovery.listWindows(for: application)
    }

    func activateWindow(applicationID: String, windowID: UInt32) -> Bool {
        guard let application = applicationCatalog.application(withID: applicationID),
              let window = windowDiscovery.listWindows(for: application)
                  .first(where: { $0.id == windowID }) else {
            return false
        }
        return windowActivator.activate(
            target: ComputerUseTarget(application: application, window: window)
        )
    }

    @discardableResult
    func requestAccessibility() -> Bool {
        permissionManager.requestAccessibility()
    }

    @discardableResult
    func requestScreenRecording() -> Bool {
        permissionManager.requestScreenRecording()
    }

    func observe(
        applicationID: String,
        windowID: UInt32?,
        includeScreenshot: Bool,
        cancellation: ComputerUseCancellationToken
    ) throws -> ComputerUseObservation {
        var configuration = ComputerUseObservationConfiguration.default
        configuration.preferredWindowID = windowID
        return try observationService.observe(
            applicationID: applicationID,
            includeScreenshot: includeScreenshot,
            configuration: configuration,
            cancellation: cancellation
        )
    }

    func execute(
        action: ComputerUseAction,
        observation: ComputerUseObservation,
        approval: ComputerUseApprovalGrant,
        requestID: UUID,
        cancellation: ComputerUseCancellationToken
    ) throws -> ComputerUseActionResult {
        try actionService.execute(
            action: action,
            observation: observation,
            approval: approval,
            requestID: requestID,
            cancellation: cancellation
        )
    }
}
