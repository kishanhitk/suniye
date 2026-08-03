import Foundation

actor ComputerUsePlatformRunner {
    private let applicationCatalog: ComputerUseApplicationCatalog
    private let permissionManager: ComputerUsePermissionManaging
    private let observationService: ComputerUseObservationServicing

    init(
        applicationCatalog: ComputerUseApplicationCatalog,
        permissionManager: ComputerUsePermissionManaging,
        observationService: ComputerUseObservationServicing
    ) {
        self.applicationCatalog = applicationCatalog
        self.permissionManager = permissionManager
        self.observationService = observationService
    }

    func listApplications() -> [ComputerUseApplication] {
        applicationCatalog.listApplications()
    }

    func permissionSnapshot() -> ComputerUsePermissionSnapshot {
        permissionManager.snapshot()
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
        cancellation: ComputerUseCancellationToken
    ) throws -> ComputerUseObservation {
        return try observationService.observe(
            applicationID: applicationID,
            configuration: .default,
            cancellation: cancellation
        )
    }

}
