import AudioToolbox
import CoreAudio
import Foundation

enum MeetingAudioSourceEvent: Equatable, Sendable {
    /// The microphone moved to another input; the recording goes on.
    case inputChanged(deviceName: String)
    /// The source stopped and could not start again.
    case failed(String)
}

/// One meeting track. Blocks arrive as 16 kHz mono floats on a background queue.
protocol MeetingAudioSource: AnyObject {
    var onSamples: (([Float]) -> Void)? { get set }
    var onEvent: ((MeetingAudioSourceEvent) -> Void)? { get set }
    func start() throws
    func stop()
}

/// The meeting's microphone track. It opens the same `MicrophoneStream` and
/// device choice as dictation's `AudioCaptureService`. Unlike a dictation, a
/// meeting outlives a device change: it reopens the input that the device
/// choice picks, with the microphone that the user picked when the meeting
/// started.
final class MeetingMicCapture: MeetingAudioSource, @unchecked Sendable {
    @Locked var onSamples: (([Float]) -> Void)?
    @Locked var onEvent: ((MeetingAudioSourceEvent) -> Void)?

    /// An engine reports a harmless configuration change right after it
    /// starts; changes this soon after an open are not reopened.
    static let settleTime: TimeInterval = 2
    /// This many reopens with no sound between them end the track.
    static let maximumReopens = 20
    /// A closed lid with an external display gives exact zeros with no Core
    /// Audio event. After this long, the capture checks the device choice
    /// again, which skips a built-in mic that the lid switched off.
    static let digitalSilenceLimit: TimeInterval = 10

    private let queue = DispatchQueue(label: "dev.suniye.meeting.microphone", qos: .userInitiated)
    private let queueKey = DispatchSpecificKey<Void>()
    private let hardwareCatalog: AudioCaptureHardwareCatalogProtocol
    private let deviceMonitor: AudioDeviceMonitorProtocol
    private let driverFactory: AudioCaptureDriverFactoryProtocol
    private let preferredInputDeviceID: String?
    private let firstFrameDeadline: DispatchTimeInterval
    private let uptime: () -> TimeInterval

    private var running = false
    private var stream: MicrophoneStream?
    private var resampler: MeetingResampler?
    private var openedAt: TimeInterval = 0
    private var reopensWithoutSound = 0
    private var digitalSilenceSince: TimeInterval?

    init(
        hardwareCatalog: AudioCaptureHardwareCatalogProtocol = CoreAudioCaptureHardwareCatalog(),
        deviceMonitor: AudioDeviceMonitorProtocol = CoreAudioDeviceMonitor(),
        driverFactory: AudioCaptureDriverFactoryProtocol = DefaultAudioCaptureDriverFactory(),
        firstFrameDeadline: DispatchTimeInterval = .milliseconds(1_500),
        uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        preferredInputDeviceID: String? = nil
    ) {
        self.hardwareCatalog = hardwareCatalog
        self.deviceMonitor = deviceMonitor
        self.driverFactory = driverFactory
        self.firstFrameDeadline = firstFrameDeadline
        self.uptime = uptime
        self.preferredInputDeviceID = preferredInputDeviceID
        queue.setSpecific(key: queueKey, value: ())
    }

    deinit {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            closeInput()
        } else {
            queue.sync { closeInput() }
        }
    }

    func start() throws {
        try queue.sync {
            guard !running else { return }
            reopensWithoutSound = 0
            try openInput()
            running = true
            deviceMonitor.onChange = { [weak self] reason in
                self?.queue.async { self?.handleDeviceChange(reason) }
            }
            deviceMonitor.start()
        }
    }

    func stop() {
        queue.sync {
            guard running else { return }
            running = false
            deviceMonitor.stop()
            deviceMonitor.onChange = nil
            stream?.drain()
            if let tail = resampler?.flush(), !tail.isEmpty {
                onSamples?(tail)
            }
            closeInput()
        }
    }

    // MARK: - Input lifecycle (on `queue`)

    private func openInput() throws {
        let resolution = try hardwareCatalog.resolveDeviceRoute(preferredInputDeviceID: preferredInputDeviceID)
        let stream = try MicrophoneStream(
            queue: queue,
            driverFactory: driverFactory,
            resolution: resolution,
            echoCancellationEnabled: false,
            firstFrameDeadline: firstFrameDeadline
        )
        stream.delegate = self
        self.stream = stream
        do {
            try stream.start()
        } catch {
            self.stream = nil
            throw error
        }
    }

    private func closeInput() {
        stream?.stop()
        stream = nil
        resampler = nil
    }

    private func reopen(reason: String) {
        guard running else { return }
        reopensWithoutSound += 1
        guard reopensWithoutSound <= Self.maximumReopens else {
            fail("The microphone kept failing (\(reason)).")
            return
        }
        let previousName = stream?.deviceRoute.effectiveInputName
        stream?.drain()
        closeInput()
        do {
            try openInput()
            AppLogger.shared.log(.info, "meeting microphone reopened reason=\(reason)")
            if let name = stream?.deviceRoute.effectiveInputName, name != previousName {
                onEvent?(.inputChanged(deviceName: name))
            }
        } catch {
            AppLogger.shared.log(.error, "meeting microphone could not reopen reason=\(reason) error=\(error.localizedDescription)")
            fail(error.localizedDescription)
        }
    }

    private func fail(_ message: String) {
        running = false
        deviceMonitor.stop()
        deviceMonitor.onChange = nil
        closeInput()
        onEvent?(.failed(message))
    }

    private func handleDeviceChange(_ reason: AudioDeviceChangeReason) {
        switch reason {
        case .selectedDeviceFormat, .serviceRestarted, .ioStoppedAbnormally:
            guard running else { return }
            reopen(reason: reason.rawValue)
        case .defaultInput, .devices, .selectedDeviceAlive, .selectedDeviceChanged:
            reopenIfTheDeviceChoiceChanged(reason: reason.rawValue)
        case .defaultOutput, .inputMuted, .processorOverload:
            return
        }
    }

    private func reopenIfTheDeviceChoiceChanged(reason: String) {
        guard running else { return }
        let picked = try? hardwareCatalog.resolveDeviceRoute(preferredInputDeviceID: preferredInputDeviceID)
        guard picked?.route.effectiveInputDeviceID != stream?.deviceRoute.effectiveInputDeviceID else { return }
        reopen(reason: reason)
    }

    private func noteDigitalSilence(_ isZero: Bool) {
        guard isZero else {
            digitalSilenceSince = nil
            return
        }
        let now = uptime()
        guard let since = digitalSilenceSince else {
            digitalSilenceSince = now
            return
        }
        if now - since >= Self.digitalSilenceLimit {
            digitalSilenceSince = nil
            // Later on the queue: a reopen closes the ring that the drain loop
            // reads now.
            queue.async { [weak self] in self?.reopenIfTheDeviceChoiceChanged(reason: "digital silence") }
        }
    }
}

extension MeetingMicCapture: MicrophoneStreamDelegate {
    func microphoneStream(_ stream: MicrophoneStream, didRead samples: UnsafeBufferPointer<Float>) -> Bool {
        guard stream === self.stream, let resampler else { return false }
        let isZero = samples.allSatisfy { $0 == 0 }
        if !isZero {
            reopensWithoutSound = 0
        }
        noteDigitalSilence(isZero)
        let block = resampler.process(samples)
        if !block.isEmpty {
            onSamples?(block)
        }
        return true
    }

    func microphoneStream(_ stream: MicrophoneStream, willFallBack cause: MicrophoneStream.FallbackCause) {
        switch cause {
        case let .startFailed(error):
            AppLogger.shared.log(.warning, "meeting microphone primary backend failed; trying the standard engine error=\(error.localizedDescription)")
        case .noFirstFrame:
            AppLogger.shared.log(.warning, "meeting microphone delivered no first frame; trying the standard engine")
        }
    }

    func microphoneStream(
        _ stream: MicrophoneStream,
        didStart plan: AudioCapturePlan,
        format: AudioCaptureFormat,
        fallback cause: MicrophoneStream.FallbackCause?
    ) throws {
        resampler = try MeetingResampler(inputSampleRate: format.sampleRate)
        openedAt = uptime()
        digitalSilenceSince = nil
        deviceMonitor.watch(deviceID: stream.inputDeviceID)
        AppLogger.shared.log(.info, "meeting microphone open input=\(stream.deviceRoute.inputTransport.rawValue) rate=\(format.sampleRate) backend=\(plan.backend.rawValue)")
    }

    func microphoneStreamConfigurationChanged(_ stream: MicrophoneStream) {
        guard stream === self.stream, running, uptime() - openedAt >= Self.settleTime else { return }
        reopen(reason: "configuration change")
    }

    func microphoneStream(_ stream: MicrophoneStream, deliveredNoAudio standardEngineError: Error?) {
        guard stream === self.stream, running else { return }
        guard let standardEngineError else {
            AppLogger.shared.log(.error, "meeting microphone delivered no audio on the standard engine")
            fail("The microphone delivered no audio.")
            return
        }
        fail(standardEngineError.localizedDescription)
    }
}
