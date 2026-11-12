import Foundation

enum AudioCaptureBackend: String, Codable, Equatable, Sendable {
    case inputOnlyHAL
    case standardEngine
    case voiceProcessingEngine
}

enum AudioCaptureFallbackReason: String, Codable, Equatable, Sendable {
    case bluetoothRoute = "bluetooth_route"
    case backendStartFailed = "backend_start_failed"
}

struct AudioCaptureFormat: Equatable, Sendable {
    let sampleRate: Int
    let channelCount: Int
}

/// Why Suniye records from a microphone other than the one the user chose.
enum AudioInputStandIn: Equatable, Sendable {
    /// The saved microphone is not connected.
    case preferredMissing
    /// The chosen microphone is this built-in one, off while the lid is closed.
    case offWithLidClosed(name: String)
    /// The system default is this Bluetooth microphone. Recording from it
    /// switches the headset to call-quality audio.
    case bluetoothDefault(name: String)

    var logValue: String {
        switch self {
        case .preferredMissing: return "preferred_missing"
        case .offWithLidClosed: return "lid_closed"
        case .bluetoothDefault: return "bluetooth_default"
        }
    }
}

struct AudioInputResolution {
    let device: AudioInputDevice
    let standIn: AudioInputStandIn?
}

/// Picks the microphone a dictation records from.
///
/// A connected saved microphone always wins, Bluetooth included: that is how a
/// user chooses a headset on purpose. Otherwise the system default, unless it is
/// Bluetooth or off with the lid closed; then the built-in microphone, then
/// another wired input. Bluetooth only when nothing else can record.
enum AudioInputResolver {
    static func resolve(
        preferredInputDeviceID: String?,
        devices: [AudioInputDevice]
    ) throws -> AudioInputResolution {
        let usable = devices.filter(\.isAvailable)
        if let preferredInputDeviceID,
           let preferred = usable.first(where: { $0.id == preferredInputDeviceID }) {
            return AudioInputResolution(device: preferred, standIn: nil)
        }

        let wired = usable.filter { canStandIn($0.transport) }
        guard let device = usable.first(where: { $0.isDefault && !$0.transport.isBluetooth })
            ?? wired.first(where: { $0.transport == .builtIn })
            ?? wired.first
            // A Bluetooth microphone beats recording nothing.
            ?? usable.first(where: \.isDefault)
            ?? usable.first(where: \.transport.isBluetooth)
        else {
            throw devices.contains { $0.availability == .offWithLidClosed }
                ? AudioCaptureServiceError.builtInMicrophoneOff
                : AudioCaptureServiceError.noInputDevice
        }

        let standIn: AudioInputStandIn?
        if let preferredInputDeviceID {
            standIn = devices.first { $0.id == preferredInputDeviceID }.flatMap(reasonSkipped) ?? .preferredMissing
        } else if let systemDefault = devices.first(where: \.isDefault), systemDefault.id != device.id {
            standIn = reasonSkipped(systemDefault)
        } else {
            standIn = nil
        }
        return AudioInputResolution(device: device, standIn: standIn)
    }

    private static func reasonSkipped(_ device: AudioInputDevice) -> AudioInputStandIn? {
        switch device.availability {
        case .offWithLidClosed:
            return .offWithLidClosed(name: device.name)
        case .available where device.transport.isBluetooth:
            return .bluetoothDefault(name: device.name)
        case .available, .notConnected:
            return nil
        }
    }

    /// A virtual or aggregate input can record silence while its app is idle,
    /// and an iPhone's Continuity microphone prompts on the phone and can fail,
    /// so neither replaces a skipped microphone.
    private static func canStandIn(_ transport: AudioDeviceTransport) -> Bool {
        switch transport {
        case .builtIn, .usb, .other:
            return true
        case .bluetooth, .bluetoothLE, .continuity, .aggregate, .virtual:
            return false
        }
    }
}

struct AudioDeviceRoute: Equatable, Sendable {
    let preferredInputDeviceID: String?
    let effectiveInputDeviceID: String
    let effectiveInputName: String
    let inputTransport: AudioDeviceTransport
    let outputTransport: AudioDeviceTransport
    let nominalInputSampleRate: Int
    let inputChannelCount: Int
    let standIn: AudioInputStandIn?
}

struct AudioCapturePlan: Equatable, Sendable {
    let deviceRoute: AudioDeviceRoute
    let requestedEchoCancellation: Bool
    let effectiveEchoCancellation: Bool
    let backend: AudioCaptureBackend
    let fallbackReason: AudioCaptureFallbackReason?

    func snapshot(format: AudioCaptureFormat? = nil) -> AudioRouteSnapshot {
        AudioRouteSnapshot(
            preferredInputDeviceID: deviceRoute.preferredInputDeviceID,
            effectiveInputDeviceID: deviceRoute.effectiveInputDeviceID,
            effectiveInputName: deviceRoute.effectiveInputName,
            inputTransport: deviceRoute.inputTransport,
            outputTransport: deviceRoute.outputTransport,
            inputSampleRate: format?.sampleRate ?? deviceRoute.nominalInputSampleRate,
            inputChannelCount: format?.channelCount ?? deviceRoute.inputChannelCount,
            requestedEchoCancellation: requestedEchoCancellation,
            effectiveEchoCancellation: effectiveEchoCancellation,
            backend: backend,
            fallbackReason: fallbackReason,
            standIn: deviceRoute.standIn
        )
    }
}

enum AudioCapturePolicy {
    static func primaryPlan(
        for route: AudioDeviceRoute,
        echoCancellationEnabled: Bool
    ) -> AudioCapturePlan {
        let supportsEchoCancellation = !route.inputTransport.isBluetooth && !route.outputTransport.isBluetooth
        let effectiveEchoCancellation = echoCancellationEnabled && supportsEchoCancellation
        return AudioCapturePlan(
            deviceRoute: route,
            requestedEchoCancellation: echoCancellationEnabled,
            effectiveEchoCancellation: effectiveEchoCancellation,
            backend: effectiveEchoCancellation ? .voiceProcessingEngine : .inputOnlyHAL,
            fallbackReason: echoCancellationEnabled && !supportsEchoCancellation ? .bluetoothRoute : nil
        )
    }

    static func fallbackPlan(
        for route: AudioDeviceRoute,
        echoCancellationEnabled: Bool,
        reason: AudioCaptureFallbackReason
    ) -> AudioCapturePlan {
        AudioCapturePlan(
            deviceRoute: route,
            requestedEchoCancellation: echoCancellationEnabled,
            effectiveEchoCancellation: false,
            backend: .standardEngine,
            fallbackReason: reason
        )
    }
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
            return "The microphone disconnected. Try again."
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
    let fallbackReason: AudioCaptureFallbackReason?
    let standIn: AudioInputStandIn?

    var privacySafeLogValue: String {
        "input=\(inputTransport.rawValue) output=\(outputTransport.rawValue) sr=\(inputSampleRate) channels=\(inputChannelCount) backend=\(backend.rawValue) aec_requested=\(requestedEchoCancellation) aec_effective=\(effectiveEchoCancellation) fallback=\(fallbackReason?.rawValue ?? "none") standin=\(standIn?.logValue ?? "none")"
    }
}

struct AudioCaptureSession: Equatable, Sendable {
    let id: UUID
    let route: AudioRouteSnapshot
}

/// Mid-recording copy of the tail of the accumulated sample buffer, used for
/// live transcription preview decodes.
struct AudioSampleSnapshot: Equatable, Sendable {
    let samples: [Float]
    let sampleRate: Int
}

enum AudioCaptureEvent: Equatable, Sendable {
    case levelsUpdated(sessionID: UUID, levels: [Float])
    case devicesChanged([AudioInputDevice])
    case routeChanged(sessionID: UUID, route: AudioRouteSnapshot)
    case interrupted(sessionID: UUID, reason: AudioCaptureInterruption)
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
        route: AudioRouteSnapshot? = nil,
        droppedSampleCount: UInt64 = 0
    ) {
        let health = Self.health(for: samples, sampleRate: sampleRate, droppedSampleCount: droppedSampleCount)
        self.sessionID = sessionID
        self.samples = samples
        self.sampleRate = sampleRate
        self.outcome = Self.outcome(for: health)
        self.health = health
        self.route = route
    }

    static func interrupted(
        sessionID: UUID?,
        reason: AudioCaptureInterruption,
        route: AudioRouteSnapshot? = nil
    ) -> CapturedAudio {
        CapturedAudio(
            sessionID: sessionID,
            samples: [],
            sampleRate: route?.inputSampleRate ?? 16_000,
            outcome: .interrupted(reason),
            route: route,
            droppedSampleCount: 0
        )
    }

    private init(
        sessionID: UUID?,
        samples: [Float],
        sampleRate: Int,
        outcome: AudioCaptureOutcome,
        route: AudioRouteSnapshot?,
        droppedSampleCount: UInt64
    ) {
        self.sessionID = sessionID
        self.samples = samples
        self.sampleRate = sampleRate
        self.outcome = outcome
        self.health = Self.health(for: samples, sampleRate: sampleRate, droppedSampleCount: droppedSampleCount)
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
