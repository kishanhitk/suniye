import AudioToolbox
import CoreAudio
import Foundation

enum MeetingAudioSourceEvent: Equatable, Sendable {
    /// The microphone moved to another input; the recording goes on.
    case inputChanged(deviceName: String)
    /// The source stopped and could not start again.
    case failed(String)
}

/// One meeting track. Blocks arrive as 16 kHz mono floats on a background
/// queue. A block holds all the audio that the source had when it handed the
/// block over: the recorder places each block by the time it arrives.
protocol MeetingAudioSource: AnyObject {
    var onSamples: (([Float]) -> Void)? { get set }
    var onEvent: ((MeetingAudioSourceEvent) -> Void)? { get set }
    func start() throws
    func stop()
}

/// The meeting's microphone track. It runs beside dictation's
/// `AudioCaptureService` on the same drivers and the same device choice, so
/// the dictation path does not change. Unlike a dictation, a meeting outlives
/// a device change: it reopens the input that the device choice picks, with
/// the microphone that the user picked when the meeting started.
final class MeetingMicCapture: MeetingAudioSource, @unchecked Sendable {
    var onSamples: (([Float]) -> Void)? {
        get { withCallbackLock { sampleCallback } }
        set { withCallbackLock { sampleCallback = newValue } }
    }

    var onEvent: ((MeetingAudioSourceEvent) -> Void)? {
        get { withCallbackLock { eventCallback } }
        set { withCallbackLock { eventCallback = newValue } }
    }

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
    private let callbackLock = NSLock()
    private let ringCapacity = 1_048_576
    private let drainCapacity = 32_768
    private let drainScratch: UnsafeMutablePointer<Float>

    private var sampleCallback: (([Float]) -> Void)?
    private var eventCallback: ((MeetingAudioSourceEvent) -> Void)?
    private var running = false
    private var ring: OpaquePointer?
    private var driver: AudioCaptureDriver?
    private var resampler: MeetingResampler?
    private var drainTimer: DispatchSourceTimer?
    private var currentRoute: AudioDeviceRoute?
    private var receivedFrame = false
    private var openGeneration = 0
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
        drainScratch = .allocate(capacity: drainCapacity)
        queue.setSpecific(key: queueKey, value: ())
    }

    deinit {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            closeInput()
        } else {
            queue.sync { closeInput() }
        }
        drainScratch.deallocate()
    }

    func start() throws {
        try queue.sync {
            guard !running else { return }
            reopensWithoutSound = 0
            try openInput(fallback: false)
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
            drainRing()
            if let tail = resampler?.flush(), !tail.isEmpty {
                onSamples?(tail)
            }
            closeInput()
        }
    }

    // MARK: - Input lifecycle (on `queue`)

    private func openInput(fallback: Bool) throws {
        let resolution = try hardwareCatalog.resolveDeviceRoute(preferredInputDeviceID: preferredInputDeviceID)
        let plan = fallback
            ? AudioCapturePolicy.fallbackPlan(for: resolution.route, echoCancellationEnabled: false, reason: .backendStartFailed)
            : AudioCapturePolicy.primaryPlan(for: resolution.route, echoCancellationEnabled: false)
        guard let ring = SuniyeAudioRingBufferCreate(ringCapacity) else {
            throw AudioCaptureServiceError.ringBufferUnavailable
        }
        openGeneration += 1
        let generation = openGeneration
        let started: AudioCaptureDriverStart
        do {
            started = try driverFactory.startDriver(for: plan, inputDeviceID: resolution.inputDeviceID, ring: ring) { [weak self] in
                self?.queue.async { self?.handleConfigurationChange(generation: generation) }
            }
        } catch {
            SuniyeAudioRingBufferDestroy(ring)
            guard !fallback else { throw error }
            AppLogger.shared.log(.warning, "meeting microphone primary backend failed; trying the standard engine error=\(error.localizedDescription)")
            try openInput(fallback: true)
            return
        }
        do {
            resampler = try MeetingResampler(inputSampleRate: started.format.sampleRate)
        } catch {
            started.driver.stop()
            SuniyeAudioRingBufferDestroy(ring)
            throw error
        }
        self.ring = ring
        driver = started.driver
        currentRoute = resolution.route
        receivedFrame = false
        openedAt = uptime()
        digitalSilenceSince = nil
        deviceMonitor.watch(deviceID: resolution.inputDeviceID)
        startDrainTimer()
        scheduleFirstFrameCheck(generation: generation, fallback: fallback)
        AppLogger.shared.log(.info, "meeting microphone open input=\(resolution.route.inputTransport.rawValue) rate=\(started.format.sampleRate) backend=\(plan.backend.rawValue)")
    }

    private func closeInput() {
        drainTimer?.cancel()
        drainTimer = nil
        driver?.stop()
        driver = nil
        if let ring {
            SuniyeAudioRingBufferDestroy(ring)
        }
        ring = nil
        resampler = nil
    }

    private func reopen(reason: String) {
        guard running else { return }
        reopensWithoutSound += 1
        guard reopensWithoutSound <= Self.maximumReopens else {
            fail("The microphone kept failing (\(reason)).")
            return
        }
        let previousName = currentRoute?.effectiveInputName
        drainRing()
        closeInput()
        do {
            try openInput(fallback: false)
            AppLogger.shared.log(.info, "meeting microphone reopened reason=\(reason)")
            if let name = currentRoute?.effectiveInputName, name != previousName {
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

    private func handleConfigurationChange(generation: Int) {
        guard running, generation == openGeneration, uptime() - openedAt >= Self.settleTime else { return }
        reopen(reason: "configuration change")
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
        guard picked?.route.effectiveInputDeviceID != currentRoute?.effectiveInputDeviceID else { return }
        reopen(reason: reason)
    }

    private func scheduleFirstFrameCheck(generation: Int, fallback: Bool) {
        queue.asyncAfter(deadline: .now() + firstFrameDeadline) { [weak self] in
            guard let self, self.running, generation == self.openGeneration, !self.receivedFrame else { return }
            guard !fallback else {
                AppLogger.shared.log(.error, "meeting microphone delivered no audio on the standard engine")
                self.fail("The microphone delivered no audio.")
                return
            }
            AppLogger.shared.log(.warning, "meeting microphone delivered no first frame; trying the standard engine")
            self.closeInput()
            do {
                try self.openInput(fallback: true)
            } catch {
                self.fail(error.localizedDescription)
            }
        }
    }

    // MARK: - Drain (on `queue`)

    private func startDrainTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(20), repeating: .milliseconds(20), leeway: .milliseconds(5))
        timer.setEventHandler { [weak self] in self?.drainRing() }
        drainTimer = timer
        timer.resume()
    }

    private func drainRing() {
        guard let ring, let resampler else { return }
        var drained: [Float] = []
        var count = SuniyeAudioRingBufferRead(ring, drainScratch, drainCapacity)
        while count > 0 {
            receivedFrame = true
            let raw = UnsafeBufferPointer(start: drainScratch, count: count)
            let isZero = raw.allSatisfy { $0 == 0 }
            if !isZero {
                reopensWithoutSound = 0
            }
            noteDigitalSilence(isZero)
            drained += resampler.process(raw)
            count = SuniyeAudioRingBufferRead(ring, drainScratch, drainCapacity)
        }
        if !drained.isEmpty {
            onSamples?(drained)
        }
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

    private func withCallbackLock<T>(_ work: () -> T) -> T {
        callbackLock.lock()
        defer { callbackLock.unlock() }
        return work()
    }
}
