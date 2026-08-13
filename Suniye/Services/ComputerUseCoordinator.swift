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

    var phase: ComputerUseCoordinatorPhase = .idle {
        didSet {
            guard oldValue != phase else { return }
            onPhaseChange?(phase)
        }
    }
    var permissionSnapshot: ComputerUsePermissionSnapshot
    var draft = ""
    var conversation: [ComputerUseConversationMessage] = []
    var errorMessage: String?
    var debugSessionID: ComputerUseDebugSessionID?

    private struct ActiveRun {
        let id: UUID
        let interventions: ComputerUseInterventionChannel
        var task: Task<Void, Never>?
    }

    /// True while the Computer Use page is on screen. Dictation with no
    /// explicit destination routes here so spoken text lands in the
    /// conversation instead of the focused text field.
    @ObservationIgnored var isPageActive = false

    @ObservationIgnored var onPhaseChange: ((ComputerUseCoordinatorPhase) -> Void)?
    @ObservationIgnored private let permissions: any ComputerUsePermissionServing
    @ObservationIgnored private let permissionSettings:
        any ComputerUsePermissionSettingsOpening
    @ObservationIgnored private let cursorSession: any ComputerUseCursorSessionManaging
    @ObservationIgnored private let conversationStore: any ComputerUseConversationStoring
    @ObservationIgnored private let makeAgent: AgentFactory
    @ObservationIgnored private var configuration: ComputerUseRemoteModelConfiguration?
    @ObservationIgnored private var activeRun: ActiveRun?
    @ObservationIgnored private var pendingVoiceInstruction: String?
    @ObservationIgnored private var permissionOperationID: UUID?

    init(
        permissions: any ComputerUsePermissionServing = SystemComputerUsePermissionService(),
        permissionSettings: (any ComputerUsePermissionSettingsOpening)? = nil,
        initialPermissionSnapshot: ComputerUsePermissionSnapshot = .notGranted,
        cursorSession: any ComputerUseCursorSessionManaging = SystemComputerUseCursorPresenter(),
        conversationStore: any ComputerUseConversationStoring = NoopComputerUseConversationStore(),
        makeAgent: @escaping AgentFactory = ComputerUseCoordinator.makeProductionAgent
    ) {
        self.permissions = permissions
        self.permissionSettings = permissionSettings
            ?? SystemComputerUsePermissionSettingsOpener()
        self.permissionSnapshot = initialPermissionSnapshot
        self.cursorSession = cursorSession
        self.conversationStore = conversationStore
        self.makeAgent = makeAgent
        conversation = conversationStore.load()
        pendingVoiceInstruction = conversationStore.loadPendingVoiceInstruction()
        draft = pendingVoiceInstruction ?? ""
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
        let interventions = ComputerUseInterventionChannel()
        let debugSessionID = ComputerUseDebugSessionID.generate(uuid: runID)
        let history = conversation
        conversation.append(.init(role: .user, text: instruction))
        persistConversation()
        draft = ""
        errorMessage = nil
        phase = .running
        activeRun = ActiveRun(id: runID, interventions: interventions, task: nil)
        self.debugSessionID = debugSessionID
        let activitySink = ComputerUseActivitySink { [weak self] activity in
            await self?.appendActivity(activity, for: runID)
        }
        let agent = makeAgent(configuration, activitySink)
        let task = ComputerUseAgentTask(
            instruction: instruction,
            conversation: history,
            debugSessionID: debugSessionID,
            interventions: interventions
        )
        activeRun?.task = Task { [weak self] in
            let result = await agent.run(task: task)
            guard !Task.isCancelled,
                  let self,
                  self.activeRun?.id == runID else {
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
        if isRunning, let activeRun {
            conversation.append(.init(role: .user, text: normalized))
            persistConversation()
            activeRun.interventions.submit(normalized)
            return .intervened
        }
        guard pendingVoiceInstruction == nil else {
            return .rejected(message: "A Computer Use voice task is already pending.")
        }

        pendingVoiceInstruction = normalized
        conversationStore.savePendingVoiceInstruction(normalized)
        draft = normalized
        return startPendingVoiceTaskIfPossible() ? .started : .queued
    }

    func stop() {
        guard isRunning else {
            return
        }
        invalidateActiveRun()
        cursorSession.endSession()
        pendingVoiceInstruction = nil
        conversationStore.savePendingVoiceInstruction(nil)
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
        conversationStore.savePendingVoiceInstruction(nil)
        draft = ""
        conversation = []
        persistConversation()
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
        cursorSession.endSession()
        appendAssistantMessage(result.message)
        // The run's activity rows only persist at terminal states; a crash
        // mid-run loses them, which recovery treats as acceptable.
        persistConversation()
        switch result.outcome {
        case .completed:
            phase = .completed
        case .cancelled:
            phase = .cancelled
        case .failed:
            errorMessage = result.message
            phase = .failed
        }
    }

    private func fail(_ message: String) {
        errorMessage = message
        phase = .failed
    }

    private func appendAssistantMessage(_ text: String) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return
        }
        conversation.append(.init(role: .assistant, text: normalized))
        persistConversation()
    }

    private func appendActivity(_ activity: ComputerUseActivity, for runID: UUID) {
        guard activeRun?.id == runID else {
            return
        }
        if let index = conversation.firstIndex(where: { $0.activity?.id == activity.id }) {
            conversation[index] = .init(
                id: conversation[index].id,
                activity: activity
            )
            return
        }
        conversation.append(.init(activity: activity))
    }

    private func persistConversation() {
        conversationStore.save(conversation)
    }

    private func invalidateActiveRun() {
        activeRun?.task?.cancel()
        activeRun?.interventions.removeAll()
        activeRun = nil
    }

    func cancelPendingVoiceTask() {
        pendingVoiceInstruction = nil
        conversationStore.savePendingVoiceInstruction(nil)
    }

    /// The one launch gate for a pending voice instruction. Every async
    /// completion point that can change the preconditions (model configured,
    /// permissions refreshed or granted) calls this; the return value reports
    /// whether a run actually started.
    @discardableResult
    private func startPendingVoiceTaskIfPossible() -> Bool {
        guard let instruction = pendingVoiceInstruction else { return false }
        draft = instruction
        guard canSubmit else { return false }
        submit()
        guard isRunning else { return false }
        pendingVoiceInstruction = nil
        conversationStore.savePendingVoiceInstruction(nil)
        return true
    }

    private static func makeProductionAgent(
        configuration: ComputerUseRemoteModelConfiguration,
        activitySink: ComputerUseActivitySink
    ) -> any ComputerUseAgentRunning {
        ComputerUseAgent(
            model: ComputerUseRemoteModelClient(configuration: configuration),
            tools: ComputerUseToolBackend(),
            activitySink: activitySink,
            contextPolicy: .referenceAligned(modelID: configuration.modelID)
        )
    }
}
