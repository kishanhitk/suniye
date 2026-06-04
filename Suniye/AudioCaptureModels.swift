import Foundation

enum AudioCaptureBackend: String, Codable, Equatable, Sendable {
    case inputOnlyHAL
    case standardEngine
    case voiceProcessingEngine
}

enum AudioCaptureInterruption: String, Codable, Equatable, Sendable {
    case deviceChanged
    case deviceUnavailable
    case formatChanged
    case serviceRestarted
    case engineConfigurationChanged
    case inputMuted
    case ioStoppedAbnormally
    case noAudioArriving
    case maximumDurationReached
    case systemSleep

    var userMessage: String {
        switch self {
        case .deviceChanged, .engineConfigurationChanged:
            return "Microphone changed. Try again."
        case .deviceUnavailable:
            return "The selected microphone disconnected. Reconnect it or choose another input."
        case .formatChanged:
            return "The microphone format changed. Try again."
        case .serviceRestarted:
            return "Audio service restarted. Try again."
        case .inputMuted:
            return "Your microphone is muted."
        case .ioStoppedAbnormally:
            return "Audio capture was interrupted. Try again."
        case .noAudioArriving:
            return "No audio is arriving from the selected microphone."
        case .maximumDurationReached:
            return "Maximum dictation length reached."
        case .systemSleep:
            return "Dictation stopped because your Mac went to sleep."
        }
    }
}

struct AudioRouteSnapshot: Equatable, Sendable {
    let preferredInputDeviceID: String?
    let effectiveInputDeviceID: String
    let effectiveInputName: String
    let inputTransport: AudioDeviceTransport
    let outputTransport: AudioDeviceTransport
    let inputSampleRate: Int
    let inputChannelCount: Int
    let requestedEchoCancellation: Bool
    let effectiveEchoCancellation: Bool
    let backend: AudioCaptureBackend
    let fallbackReason: String?

    var privacySafeLogValue: String {
        "input=\(inputTransport.rawValue) output=\(outputTransport.rawValue) sr=\(inputSampleRate) channels=\(inputChannelCount) backend=\(backend.rawValue) aec_requested=\(requestedEchoCancellation) aec_effective=\(effectiveEchoCancellation) fallback=\(fallbackReason ?? "none")"
    }
}

struct AudioCaptureSession: Equatable, Sendable {
    let id: UUID
    let route: AudioRouteSnapshot
}

enum AudioCaptureOutcome: Equatable, Sendable {
    case complete
    case tooShort
    case silent
    case clipped
    case bufferOverflow
    case invalidSamples
    case interrupted(AudioCaptureInterruption)

    var userMessage: String? {
        switch self {
        case .complete:
            return nil
        case .tooShort:
            return "Hold the shortcut a little longer and try again."
        case .silent:
            return "No speech was detected from the selected microphone."
        case .clipped:
            return "The microphone audio was distorted. Lower its input level and try again."
        case .bufferOverflow:
            return "Audio capture could not keep up. Try again."
        case .invalidSamples:
            return "The microphone returned invalid audio. Try again."
        case let .interrupted(reason):
            return reason.userMessage
        }
    }
}

struct AudioCaptureHealth: Equatable, Sendable {
    let frameCount: Int
    let durationSeconds: TimeInterval
    let rms: Float
    let peak: Float
    let clippedSampleCount: Int
    let nonFiniteSampleCount: Int
    let droppedSampleCount: UInt64
}

struct CapturedAudio: Equatable, Sendable {
    let sessionID: UUID?
    let samples: [Float]
    let sampleRate: Int
    let outcome: AudioCaptureOutcome
    let health: AudioCaptureHealth
    let route: AudioRouteSnapshot?

    init(
        sessionID: UUID? = nil,
        samples: [Float],
        sampleRate: Int,
        outcome: AudioCaptureOutcome? = nil,
        route: AudioRouteSnapshot? = nil,
        droppedSampleCount: UInt64 = 0
    ) {
        let health = Self.health(for: samples, sampleRate: sampleRate, droppedSampleCount: droppedSampleCount)
        self.sessionID = sessionID
        self.samples = samples
        self.sampleRate = sampleRate
        self.outcome = outcome ?? Self.outcome(for: health)
        self.health = health
        self.route = route
    }

    private static func health(for samples: [Float], sampleRate: Int, droppedSampleCount: UInt64) -> AudioCaptureHealth {
        var sum: Double = 0
        var peak: Float = 0
        var clipped = 0
        var nonFinite = 0

        for sample in samples {
            guard sample.isFinite else {
                nonFinite += 1
                continue
            }
            let absolute = abs(sample)
            peak = max(peak, absolute)
            if absolute >= 0.999 {
                clipped += 1
            }
            let value = Double(sample)
            sum += value * value
        }

        let finiteCount = max(1, samples.count - nonFinite)
        let rms = Float((sum / Double(finiteCount)).squareRoot())
        let effectiveRate = max(8_000, sampleRate)
        return AudioCaptureHealth(
            frameCount: samples.count,
            durationSeconds: Double(samples.count) / Double(effectiveRate),
            rms: rms,
            peak: peak,
            clippedSampleCount: clipped,
            nonFiniteSampleCount: nonFinite,
            droppedSampleCount: droppedSampleCount
        )
    }

    private static func outcome(for health: AudioCaptureHealth) -> AudioCaptureOutcome {
        if health.nonFiniteSampleCount > 0 {
            return .invalidSamples
        }
        if health.droppedSampleCount > 0 {
            return .bufferOverflow
        }
        if health.durationSeconds < 0.08 {
            return .tooShort
        }
        if health.peak < 0.000_01 {
            return .silent
        }
        if health.clippedSampleCount > max(64, health.frameCount / 4) {
            return .clipped
        }
        return .complete
    }
}
