enum ComputerUseVoiceTaskSubmission: Equatable {
    case started
    case queued
    case rejected(message: String)
}

/// Main-actor seam between the dictation pipeline and the Computer Use task
/// coordinator. The caller supplies already-transcribed task text; the adapter
/// owns task state, readiness, and agent launch.
@MainActor
protocol ComputerUseVoiceTaskHandling: AnyObject {
    func submitVoiceTask(_ instruction: String) -> ComputerUseVoiceTaskSubmission
}
