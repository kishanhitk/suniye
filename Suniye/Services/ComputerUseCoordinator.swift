import Foundation
import Observation

private actor ComputerUsePlatformRunner {
    private let applicationCatalog: ComputerUseApplicationCatalog
    private let permissionManager: ComputerUsePermissionManaging
    private let observationService: ComputerUseObservationServicing
    private let actionService: ComputerUseActionServicing

    init(
        applicationCatalog: ComputerUseApplicationCatalog,
        permissionManager: ComputerUsePermissionManaging,
        observationService: ComputerUseObservationServicing,
        actionService: ComputerUseActionServicing
    ) {
        self.applicationCatalog = applicationCatalog
        self.permissionManager = permissionManager
        self.observationService = observationService
        self.actionService = actionService
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

enum ComputerUseCoordinatorPhase: Equatable {
    case idle
    case loadingApplications
    case requestingPermission
    case ready
    case observing
    case observed
    case requestingApproval
    case acting
    case actionCompleted
    case actionFailed
    case failed
}

/// Main-actor state for the Phase 2 approved-action Computer Use surface.
///
/// Native discovery, observation, and action execution run through
/// `ComputerUsePlatformRunner` so platform work does not block SwiftUI rendering.
@MainActor
@Observable
final class ComputerUseCoordinator {
    private let runner: ComputerUsePlatformRunner

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
    var pendingApproval: ComputerUseApprovalRequest?
    var actionText = ""
    var lastActionResult: ComputerUseActionResult?

    @ObservationIgnored private var activeOperationID: UUID?
    @ObservationIgnored private var activeCancellation: ComputerUseCancellationToken?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var permissionTask: Task<Void, Never>?
    @ObservationIgnored private var observationTask: Task<Void, Never>?
    @ObservationIgnored private var actionTask: Task<Void, Never>?

    init(
        applicationCatalog: ComputerUseApplicationCatalog? = nil,
        permissionManager: ComputerUsePermissionManaging? = nil,
        observationService: ComputerUseObservationServicing? = nil,
        actionService: ComputerUseActionServicing? = nil
    ) {
        let resolvedCatalog = applicationCatalog ?? SystemComputerUseApplicationCatalog()
        let resolvedPermissionManager = permissionManager ?? SystemComputerUsePermissionService()
        let resolvedObservationService = observationService ?? ComputerUseObservationService(
            applicationCatalog: resolvedCatalog,
            permissionManager: resolvedPermissionManager
        )
        let resolvedActionService = actionService ?? ComputerUseActionService(
            permissionManager: resolvedPermissionManager
        )

        runner = ComputerUsePlatformRunner(
            applicationCatalog: resolvedCatalog,
            permissionManager: resolvedPermissionManager,
            observationService: resolvedObservationService,
            actionService: resolvedActionService
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
        case .loadingApplications, .requestingPermission, .observing, .requestingApproval, .acting:
            true
        case .idle, .ready, .observed, .actionCompleted, .actionFailed, .failed:
            false
        }
    }

    var canRequestAction: Bool {
        phase == .observed
            && observation != nil
            && permissionSnapshot.canReadAccessibility
    }

    var canObserve: Bool {
        guard let selectedApplicationID,
              !selectedApplicationID.isEmpty,
              !isBusy,
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
        case .requestingApproval:
            return "Approval required"
        case .acting:
            return "Performing approved action"
        case .actionCompleted:
            return "Action completed"
        case .actionFailed:
            return "Action failed"
        case .failed:
            return "Observation failed"
        }
    }

    func start() {
        refresh()
    }

    func refresh() {
        cancelActiveOperation()
        refreshTask?.cancel()
        permissionTask?.cancel()

        let operationID = UUID()
        activeOperationID = operationID
        phase = .loadingApplications
        errorMessage = nil
        observation = nil
        pendingApproval = nil
        lastActionResult = nil

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
        guard !isBusy else {
            return
        }

        guard applications.contains(where: { $0.id == identifier }) else {
            return
        }

        guard selectedApplicationID != identifier else {
            return
        }

        cancelActiveOperation()
        selectedApplicationID = identifier
        observation = nil
        errorMessage = nil
        pendingApproval = nil
        lastActionResult = nil
        phase = .ready
    }

    func observeSelectedApplication() {
        guard let selectedApplicationID, canObserve else {
            return
        }

        refreshTask?.cancel()
        permissionTask?.cancel()
        cancelActiveOperation()

        let operationID = UUID()
        let cancellation = ComputerUseCancellationToken()
        let captureScreenshot = includeScreenshot
        activeOperationID = operationID
        activeCancellation = cancellation
        phase = .observing
        observation = nil
        errorMessage = nil
        pendingApproval = nil
        lastActionResult = nil

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

    func requestAction(_ action: ComputerUseAction) {
        guard let observation, canRequestAction else {
            return
        }

        do {
            try ComputerUseActionPolicy.validate(action: action, observation: observation)
        } catch {
            phase = .actionFailed
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return
        }

        pendingApproval = ComputerUseApprovalRequest(
            id: UUID(),
            action: action,
            target: observation.target,
            risk: action.risk,
            reason: "Suniye will send this action to the selected app."
        )
        errorMessage = nil
        phase = .requestingApproval
    }

    func approvePendingAction() {
        guard let request = pendingApproval,
              let observation,
              phase == .requestingApproval else {
            return
        }

        let grant = ComputerUseApprovalGrant(
            requestID: request.id,
            scope: .once,
            applicationID: observation.target.application.id,
            windowID: observation.target.window.id,
            observationGeneration: observation.generation,
            action: request.action
        )
        let operationID = UUID()
        let cancellation = ComputerUseCancellationToken()
        let observationRunner = runner
        activeOperationID = operationID
        activeCancellation = cancellation
        pendingApproval = nil
        lastActionResult = nil
        errorMessage = nil
        phase = .acting

        actionTask = Task { [weak self] in
            do {
                let result = try await observationRunner.execute(
                    action: request.action,
                    observation: observation,
                    approval: grant,
                    requestID: request.id,
                    cancellation: cancellation
                )

                guard !Task.isCancelled else {
                    return
                }
                guard let self, self.activeOperationID == operationID else {
                    return
                }

                self.lastActionResult = result
                self.phase = .actionCompleted
                self.activeCancellation = nil
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                guard let self, self.activeOperationID == operationID else {
                    return
                }

                if let actionError = error as? ComputerUseActionError,
                   actionError == .cancelled {
                    self.phase = self.observation == nil ? .ready : .observed
                    self.activeCancellation = nil
                    return
                }

                self.phase = .actionFailed
                self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.activeCancellation = nil
            }
        }
    }

    func denyPendingAction() {
        pendingApproval = nil
        phase = observation == nil ? .ready : .observed
    }

    func stopPendingAction() {
        pendingApproval = nil
        cancel()
        observation = nil
        lastActionResult = nil
        errorMessage = nil
        phase = .ready
    }

    func cancel() {
        cancelActiveOperation()
        refreshTask?.cancel()
        permissionTask?.cancel()
        pendingApproval = nil

        if isBusy {
            phase = .ready
        }
    }

    private func requestPermission(
        _ request: @escaping (ComputerUsePlatformRunner) async -> Bool
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

    private func cancelActiveOperation() {
        activeCancellation?.cancel()
        observationTask?.cancel()
        actionTask?.cancel()
        activeCancellation = nil
        activeOperationID = nil
    }
}
