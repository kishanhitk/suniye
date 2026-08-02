import Foundation
import Observation

enum ComputerUseCoordinatorPhase: Equatable {
    case idle
    case loadingApplications
    case requestingPermission
    case activatingWindow
    case ready
    case observing
    case runningAgent
    case observed
    case requestingApproval
    case acting
    case actionCompleted
    case agentCompleted
    case actionFailed
    case failed
}

/// Main-actor state for the Phase 2 approved-action Computer Use surface.
///
/// Native discovery, observation, and action execution run through
/// `ComputerUsePlatformRunner` so platform work does not block SwiftUI rendering.
@MainActor
@Observable
final class ComputerUseCoordinator: ComputerUseApprovalRequesting {
    private let runner: ComputerUsePlatformRunner
    private let observationService: ComputerUseObservationServicing
    private let actionService: ComputerUseActionServicing
    private let interventionMonitor: ComputerUseInterventionMonitoring
    private let approvalPolicyService: ComputerUseApprovalPolicyService
    private let approvalAuthorizer: ComputerUseApprovalAuthorizing
    private let sessionID: UUID
    private let agentLimits: ComputerUseAgentLimits
    private var modelClient: ComputerUseModelClient?

    var phase: ComputerUseCoordinatorPhase = .idle
    var applications: [ComputerUseApplication] = []
    var selectedApplicationID: String?
    var windows: [ComputerUseWindow] = []
    var selectedWindowID: UInt32?
    var alwaysApprovals: [ComputerUseApprovalRecord] = []
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
    var agentInstruction = ""
    var agentResult: ComputerUseAgentResult?
    var allowRemoteScreenshotUpload = false

    @ObservationIgnored private var activeOperationID: UUID?
    @ObservationIgnored private var activeCancellation: ComputerUseCancellationToken?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var permissionTask: Task<Void, Never>?
    @ObservationIgnored private var alwaysApprovalTask: Task<Void, Never>?
    @ObservationIgnored private var windowTask: Task<Void, Never>?
    @ObservationIgnored private var observationTask: Task<Void, Never>?
    @ObservationIgnored private var actionTask: Task<Void, Never>?
    @ObservationIgnored private var agentTask: Task<Void, Never>?
    @ObservationIgnored private var remoteModelConfiguration: ComputerUseRemoteModelConfiguration?
    @ObservationIgnored private lazy var agent: ComputerUseAgent = makeAgent(
        modelClient: modelClient,
        limits: agentLimits
    )
    @ObservationIgnored private var agentApprovalContinuations: [UUID: CheckedContinuation<ComputerUseApprovalDecision, Never>] = [:]

    init(
        applicationCatalog: ComputerUseApplicationCatalog? = nil,
        windowDiscovery: ComputerUseWindowDiscovering? = nil,
        windowActivator: ComputerUseWindowActivating? = nil,
        permissionManager: ComputerUsePermissionManaging? = nil,
        observationService: ComputerUseObservationServicing? = nil,
        actionService: ComputerUseActionServicing? = nil,
        approvalStore: ComputerUseApprovalStoring? = nil,
        policy: ComputerUsePolicyChecking? = nil,
        auditRecorder: ComputerUseAuditRecording? = nil,
        modelClient: ComputerUseModelClient? = nil,
        interventionMonitor: ComputerUseInterventionMonitoring? = nil,
        agentLimits: ComputerUseAgentLimits = ComputerUseAgentLimits()
    ) {
        let resolvedCatalog = applicationCatalog ?? SystemComputerUseApplicationCatalog()
        let resolvedWindowDiscovery = windowDiscovery ?? SystemComputerUseWindowDiscovery()
        let resolvedWindowActivator = windowActivator ?? SystemComputerUseWindowActivator()
        let resolvedPermissionManager = permissionManager ?? SystemComputerUsePermissionService()
        let resolvedApprovalStore = approvalStore ?? ComputerUseApprovalStore()
        let resolvedPolicy = policy ?? ComputerUsePolicyService()
        let resolvedAuditRecorder = auditRecorder ?? AppLoggerComputerUseAuditRecorder()
        approvalPolicyService = ComputerUseApprovalPolicyService(
            policy: resolvedPolicy,
            store: resolvedApprovalStore,
            auditRecorder: resolvedAuditRecorder
        )
        approvalAuthorizer = ComputerUseApprovalPolicyActor(
            policyService: ComputerUseApprovalPolicyService(
                policy: resolvedPolicy,
                store: resolvedApprovalStore,
                auditRecorder: resolvedAuditRecorder
            )
        )
        sessionID = UUID()
        self.agentLimits = agentLimits
        let resolvedObservationService = observationService ?? ComputerUseObservationService(
            applicationCatalog: resolvedCatalog,
            permissionManager: resolvedPermissionManager
        )
        let resolvedActionService = actionService ?? ComputerUseActionService(
            permissionManager: resolvedPermissionManager,
            approvalStore: resolvedApprovalStore,
            policy: resolvedPolicy
        )
        self.observationService = resolvedObservationService
        self.actionService = resolvedActionService
        self.interventionMonitor = interventionMonitor ?? SystemComputerUseInterventionMonitor()
        self.modelClient = modelClient

        runner = ComputerUsePlatformRunner(
            applicationCatalog: resolvedCatalog,
            windowDiscovery: resolvedWindowDiscovery,
            windowActivator: resolvedWindowActivator,
            permissionManager: resolvedPermissionManager,
            approvalStore: resolvedApprovalStore,
            observationService: resolvedObservationService,
            actionService: resolvedActionService
        )
    }

    var applicationIDs: [String] {
        applications.map(\.id)
    }

    var windowIDs: [UInt32] {
        windows.map(\.id)
    }

    var selectedApplication: ComputerUseApplication? {
        guard let selectedApplicationID else {
            return nil
        }
        return applications.first { $0.id == selectedApplicationID }
    }

    var selectedWindow: ComputerUseWindow? {
        guard let selectedWindowID else {
            return nil
        }
        return windows.first { $0.id == selectedWindowID }
    }

    var isBusy: Bool {
        switch phase {
        case .loadingApplications, .requestingPermission, .activatingWindow, .observing, .requestingApproval, .acting:
            true
        case .runningAgent:
            true
        case .idle, .ready, .observed, .actionCompleted, .agentCompleted, .actionFailed, .failed:
            false
        }
    }

    var canRunAgent: Bool {
        guard let selectedApplicationID,
              !selectedApplicationID.isEmpty,
              !isBusy,
              isModelConfigured,
              permissionSnapshot.canReadAccessibility else {
            return false
        }
        return !includeScreenshot || permissionSnapshot.canCaptureScreen
    }

    var isModelConfigured: Bool {
        guard modelClient != nil else {
            return false
        }
        return remoteModelConfiguration?.validationMessage == nil
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
        case .activatingWindow:
            return "Bringing window forward"
        case .ready:
            return "Ready to inspect"
        case .observing:
            return "Reading app state"
        case .runningAgent:
            return "Computer Use is working"
        case .observed:
            return "Observation captured"
        case .requestingApproval:
            return "Approval required"
        case .acting:
            return "Performing approved action"
        case .actionCompleted:
            return "Action completed"
        case .agentCompleted:
            return "Computer Use finished"
        case .actionFailed:
            return "Action failed"
        case .failed:
            return "Observation failed"
        }
    }

    func start() {
        refresh()
    }

    func configureModel(_ modelClient: ComputerUseModelClient?) {
        guard !isBusy else {
            return
        }
        remoteModelConfiguration = nil
        self.modelClient = modelClient
        agent = makeAgent(modelClient: modelClient, limits: agentLimits)
    }

    func configureRemoteModel(_ configuration: ComputerUseRemoteModelConfiguration?) {
        guard !isBusy else {
            return
        }
        remoteModelConfiguration = configuration
        modelClient = configuration.map { makeRemoteModelClient(configuration: $0) }
        agent = makeAgent(modelClient: modelClient, limits: agentLimits)
    }

    func setRemoteScreenshotUploadAllowed(_ allowed: Bool) {
        guard !isBusy else {
            return
        }
        allowRemoteScreenshotUpload = allowed
        guard let remoteModelConfiguration else {
            return
        }
        modelClient = makeRemoteModelClient(configuration: remoteModelConfiguration)
        agent = makeAgent(modelClient: modelClient, limits: agentLimits)
    }

    func startAgent() {
        let instruction = agentInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else {
            phase = .actionFailed
            errorMessage = "Enter a task for Computer Use."
            return
        }
        guard canRunAgent,
              let selectedApplicationID else {
            return
        }

        cancelActiveOperation()
        let operationID = UUID()
        let cancellation = ComputerUseCancellationToken()
        let agent = self.agent
        let selectedWindowID = self.selectedWindowID
        let task = ComputerUseAgentTask(
            instruction: instruction,
            applicationID: selectedApplicationID,
            windowID: selectedWindowID,
            includeScreenshot: includeScreenshot,
            sessionID: sessionID
        )
        activeOperationID = operationID
        activeCancellation = cancellation
        observation = nil
        pendingApproval = nil
        agentResult = nil
        lastActionResult = nil
        errorMessage = nil
        phase = .runningAgent

        let observationRunner = runner
        agentTask = Task { [weak self] in
            if let selectedWindowID {
                let activated = await observationRunner.activateWindow(
                    applicationID: selectedApplicationID,
                    windowID: selectedWindowID
                )
                guard activated, !Task.isCancelled else {
                    guard !Task.isCancelled,
                          let self,
                          self.activeOperationID == operationID else {
                        return
                    }
                    self.phase = .failed
                    self.errorMessage = "The selected window could not be brought to the front."
                    self.activeCancellation = nil
                    return
                }
            }

            let result = await agent.run(task: task, cancellation: cancellation)
            guard !Task.isCancelled else {
                return
            }
            guard let self, self.activeOperationID == operationID else {
                return
            }
            self.applyAgentResult(result)
        }
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
            async let approvals = observationRunner.listAlwaysApprovals()
            let (loadedApplications, loadedPermissions, loadedApprovals) = await (
                applications,
                permissions,
                approvals
            )

            guard !Task.isCancelled else {
                return
            }

            guard let self, self.activeOperationID == operationID else {
                return
            }

            self.applications = loadedApplications
            self.permissionSnapshot = loadedPermissions
            self.alwaysApprovals = loadedApprovals
            self.reconcileSelection()
            if let selectedApplicationID = self.selectedApplicationID {
                self.windows = await observationRunner.listWindows(applicationID: selectedApplicationID)
            } else {
                self.windows = []
            }
            self.reconcileWindowSelection()
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

    func refreshAlwaysApprovals() {
        alwaysApprovalTask?.cancel()
        let observationRunner = runner
        alwaysApprovalTask = Task { [weak self] in
            let approvals = await observationRunner.listAlwaysApprovals()
            guard !Task.isCancelled else {
                return
            }
            self?.alwaysApprovals = approvals
        }
    }

    func revokeAlwaysApproval(_ record: ComputerUseApprovalRecord) {
        guard !isBusy else {
            return
        }
        let observationRunner = runner
        Task { [weak self] in
            await observationRunner.revokeAlwaysApproval(record)
            guard !Task.isCancelled else {
                return
            }
            self?.refreshAlwaysApprovals()
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
        selectedWindowID = nil
        windows = []
        observation = nil
        errorMessage = nil
        pendingApproval = nil
        lastActionResult = nil
        phase = .ready
        loadWindows(for: identifier)
    }

    func selectWindow(_ identifier: UInt32) {
        guard !isBusy,
              windows.contains(where: { $0.id == identifier }) else {
            return
        }
        guard selectedWindowID != identifier else {
            return
        }

        cancelActiveOperation()
        selectedWindowID = identifier
        observation = nil
        errorMessage = nil
        pendingApproval = nil
        lastActionResult = nil
        phase = .ready
    }

    func activateSelectedWindow() {
        guard !isBusy,
              let selectedApplicationID,
              let selectedWindowID else {
            return
        }

        windowTask?.cancel()
        let operationID = UUID()
        activeOperationID = operationID
        phase = .activatingWindow
        errorMessage = nil

        let observationRunner = runner
        windowTask = Task { [weak self] in
            let activated = await observationRunner.activateWindow(
                applicationID: selectedApplicationID,
                windowID: selectedWindowID
            )
            guard !Task.isCancelled else {
                return
            }
            guard let self,
                  self.activeOperationID == operationID else {
                return
            }
            guard activated else {
                self.phase = .failed
                self.errorMessage = "The selected window could not be brought to the front."
                return
            }

            self.windows = await observationRunner.listWindows(applicationID: selectedApplicationID)
            self.reconcileWindowSelection()
            self.phase = .ready
        }
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
        let selectedWindowID = self.selectedWindowID
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
                    windowID: selectedWindowID,
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

        let request = ComputerUseApprovalRequest(
            id: UUID(),
            action: action,
            target: observation.target,
            risk: action.risk,
            reason: "Suniye will send this action to the selected app.",
            sessionID: sessionID,
            observationGeneration: observation.generation
        )
        do {
            pendingApproval = try approvalPolicyService.prepare(request)
        } catch {
            pendingApproval = nil
            phase = .actionFailed
            errorMessage = localizedMessage(error)
            return
        }
        errorMessage = nil
        phase = .requestingApproval
    }

    func requestApproval(
        _ request: ComputerUseApprovalRequest,
        cancellation: ComputerUseCancellationToken
    ) async -> ComputerUseApprovalDecision {
        guard !cancellation.isCancelled, !Task.isCancelled else {
            return .stopSession
        }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !cancellation.isCancelled else {
                    continuation.resume(returning: .stopSession)
                    return
                }
                agentApprovalContinuations[request.id] = continuation
                pendingApproval = request
                errorMessage = nil
                phase = .requestingApproval
            }
        } onCancel: { [weak self] in
            cancellation.cancel()
            Task { @MainActor [weak self] in
                self?.resolveAgentApproval(
                    requestID: request.id,
                    decision: .stopSession
                )
            }
        }
    }

    func approvePendingAction() {
        approvePendingAction(scope: .once)
    }

    func approvePendingAction(scope: ComputerUseApprovalScope) {
        guard let request = pendingApproval,
              phase == .requestingApproval else {
            return
        }

        if agentApprovalContinuations[request.id] != nil {
            guard request.allowedScopes.contains(scope) else {
                errorMessage = ComputerUsePolicyError.approvalScopeNotAllowed.localizedDescription
                return
            }
            _ = resolveAgentApproval(
                requestID: request.id,
                decision: decision(for: scope)
            )
            return
        }

        guard let observation else {
            return
        }

        let grant: ComputerUseApprovalGrant
        do {
            grant = try approvalPolicyService.grant(for: request, scope: scope)
        } catch {
            phase = .actionFailed
            errorMessage = localizedMessage(error)
            return
        }
        let refreshApprovalsAfterAction = scope == .always
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
                if refreshApprovalsAfterAction {
                    self?.refreshAlwaysApprovals()
                }

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
                if refreshApprovalsAfterAction {
                    self?.refreshAlwaysApprovals()
                }
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
        if let pendingApproval {
            approvalPolicyService.recordDenied(for: pendingApproval)
            if resolveAgentApproval(requestID: pendingApproval.id, decision: .deny) {
                return
            }
        }
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
        resolveAllAgentApprovals(with: .stopSession)
        cancelActiveOperation()
        refreshTask?.cancel()
        permissionTask?.cancel()
        alwaysApprovalTask?.cancel()
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
        windows = []
        selectedWindowID = nil
        observation = nil
    }

    private func loadWindows(for applicationID: String) {
        windowTask?.cancel()
        let observationRunner = runner
        windowTask = Task { [weak self] in
            let loadedWindows = await observationRunner.listWindows(applicationID: applicationID)
            guard !Task.isCancelled else {
                return
            }
            guard let self,
                  self.selectedApplicationID == applicationID else {
                return
            }
            self.windows = loadedWindows
            self.reconcileWindowSelection()
        }
    }

    private func reconcileWindowSelection() {
        guard !windows.isEmpty else {
            selectedWindowID = nil
            return
        }
        if let selectedWindowID,
           windows.contains(where: { $0.id == selectedWindowID }) {
            return
        }
        selectedWindowID = windows.first(where: \.isKeyWindow)?.id ?? windows[0].id
    }

    private func cancelActiveOperation() {
        activeCancellation?.cancel()
        observationTask?.cancel()
        actionTask?.cancel()
        agentTask?.cancel()
        windowTask?.cancel()
        activeCancellation = nil
        activeOperationID = nil
    }

    private func applyAgentResult(_ result: ComputerUseAgentResult) {
        agentResult = result
        observation = result.latestObservation
        lastActionResult = result.actionResults.last
        activeCancellation = nil
        agentTask = nil
        refreshAlwaysApprovals()
        phase = .agentCompleted
        if result.phase == .failed {
            errorMessage = result.message
        }
    }

    private func makeAgent(
        modelClient: ComputerUseModelClient?,
        limits: ComputerUseAgentLimits
    ) -> ComputerUseAgent {
        ComputerUseAgent(
            modelClient: modelClient ?? UnconfiguredComputerUseModelClient(),
            approvalService: self,
            approvalAuthorizer: approvalAuthorizer,
            observationService: observationService,
            actionService: actionService,
            interventionMonitor: interventionMonitor,
            limits: limits
        )
    }

    private func makeRemoteModelClient(
        configuration: ComputerUseRemoteModelConfiguration
    ) -> ComputerUseModelClient {
        OpenAICompatibleComputerUseModelClient(
            configuration: configuration.withScreenshotUpload(allowRemoteScreenshotUpload)
        )
    }

    private func decision(for scope: ComputerUseApprovalScope) -> ComputerUseApprovalDecision {
        switch scope {
        case .once:
            return .allowOnce
        case .session:
            return .allowForSession
        case .always:
            return .allowAlways
        }
    }

    @discardableResult
    private func resolveAgentApproval(
        requestID: UUID,
        decision: ComputerUseApprovalDecision
    ) -> Bool {
        guard let continuation = agentApprovalContinuations.removeValue(forKey: requestID) else {
            return false
        }
        if pendingApproval?.id == requestID {
            pendingApproval = nil
        }
        continuation.resume(returning: decision)
        if phase == .requestingApproval {
            phase = .runningAgent
        }
        return true
    }

    private func resolveAllAgentApprovals(
        with decision: ComputerUseApprovalDecision
    ) {
        let requestIDs = Array(agentApprovalContinuations.keys)
        for requestID in requestIDs {
            _ = resolveAgentApproval(requestID: requestID, decision: decision)
        }
    }

    private func localizedMessage(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
