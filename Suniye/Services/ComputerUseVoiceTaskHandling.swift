import Foundation

enum ComputerUseVoiceTaskSubmission: Equatable {
    case started
    case queued
    case intervened
    case rejected(message: String)
}

@MainActor
protocol ComputerUseVoiceTaskHandling: AnyObject {
    func submitVoiceTask(_ instruction: String) -> ComputerUseVoiceTaskSubmission
}
