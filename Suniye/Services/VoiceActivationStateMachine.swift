import Foundation

/// The context a spoken turn was captured in.
enum VoiceTurnContext: Equatable, Sendable {
    /// Wake phrase heard while no run was active.
    case initial
    /// Wake phrase heard while a Computer Use run was active; the turn becomes an intervention.
    case duringRun
    /// Captured inside the post-completion follow-up window; no wake phrase required.
    case followUp
}

/// Events the controller feeds into the state machine.
enum VoiceActivationEvent: Equatable, Sendable {
    case enabled
    case disabled
    case systemSlept
    case systemWoke(tapRestored: Bool)
    case tapSuspended
    case tapRestored
    case wakeDetected(runActive: Bool)
    case speechStarted
    case speechEnded
    case noSpeechTimeout
    case cancelRequested
    case transcriptSubmitted
    case transcriptFailed
    case runCompleted(speechWillPlay: Bool)
    case runStoppedOrFailed
    case speechPlaybackEnded
}

/// Effects the controller must perform after a transition.
enum VoiceActivationEffect: Equatable, Sendable {
    /// Begin a capture window with the endpointer's default no-speech timeout.
    case startTurnCapture
    case stopTurnCapture
    case transcribeAndSubmit
    case playWakeCue
    /// Begin a capture window with the (longer) follow-up no-speech timeout.
    /// Expiry arrives back as `.noSpeechTimeout` — the endpointer is the only
    /// timer; there is no separate expiry mechanism.
    case armFollowUpWindow
}

/// The user-visible states from the UX plan that belong to the listening
/// lifecycle. Run progress (working, needs input, terminal) is owned by
/// `ComputerUseCoordinator` and only enters here as events.
enum VoiceActivationState: Equatable, Sendable {
    case off
    /// Enabled, but the tap is unavailable (system sleep, hold-to-talk session).
    case suspended
    case ready
    case listening(VoiceTurnContext)
    case transcribing(VoiceTurnContext)
    /// Post-completion window in which speech starts a turn without a wake phrase.
    case followUpWindow
}

/// Pure state machine for Voice Activation. The controller owns side effects;
/// this type owns legality of transitions.
struct VoiceActivationStateMachine: Equatable, Sendable {
    struct Configuration: Equatable, Sendable {
        var followUpWindowEnabled: Bool = false
    }

    private(set) var state: VoiceActivationState = .off
    var configuration: Configuration

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    @discardableResult
    mutating func handle(_ event: VoiceActivationEvent) -> [VoiceActivationEffect] {
        switch (state, event) {
        case (.off, .enabled):
            state = .ready
            return []
        case (_, .disabled):
            let effects = cancellationEffects()
            state = .off
            return effects

        case (.off, _):
            return []

        case (_, .systemSlept), (_, .tapSuspended):
            let effects = cancellationEffects()
            state = .suspended
            return effects
        case (.suspended, .systemWoke(let tapRestored)):
            state = tapRestored ? .ready : .suspended
            return []
        case (.suspended, .tapRestored):
            state = .ready
            return []
        case (.suspended, _):
            return []

        case (.ready, .wakeDetected(let runActive)), (.followUpWindow, .wakeDetected(let runActive)):
            state = .listening(runActive ? .duringRun : .initial)
            return [.playWakeCue, .startTurnCapture]

        case (.followUpWindow, .speechStarted):
            state = .listening(.followUp)
            return []
        case (.followUpWindow, .speechEnded):
            state = .transcribing(.followUp)
            return [.stopTurnCapture, .transcribeAndSubmit]

        case (.listening(let context), .speechEnded):
            state = .transcribing(context)
            return [.stopTurnCapture, .transcribeAndSubmit]
        case (.listening, .noSpeechTimeout), (.listening, .cancelRequested),
             (.followUpWindow, .noSpeechTimeout):
            state = .ready
            return [.stopTurnCapture]

        case (.transcribing, .transcriptSubmitted), (.transcribing, .transcriptFailed):
            state = .ready
            return []

        case (.ready, .runCompleted(let speechWillPlay)):
            guard configuration.followUpWindowEnabled, !speechWillPlay else {
                // With speech playing, the window arms on playbackEnded instead
                // (self-capture guard).
                return []
            }
            state = .followUpWindow
            return [.armFollowUpWindow]
        case (.ready, .speechPlaybackEnded):
            guard configuration.followUpWindowEnabled else {
                return []
            }
            state = .followUpWindow
            return [.armFollowUpWindow]

        default:
            return []
        }
    }

    private func cancellationEffects() -> [VoiceActivationEffect] {
        switch state {
        case .listening, .followUpWindow:
            return [.stopTurnCapture]
        case .off, .suspended, .ready, .transcribing:
            return []
        }
    }
}
