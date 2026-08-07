import Foundation
import Observation

enum ComputerUseCoordinatorPhase: Equatable {
    case idle
    case loadingApplications
    case requestingPermission
    case ready
    case observing
    case runningAgent
    case observed
    case agentCompleted
    case failed
}

/// Main-actor state for the Computer Use task and observation surface.
///
/// Native discovery, observation, and action execution run through
/// `ComputerUsePlatformRunner` so platform work does not block SwiftUI rendering.
@MainActor
@Observable
final class ComputerUseCoordinator: ComputerUseVoiceTaskHandling {
    private let runner: ComputerUsePlatformRunner
    private let applicationCatalog: ComputerUseApplicationCatalog
    private let observationService: ComputerUseObservationServicing
    private let actionService: ComputerUseActionServicing
    private let approvalAuthorizer: ComputerUseApprovalAuthorizing
    private let sessionID: UUID
    private var modelClient: ComputerUseModelClient?

    var phase: ComputerUseCoordinatorPhase = .idle
    var applications: [ComputerUseApplication] = []
    var selectedApplicationID: String?
    var permissionSnapshot = ComputerUsePermissionSnapshot(
        accessibility: .notGranted,
        screenRecording: .notGranted
    )
    var observation: ComputerUseObservation?
    var errorMessage: String?
    var agentInstruction = ""
    var agentResult: ComputerUseAgentResult?
    var isVoiceTaskPending: Bool {
        pendingVoiceInstruction != nil
    }

    @ObservationIgnored private var activeOperationID: UUID?
    @ObservationIgnored private var activeCancellation: ComputerUseCancellationToken?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var permissionTask: Task<Void, Never>?
    @ObservationIgnored private var observationTask: Task<Void, Never>?
    @ObservationIgnored private var agentTask: Task<Void, Never>?
    @ObservationIgnored private var remoteModelConfiguration: ComputerUseRemoteModelConfiguration?
    private var pendingVoiceInstruction: String?
    @ObservationIgnored private lazy var agent: ComputerUseAgent = makeAgent(
        modelClient: modelClient
    )
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
        modelClient: ComputerUseModelClient? = nil
    ) {
        let resolvedCatalog = applicationCatalog ?? SystemComputerUseApplicationCatalog()
        let resolvedWindowDiscovery = windowDiscovery ?? SystemComputerUseWindowDiscovery()
        let resolvedWindowActivator = windowActivator ?? SystemComputerUseWindowActivator()
        let resolvedPermissionManager = permissionManager ?? SystemComputerUsePermissionService()
        let resolvedApprovalStore = approvalStore ?? ComputerUseApprovalStore()
        let resolvedPolicy = policy ?? ComputerUsePolicyService()
        let resolvedAuditRecorder = auditRecorder ?? AppLoggerComputerUseAuditRecorder()
        approvalAuthorizer = ComputerUseApprovalPolicyActor(
            policyService: ComputerUseApprovalPolicyService(
                policy: resolvedPolicy,
                store: resolvedApprovalStore,
                auditRecorder: resolvedAuditRecorder
            )
        )
        sessionID = UUID()
        let resolvedObservationService = observationService ?? ComputerUseObservationService(
            applicationCatalog: resolvedCatalog,
            windowDiscovery: resolvedWindowDiscovery,
            windowActivator: resolvedWindowActivator,
            permissionManager: resolvedPermissionManager
        )
        let resolvedActionService = actionService ?? ComputerUseActionService(
            targetActivator: resolvedWindowActivator,
            permissionManager: resolvedPermissionManager,
            approvalStore: resolvedApprovalStore,
            policy: resolvedPolicy
        )
        self.applicationCatalog = resolvedCatalog
        self.observationService = resolvedObservationService
        self.actionService = resolvedActionService
        self.modelClient = modelClient

        runner = ComputerUsePlatformRunner(
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
        case .runningAgent:
            true
        case .idle, .ready, .observed, .agentCompleted, .failed:
            false
        }
    }

    var canRunAgent: Bool {
        guard !isBusy,
              isModelConfigured,
              permissionSnapshot.canReadAccessibility,
              permissionSnapshot.canCaptureScreen else {
            return false
        }
        return true
    }

    var isModelConfigured: Bool {
        guard modelClient != nil else {
            return false
        }
        return remoteModelConfiguration?.validationMessage == nil
    }

    var canObserve: Bool {
        guard let selectedApplicationID,
              !selectedApplicationID.isEmpty,
              !isBusy,
              permissionSnapshot.canReadAccessibility,
              permissionSnapshot.canCaptureScreen else {
            return false
        }
        return true
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
        case .runningAgent:
            return "Computer Use is working"
        case .observed:
            return "Observation captured"
        case .agentCompleted:
            return "Computer Use finished"
        case .failed:
            return "Computer Use failed"
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
        agent = makeAgent(modelClient: modelClient)
        startPendingVoiceTaskIfPossible()
    }

    func configureRemoteModel(_ configuration: ComputerUseRemoteModelConfiguration?) {
        guard !isBusy else {
            return
        }
        remoteModelConfiguration = configuration
        modelClient = configuration.map { makeRemoteModelClient(configuration: $0) }
        agent = makeAgent(modelClient: modelClient)
        startPendingVoiceTaskIfPossible()
    }

    func submitVoiceTask(_ instruction: String) -> ComputerUseVoiceTaskSubmission {
        let trimmedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInstruction.isEmpty else {
            return .rejected(message: "No Computer Use task was transcribed.")
        }

        guard phase != .runningAgent, phase != .observing else {
            return .rejected(message: "Computer Use is already working.")
        }

        agentInstruction = trimmedInstruction
        pendingVoiceInstruction = trimmedInstruction
        if canRunAgent {
            startPendingVoiceTaskIfPossible()
            return .started
        } else {
            errorMessage = voiceTaskWaitingMessage
            return .queued
        }
    }

    func startAgent() {
        let instruction = agentInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else {
            phase = .failed
            errorMessage = "Enter a task for Computer Use."
            return
        }
        guard canRunAgent else {
            return
        }

        pendingVoiceInstruction = nil
        cancelActiveOperation()
        let operationID = UUID()
        let cancellation = ComputerUseCancellationToken()
        let agent = self.agent
        let task = ComputerUseAgentTask(
            instruction: instruction,
            applicationID: selectedApplicationID,
            sessionID: sessionID
        )
        activeOperationID = operationID
        activeCancellation = cancellation
        observation = nil
        agentResult = nil
        errorMessage = nil
        phase = .runningAgent

        agentTask = Task { [weak self] in
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

        let observationRunner = runner
        refreshTask = Task { [weak self] in
            async let applications = observationRunner.listApplications()
            async let permissions = observationRunner.permissionSnapshot()
            let (loadedApplications, loadedPermissions) = await (
                applications,
                permissions
            )

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
            self.startPendingVoiceTaskIfPossible()
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
            self.startPendingVoiceTaskIfPossible()
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
        cancelActiveOperation()
        refreshTask?.cancel()
        permissionTask?.cancel()
        pendingVoiceInstruction = nil

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
            self.startPendingVoiceTaskIfPossible()
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
        agentTask?.cancel()
        activeCancellation = nil
        activeOperationID = nil
    }

    private func applyAgentResult(_ result: ComputerUseAgentResult) {
        agentResult = result
        observation = result.latestObservation
        activeCancellation = nil
        agentTask = nil
        if result.phase == .failed {
            phase = .failed
            errorMessage = result.message
        } else {
            phase = .agentCompleted
        }
    }

    private func startPendingVoiceTaskIfPossible() {
        guard let pendingInstruction = pendingVoiceInstruction, canRunAgent else {
            return
        }
        agentInstruction = pendingInstruction
        pendingVoiceInstruction = nil
        startAgent()
    }

    private var voiceTaskWaitingMessage: String {
        if isBusy {
            return "Voice task captured. Computer Use is still preparing."
        }
        if !isModelConfigured {
            return "Voice task captured. Connect a model to run it."
        }
        return "Voice task captured. Grant Computer Use permissions to run it."
    }

    private func makeAgent(
        modelClient: ComputerUseModelClient?
    ) -> ComputerUseAgent {
        ComputerUseAgent(
            modelClient: modelClient ?? UnconfiguredComputerUseModelClient(),
            approvalAuthorizer: approvalAuthorizer,
            applicationCatalog: applicationCatalog,
            observationService: observationService,
            actionService: actionService
        )
    }

    private func makeRemoteModelClient(
        configuration: ComputerUseRemoteModelConfiguration
    ) -> ComputerUseModelClient {
        OpenAICompatibleComputerUseModelClient(
            configuration: configuration
        )
    }

}
