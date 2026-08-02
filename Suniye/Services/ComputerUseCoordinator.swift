import Foundation
import Observation

private actor ComputerUseObservationRunner {
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
        includeScreenshot: Bool,
        cancellation: ComputerUseCancellationToken
    ) throws -> ComputerUseObservation {
        try observationService.observe(
            applicationID: applicationID,
            includeScreenshot: includeScreenshot,
            configuration: .default,
            cancellation: cancellation
        )
    }
}

enum ComputerUseCoordinatorPhase: Equatable {
    case idle
    case loadingApplications
    case requestingPermission
    case ready
    case observing
    case observed
    case failed
}

/// Main-actor state for the Phase 1 read-only Computer Use surface.
///
/// Native discovery and observation run through `ComputerUseObservationRunner`
/// so Accessibility and WindowServer work does not block SwiftUI rendering.
@MainActor
@Observable
final class ComputerUseCoordinator {
    private let runner: ComputerUseObservationRunner

    var phase: ComputerUseCoordinatorPhase = .idle
    var applications: [ComputerUseApplication] = []
    var selectedApplicationID: String?
    var permissionSnapshot = ComputerUsePermissionSnapshot(
        accessibility: .notGranted,
        screenRecording: .notGranted
    )
    var observation: ComputerUseObservation?
    var errorMessage: String?
    var includeScreenshot = true

    @ObservationIgnored private var activeOperationID: UUID?
    @ObservationIgnored private var activeCancellation: ComputerUseCancellationToken?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var permissionTask: Task<Void, Never>?
    @ObservationIgnored private var observationTask: Task<Void, Never>?

    init(
        applicationCatalog: ComputerUseApplicationCatalog? = nil,
        permissionManager: ComputerUsePermissionManaging? = nil,
        observationService: ComputerUseObservationServicing? = nil
    ) {
        let resolvedCatalog = applicationCatalog ?? SystemComputerUseApplicationCatalog()
        let resolvedPermissionManager = permissionManager ?? SystemComputerUsePermissionService()
        let resolvedObservationService = observationService ?? ComputerUseObservationService(
            applicationCatalog: resolvedCatalog,
            permissionManager: resolvedPermissionManager
        )

        runner = ComputerUseObservationRunner(
            applicationCatalog: resolvedCatalog,
            permissionManager: resolvedPermissionManager,
            observationService: resolvedObservationService
        )
    }

    var applicationIDs: [String] {
        applications.map(\.id)
    }

    var selectedApplication: ComputerUseApplication? {
        guard let selectedApplicationID else {
            return nil
        }
        return applications.first { $0.id == selectedApplicationID }
    }

    var isBusy: Bool {
        switch phase {
        case .loadingApplications, .requestingPermission, .observing:
            true
        case .idle, .ready, .observed, .failed:
            false
        }
    }

    var canObserve: Bool {
        guard let selectedApplicationID,
              !selectedApplicationID.isEmpty,
              permissionSnapshot.canReadAccessibility else {
            return false
        }

        return !includeScreenshot || permissionSnapshot.canCaptureScreen
    }

    var phaseTitle: String {
        switch phase {
        case .idle:
            return "Ready to inspect"
        case .loadingApplications:
            return "Finding running apps"
        case .requestingPermission:
            return "Waiting for permission"
        case .ready:
            return "Ready to inspect"
        case .observing:
            return "Reading app state"
        case .observed:
            return "Observation captured"
        case .failed:
            return "Observation failed"
        }
    }

    func start() {
        refresh()
    }

    func refresh() {
        cancelActiveObservation()
        refreshTask?.cancel()
        permissionTask?.cancel()

        let operationID = UUID()
        activeOperationID = operationID
        phase = .loadingApplications
        errorMessage = nil

        let observationRunner = runner
        refreshTask = Task { [weak self] in
            async let applications = observationRunner.listApplications()
            async let permissions = observationRunner.permissionSnapshot()
            let (loadedApplications, loadedPermissions) = await (applications, permissions)

            guard !Task.isCancelled else {
                return
            }

            guard let self, self.activeOperationID == operationID else {
                return
            }

            self.applications = loadedApplications
            self.permissionSnapshot = loadedPermissions
            self.reconcileSelection()
            self.phase = .ready
        }
    }

    func refreshPermissions() {
        permissionTask?.cancel()
        let operationID = UUID()
        activeOperationID = operationID
        let observationRunner = runner
        permissionTask = Task { [weak self] in
            let permissions = await observationRunner.permissionSnapshot()
            guard !Task.isCancelled else {
                return
            }

            guard let self, self.activeOperationID == operationID else {
                return
            }

            self.permissionSnapshot = permissions
        }
    }

    func requestAccessibility() {
        guard !isBusy else {
            return
        }
        requestPermission { runner in
            await runner.requestAccessibility()
        }
    }

    func requestScreenRecording() {
        guard !isBusy else {
            return
        }
        requestPermission { runner in
            await runner.requestScreenRecording()
        }
    }

    func selectApplication(_ identifier: String) {
        guard applications.contains(where: { $0.id == identifier }) else {
            return
        }

        guard selectedApplicationID != identifier else {
            return
        }

        cancelActiveObservation()
        selectedApplicationID = identifier
        observation = nil
        errorMessage = nil
        phase = .ready
    }

    func observeSelectedApplication() {
        guard let selectedApplicationID, canObserve else {
            return
        }

        refreshTask?.cancel()
        permissionTask?.cancel()
        cancelActiveObservation()

        let operationID = UUID()
        let cancellation = ComputerUseCancellationToken()
        let captureScreenshot = includeScreenshot
        activeOperationID = operationID
        activeCancellation = cancellation
        phase = .observing
        observation = nil
        errorMessage = nil

        let observationRunner = runner
        observationTask = Task { [weak self] in
            do {
                let result = try await observationRunner.observe(
                    applicationID: selectedApplicationID,
                    includeScreenshot: captureScreenshot,
                    cancellation: cancellation
                )

                guard !Task.isCancelled else {
                    return
                }

                guard let self, self.activeOperationID == operationID else {
                    return
                }

                self.observation = result
                self.phase = .observed
                self.activeCancellation = nil
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                guard let self, self.activeOperationID == operationID else {
                    return
                }

                if let observationError = error as? ComputerUseObservationError,
                   observationError == .cancelled {
                    self.phase = .ready
                    self.activeCancellation = nil
                    return
                }

                self.phase = .failed
                self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.activeCancellation = nil
            }
        }
    }

    func cancel() {
        cancelActiveObservation()
        refreshTask?.cancel()
        permissionTask?.cancel()

        if isBusy {
            phase = .ready
        }
    }

    private func requestPermission(
        _ request: @escaping (ComputerUseObservationRunner) async -> Bool
    ) {
        permissionTask?.cancel()
        let observationRunner = runner
        let operationID = UUID()
        activeOperationID = operationID
        phase = .requestingPermission
        errorMessage = nil

        permissionTask = Task { [weak self] in
            _ = await request(observationRunner)
            let permissions = await observationRunner.permissionSnapshot()

            guard !Task.isCancelled else {
                return
            }

            guard let self, self.activeOperationID == operationID else {
                return
            }

            self.permissionSnapshot = permissions
            self.phase = .ready
        }
    }

    private func reconcileSelection() {
        if let selectedApplicationID,
           applications.contains(where: { $0.id == selectedApplicationID }) {
            return
        }

        selectedApplicationID = applications.first?.id
        observation = nil
    }

    private func cancelActiveObservation() {
        activeCancellation?.cancel()
        observationTask?.cancel()
        activeCancellation = nil
        activeOperationID = nil
    }
}
