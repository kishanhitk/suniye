import AppKit

enum SoundFeedbackEvent: Equatable {
    case transcriptionSucceeded
    case error
}

protocol SoundFeedbackServiceProtocol: AnyObject {
    func play(_ event: SoundFeedbackEvent)
}

final class SoundFeedbackService: SoundFeedbackServiceProtocol {
    private var sounds: [SoundFeedbackEvent: NSSound] = [:]

    func play(_ event: SoundFeedbackEvent) {
        let sound = sound(for: event)
        sound?.stop()
        sound?.play()
    }

    private func sound(for event: SoundFeedbackEvent) -> NSSound? {
        if let sound = sounds[event] {
            return sound
        }

        guard let sound = NSSound(named: event.soundName) else {
            return nil
        }

        sounds[event] = sound
        return sound
    }
}

private extension SoundFeedbackEvent {
    var soundName: NSSound.Name {
        switch self {
        case .transcriptionSucceeded:
            return NSSound.Name("Ping")
        case .error:
            return NSSound.Name("Basso")
        }
    }
}
