import Foundation
import Observation

enum ComputerUseCoordinatorPhase: Equatable {
    case idle
    case checkingPermissions
    case requestingPermission(ComputerUsePermissionKind)
    case ready
    case running
    case completed
    case cancelled
    case failed
}

@MainActor
@Observable
final class ComputerUseCoordinator: ComputerUseVoiceTaskHandling {
    typealias AgentFactory = @MainActor (
        ComputerUseRemoteModelConfiguration,
        ComputerUseActivitySink
    ) -> any ComputerUseAgentRunning

    var phase: ComputerUseCoordinatorPhase = .idle
    var permissionSnapshot: ComputerUsePermissionSnapshot
    var draft = ""
    var conversation: [ComputerUseConversationMessage] = []
    var errorMessage: String?
    var debugSessionID: ComputerUseDebugSessionID?

    @ObservationIgnored private let permissions: any ComputerUsePermissionServing
    @ObservationIgnored private let permissionSettings:
        any ComputerUsePermissionSettingsOpening
    @ObservationIgnored private let cursorSession: any ComputerUseCursorSessionManaging
    @ObservationIgnored private let makeAgent: AgentFactory
    @ObservationIgnored private var configuration: ComputerUseRemoteModelConfiguration?
    @ObservationIgnored private var activeRun: Task<Void, Never>?
    @ObservationIgnored private var activeRunID: UUID?
    @ObservationIgnored private var pendingVoiceInstruction: String?
    @ObservationIgnored private var permissionOperationID: UUID?

    init(
        permissions: any ComputerUsePermissionServing = SystemComputerUsePermissionService(),
        permissionSettings: (any ComputerUsePermissionSettingsOpening)? = nil,
        initialPermissionSnapshot: ComputerUsePermissionSnapshot = .notGranted,
        cursorSession: any ComputerUseCursorSessionManaging = SystemComputerUseCursorPresenter(),
        makeAgent: @escaping AgentFactory = ComputerUseCoordinator.makeProductionAgent
    ) {
        self.permissions = permissions
        self.permissionSettings = permissionSettings
            ?? SystemComputerUsePermissionSettingsOpener()
        self.permissionSnapshot = initialPermissionSnapshot
        self.cursorSession = cursorSession
        self.makeAgent = makeAgent
    }

    var isRunning: Bool {
        phase == .running
    }

    var isBusy: Bool {
        switch phase {
        case .checkingPermissions, .requestingPermission, .running:
            true
        case .idle, .ready, .completed, .cancelled, .failed:
            false
        }
    }

    var isModelConfigured: Bool {
        configuration != nil
    }

    var modelID: String? {
        configuration?.modelID
    }

    var canSubmit: Bool {
        !isBusy
            && isModelConfigured
            && permissionSnapshot.canControlComputer
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isVoiceTaskPending: Bool {
        pendingVoiceInstruction != nil
    }

    func configureModel(_ configuration: ComputerUseRemoteModelConfiguration?) {
        self.configuration = configuration
        if phase == .idle {
            phase = .ready
        }
        startPendingVoiceTaskIfPossible()
    }

    func refreshPermissions() async {
        guard !isRunning else {
            return
        }
        let operationID = UUID()
        permissionOperationID = operationID
        phase = .checkingPermissions
        let snapshot = await permissions.snapshot()
        guard permissionOperationID == operationID, !isRunning else {
            return
        }
        permissionSnapshot = snapshot
        permissionOperationID = nil
        phase = .ready
        startPendingVoiceTaskIfPossible()
    }

    func requestAccessibility() async {
        await requestPermission(.accessibility)
    }

    func requestScreenRecording() async {
        await requestPermission(.screenRecording)
    }

    func openPermissionSettings(_ permission: ComputerUsePermissionKind) {
        permissionSettings.openSettings(for: permission)
    }

    func submit() {
        let instruction = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else {
            fail("Enter a Computer Use task.")
            return
        }
        guard let configuration else {
            fail("Configure a model before using Computer Use.")
            return
        }
        guard permissionSnapshot.accessibility == .granted else {
            fail("Grant Accessibility before using Computer Use.")
            return
        }
        guard permissionSnapshot.screenRecording == .granted else {
            fail("Grant Screen Recording before using Computer Use.")
            return
        }
        guard !isBusy else {
            return
        }

        let runID = UUID()
        let debugSessionID = ComputerUseDebugSessionID.generate(uuid: runID)
        let history = conversation
        conversation.append(.init(role: .user, text: instruction))
        draft = ""
        errorMessage = nil
        phase = .running
        activeRunID = runID
        self.debugSessionID = debugSessionID
        let activitySink = ComputerUseActivitySink { [weak self] activity in
            await self?.appendActivity(activity, for: runID)
        }
        let agent = makeAgent(configuration, activitySink)
        let task = ComputerUseAgentTask(
            instruction: instruction,
            conversation: history,
            debugSessionID: debugSessionID
        )
        activeRun = Task { [weak self] in
            let result = await agent.run(task: task)
            guard !Task.isCancelled,
                  let self,
                  self.activeRunID == runID else {
                return
            }
            self.finish(result)
        }
    }

    func submitVoiceTask(_ instruction: String) -> ComputerUseVoiceTaskSubmission {
        let normalized = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return .rejected(message: "No Computer Use task was transcribed.")
        }
        guard !isRunning, pendingVoiceInstruction == nil else {
            return .rejected(message: "Computer Use is already working.")
        }

        draft = normalized
        pendingVoiceInstruction = normalized
        if isModelConfigured && permissionSnapshot.canControlComputer {
            startPendingVoiceTaskIfPossible()
            return .started
        }
        return .queued
    }

    func stop() {
        guard isRunning else {
            return
        }
        invalidateActiveRun()
        cursorSession.endSession()
        pendingVoiceInstruction = nil
        phase = .cancelled
        appendAssistantMessage("Stopped.")
    }

    func startNewConversation() {
        guard !isRunning else {
            return
        }
        invalidateActiveRun()
        cursorSession.endSession()
        pendingVoiceInstruction = nil
        draft = ""
        conversation = []
        errorMessage = nil
        debugSessionID = nil
        phase = .ready
    }

    private func requestPermission(_ permission: ComputerUsePermissionKind) async {
        guard !isRunning else {
            return
        }
        let operationID = UUID()
        permissionOperationID = operationID
        phase = .requestingPermission(permission)
        let snapshot = await permissions.request(permission)
        guard permissionOperationID == operationID, !isRunning else {
            return
        }
        permissionSnapshot = snapshot
        permissionOperationID = nil
        phase = .ready
        startPendingVoiceTaskIfPossible()
    }

    private func finish(_ result: ComputerUseAgentResult) {
        activeRun = nil
        activeRunID = nil
        cursorSession.endSession()
        appendAssistantMessage(result.message)
        switch result.outcome {
        case .completed:
            phase = .completed
        case .cancelled:
            phase = .cancelled
        case .failed:
            phase = .failed
            errorMessage = result.message
        }
    }

    private func fail(_ message: String) {
        phase = .failed
        errorMessage = message
    }

    private func appendAssistantMessage(_ text: String) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return
        }
        conversation.append(.init(role: .assistant, text: normalized))
    }

    private func appendActivity(_ activity: ComputerUseActivity, for runID: UUID) {
        guard activeRunID == runID else {
            return
        }
        conversation.append(.init(activity: activity))
    }

    private func invalidateActiveRun() {
        activeRun?.cancel()
        activeRun = nil
        activeRunID = nil
    }

    func cancelPendingVoiceTask() {
        pendingVoiceInstruction = nil
    }

    private func startPendingVoiceTaskIfPossible() {
        guard let instruction = pendingVoiceInstruction,
              !isBusy,
              isModelConfigured,
              permissionSnapshot.canControlComputer else {
            return
        }
        draft = instruction
        pendingVoiceInstruction = nil
        submit()
    }

    private static func makeProductionAgent(
        configuration: ComputerUseRemoteModelConfiguration,
        activitySink: ComputerUseActivitySink
    ) -> any ComputerUseAgentRunning {
        ComputerUseAgent(
            model: ComputerUseRemoteModelClient(configuration: configuration),
            session: ComputerUseSession(backend: ComputerUseToolBackend()),
            activitySink: activitySink
        )
    }
}
