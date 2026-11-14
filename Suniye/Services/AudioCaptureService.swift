import AudioToolbox
import CoreAudio
import Foundation
import QuartzCore

/// Shared configuration for the recording level meter. The capture service is the
/// authority on band granularity; the indicator fallback and tests must agree with it.
enum AudioLevelMeter {
    /// Number of frequency bands the level meter renders.
    static let bandCount = 22
    private static let gain: Float = 14

    /// Maps a block's RMS to the 0...1 level that the meters draw.
    static func level(rms: Float) -> Float {
        min(max(rms * gain, 0), 1)
    }
}

enum AudioCaptureServiceError: LocalizedError, Equatable {
    case noInputDevice
    case builtInMicrophoneOff
    case invalidInputFormat
    case failedToSelectInput(Int32)
    case ringBufferUnavailable
    case operationFailed(String, Int32)

    var errorDescription: String? {
        switch self {
        case .noInputDevice:
            return "No microphone is available."
        case .builtInMicrophoneOff:
            return "The built-in microphone is off while the lid is closed."
        case .invalidInputFormat:
            return "The selected microphone has an invalid audio format."
        case let .failedToSelectInput(status):
            return "Could not select the microphone (Core Audio \(status))."
        case .ringBufferUnavailable:
            return "Could not prepare the audio buffer."
        case let .operationFailed(operation, status):
            return "\(operation) failed (Core Audio \(status))."
        }
    }
}

protocol AudioCaptureServiceProtocol: AnyObject {
    var onEvent: ((AudioCaptureEvent) -> Void)? { get set }

    func startCapture(
        sessionID: UUID,
        preferredInputDeviceID: String?,
        echoCancellationEnabled: Bool
    ) async throws -> AudioCaptureSession
    func stopCapture(sessionID: UUID) async -> CapturedAudio
    func snapshotSamples(sessionID: UUID, maxDurationSeconds: Double) async -> AudioSampleSnapshot?
    func cancelCapture(sessionID: UUID, reason: AudioCaptureInterruption?) async
    func availableInputDevices() -> [AudioInputDevice]
    func routeSnapshot(preferredInputDeviceID: String?, echoCancellationEnabled: Bool) throws -> AudioRouteSnapshot
    func handleSystemSleep() async
    func handleSystemWake()
}

final class AudioCaptureService: AudioCaptureServiceProtocol, @unchecked Sendable {
    @Locked var onEvent: ((AudioCaptureEvent) -> Void)?

    private final class ActiveCapture {
        let id: UUID
        let stream: MicrophoneStream
        var route: AudioRouteSnapshot
        var samples: [Float] = []
        var interruption: AudioCaptureInterruption?
        var engineRestartCount = 0
        var smoothedLevels = Array(repeating: Float(0), count: AudioLevelMeter.bandCount)
        var lastLevelEmissionTime: CFTimeInterval = 0
        var pendingStop: CheckedContinuation<CapturedAudio, Never>?

        init(id: UUID, stream: MicrophoneStream) {
            self.id = id
            self.stream = stream
            route = stream.plan.snapshot()
        }
    }

    private let controlQueue = DispatchQueue(label: "dev.suniye.audio.capture", qos: .userInitiated)
    private let controlQueueKey = DispatchSpecificKey<Void>()
    private let deviceMonitor: AudioDeviceMonitorProtocol
    private let hardwareCatalog: AudioCaptureHardwareCatalogProtocol
    private let driverFactory: AudioCaptureDriverFactoryProtocol
    private let maximumDurationSeconds: Double
    private let firstFrameDeadline: DispatchTimeInterval
    private let maximumEngineRestarts = 2
    private let scheduleReleaseTail: (@escaping () -> Void) -> Void

    private var activeCapture: ActiveCapture?

    static let releaseTail: DispatchTimeInterval = .milliseconds(200)

    init(
        deviceMonitor: AudioDeviceMonitorProtocol = CoreAudioDeviceMonitor(),
        hardwareCatalog: AudioCaptureHardwareCatalogProtocol = CoreAudioCaptureHardwareCatalog(),
        driverFactory: AudioCaptureDriverFactoryProtocol = DefaultAudioCaptureDriverFactory(),
        maximumDurationSeconds: Double = 10 * 60,
        firstFrameDeadlineSeconds: Double = 1.5,
        scheduleReleaseTail: @escaping (@escaping () -> Void) -> Void = { endOfTail in
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + AudioCaptureService.releaseTail, execute: endOfTail)
        }
    ) {
        self.deviceMonitor = deviceMonitor
        self.hardwareCatalog = hardwareCatalog
        self.driverFactory = driverFactory
        self.maximumDurationSeconds = maximumDurationSeconds
        firstFrameDeadline = .nanoseconds(Int(firstFrameDeadlineSeconds * 1_000_000_000))
        self.scheduleReleaseTail = scheduleReleaseTail
        controlQueue.setSpecific(key: controlQueueKey, value: ())

        deviceMonitor.onChange = { [weak self] reason in
            self?.controlQueue.async {
                self?.handleDeviceChange(reason)
            }
        }
        deviceMonitor.start()
    }

    deinit {
        deviceMonitor.stop()
        let cleanup = {
            self.activeCapture?.stream.stop()
            self.activeCapture = nil
        }
        if DispatchQueue.getSpecific(key: controlQueueKey) != nil {
            cleanup()
        } else {
            controlQueue.sync(execute: cleanup)
        }
    }

    func startCapture(
        sessionID: UUID,
        preferredInputDeviceID: String?,
        echoCancellationEnabled: Bool
    ) async throws -> AudioCaptureSession {
        try await withCheckedThrowingContinuation { continuation in
            controlQueue.async {
                do {
                    self.discardActiveCapture()
                    let resolution = try self.hardwareCatalog.resolveDeviceRoute(
                        preferredInputDeviceID: preferredInputDeviceID
                    )
                    let stream = try MicrophoneStream(
                        queue: self.controlQueue,
                        driverFactory: self.driverFactory,
                        resolution: resolution,
                        echoCancellationEnabled: echoCancellationEnabled,
                        firstFrameDeadline: self.firstFrameDeadline
                    )
                    stream.delegate = self
                    let active = ActiveCapture(id: sessionID, stream: stream)
                    self.activeCapture = active
                    try stream.start()

                    self.deviceMonitor.watch(
                        deviceID: self.hardwareCatalog.deviceID(forUID: active.route.effectiveInputDeviceID)
                    )
                    AppLogger.shared.log(.info, "audio capture start session=\(sessionID.uuidString) \(active.route.privacySafeLogValue)")
                    continuation.resume(returning: AudioCaptureSession(id: sessionID, route: active.route))
                } catch {
                    self.discardActiveCapture()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Keeps recording for the release tail before it returns the audio: a
    /// shortcut often goes up while the last word is still being said.
    func stopCapture(sessionID: UUID) async -> CapturedAudio {
        await withCheckedContinuation { continuation in
            controlQueue.async {
                guard let active = self.activeCapture, active.id == sessionID, active.pendingStop == nil else {
                    continuation.resume(returning: CapturedAudio.interrupted(
                        sessionID: sessionID,
                        reason: .ioStoppedAbnormally
                    ))
                    return
                }
                guard active.interruption == nil else {
                    continuation.resume(returning: self.finalize(active: active, discard: false))
                    return
                }
                active.pendingStop = continuation
                active.stream.stopWatchingFirstFrame()
                self.scheduleReleaseTail { [weak self, weak active] in
                    self?.controlQueue.async {
                        guard let self, let active, self.activeCapture === active else { return }
                        _ = self.finalize(active: active, discard: false)
                    }
                }
            }
        }
    }

    /// Copies the most recent `maxDurationSeconds` of accumulated samples without
    /// disturbing the ongoing capture. Runs on the control queue, so it is
    /// consistent with the drain timer that appends samples.
    func snapshotSamples(sessionID: UUID, maxDurationSeconds: Double) async -> AudioSampleSnapshot? {
        await withCheckedContinuation { continuation in
            controlQueue.async {
                guard let active = self.activeCapture, active.id == sessionID, active.interruption == nil else {
                    continuation.resume(returning: nil)
                    return
                }
                let sampleRate = max(8_000, active.route.inputSampleRate)
                let maxCount = Int(Double(sampleRate) * max(0, maxDurationSeconds))
                continuation.resume(returning: AudioSampleSnapshot(
                    samples: Array(active.samples.suffix(maxCount)),
                    sampleRate: sampleRate
                ))
            }
        }
    }

    func cancelCapture(sessionID: UUID, reason: AudioCaptureInterruption?) async {
        await withCheckedContinuation { continuation in
            controlQueue.async {
                guard let active = self.activeCapture, active.id == sessionID else {
                    continuation.resume()
                    return
                }
                if let reason {
                    active.interruption = reason
                }
                _ = self.finalize(active: active, discard: true)
                continuation.resume()
            }
        }
    }

    func availableInputDevices() -> [AudioInputDevice] {
        hardwareCatalog.availableInputDevices()
    }

    func routeSnapshot(preferredInputDeviceID: String?, echoCancellationEnabled: Bool) throws -> AudioRouteSnapshot {
        let resolution = try hardwareCatalog.resolveDeviceRoute(preferredInputDeviceID: preferredInputDeviceID)
        return AudioCapturePolicy.primaryPlan(
            for: resolution.route,
            echoCancellationEnabled: echoCancellationEnabled
        ).snapshot()
    }

    func handleSystemSleep() async {
        await withCheckedContinuation { continuation in
            controlQueue.async {
                self.interruptActiveCapture(.systemSleep)
                continuation.resume()
            }
        }
    }

    func handleSystemWake() {
        controlQueue.async {
            self.deviceMonitor.stop()
            self.deviceMonitor.start()
            self.onEvent?(.devicesChanged(self.hardwareCatalog.availableInputDevices()))
        }
    }

    /// Handles an `AVAudioEngineConfigurationChange` reported by an active engine driver.
    ///
    /// The engine emits a benign configuration change immediately after `start()` (e.g. just after the
    /// standardEngine fallback re-acquires the input device). Treating that as fatal is what surfaced
    /// "Microphone changed. Try again." with no audio (KIS-141). We only interrupt when the input
    /// device actually changed; otherwise we restart the engine in place (up to `maximumEngineRestarts`
    /// times) so capture continues, because the engine stops itself on a configuration change. Beyond
    /// that cap we surface the interruption.
    private func handleEngineConfigurationChange(_ active: ActiveCapture) {
        guard activeCapture === active, active.interruption == nil else { return }

        if let interruption = lostInputInterruption(for: active, devices: hardwareCatalog.availableInputDevices()) {
            interruptActiveCapture(interruption)
            return
        }

        guard active.engineRestartCount < maximumEngineRestarts else {
            AppLogger.shared.log(
                .error,
                "audio engine restart cap reached; giving up session=\(active.id.uuidString) attempts=\(active.engineRestartCount) \(active.route.privacySafeLogValue)"
            )
            interruptActiveCapture(.engineConfigurationChanged)
            return
        }
        active.engineRestartCount += 1
        do {
            try active.stream.restart()
            AppLogger.shared.log(
                .warning,
                "audio engine reconfigured; restarted in place session=\(active.id.uuidString) attempt=\(active.engineRestartCount) \(active.route.privacySafeLogValue)"
            )
        } catch {
            AppLogger.shared.log(
                .error,
                "audio engine restart failed session=\(active.id.uuidString) attempt=\(active.engineRestartCount) error=\(error.localizedDescription) \(active.route.privacySafeLogValue)"
            )
            interruptActiveCapture(.engineConfigurationChanged)
        }
    }

    private func accept(_ values: UnsafeBufferPointer<Float>, into active: ActiveCapture) -> Bool {
        let remainingCapacity = max(0, maximumSampleCount(for: active) - active.samples.count)
        let accepted = min(values.count, remainingCapacity)
        if accepted > 0 {
            let acceptedValues = UnsafeBufferPointer(rebasing: values[0 ..< accepted])
            active.samples.append(contentsOf: acceptedValues)
            updateLevels(active: active, values: acceptedValues)
        }
        if accepted < values.count || active.samples.count >= maximumSampleCount(for: active) {
            interruptActiveCapture(.maximumDurationReached)
            return false
        }
        return true
    }

    private func updateLevels(active: ActiveCapture, values: UnsafeBufferPointer<Float>) {
        guard !values.isEmpty else { return }
        let chunkSize = max(1, values.count / active.smoothedLevels.count)
        var next = Array(repeating: Float(0), count: active.smoothedLevels.count)
        for index in next.indices {
            let start = index * chunkSize
            let end = index == next.count - 1 ? values.count : min(values.count, start + chunkSize)
            guard start < end else { continue }
            var sum: Double = 0
            for sampleIndex in start ..< end {
                let value = Double(values[sampleIndex])
                sum += value * value
            }
            let rms = Float((sum / Double(end - start)).squareRoot())
            next[index] = AudioLevelMeter.level(rms: rms)
        }
        for index in next.indices {
            // Weight the freshly measured level more heavily so the meter tracks
            // speech transients quickly instead of lagging behind.
            active.smoothedLevels[index] = active.smoothedLevels[index] * 0.42 + next[index] * 0.58
        }
        let now = CACurrentMediaTime()
        guard now - active.lastLevelEmissionTime >= 1.0 / 60.0 else { return }
        active.lastLevelEmissionTime = now
        onEvent?(.levelsUpdated(sessionID: active.id, levels: active.smoothedLevels))
    }

    private func maximumSampleCount(for active: ActiveCapture) -> Int {
        Int(Double(max(8_000, active.route.inputSampleRate)) * maximumDurationSeconds)
    }

    private func handleDeviceChange(_ reason: AudioDeviceChangeReason) {
        if reason == .serviceRestarted {
            deviceMonitor.stop()
            deviceMonitor.start()
        }
        let devices = hardwareCatalog.availableInputDevices()
        onEvent?(.devicesChanged(devices))

        guard let active else { return }
        let interruption: AudioCaptureInterruption?
        switch reason {
        case .defaultInput:
            interruption = nil
        case .defaultOutput:
            interruption = active.route.backend == .voiceProcessingEngine ? .deviceChanged : nil
        case .devices, .selectedDeviceAlive:
            interruption = lostInputInterruption(for: active, devices: devices)
        case .selectedDeviceFormat:
            interruption = .formatChanged
        case .selectedDeviceChanged:
            interruption = .deviceChanged
        case .serviceRestarted:
            interruption = .serviceRestarted
        case .inputMuted:
            interruption = hardwareCatalog.processInputIsMuted() == true ? .inputMuted : nil
        case .ioStoppedAbnormally:
            interruption = .ioStoppedAbnormally
        case .processorOverload:
            AppLogger.shared.log(.warning, "audio processor overload session=\(active.id.uuidString) \(active.route.privacySafeLogValue)")
            interruption = nil
        }
        if let interruption {
            interruptActiveCapture(interruption)
        }
    }

    private var active: ActiveCapture? {
        activeCapture
    }

    /// A dictation keeps the microphone it started with, even when the default
    /// input changes or a better one connects; the next dictation picks again.
    /// It stops only when its own microphone can no longer record.
    private func lostInputInterruption(
        for active: ActiveCapture,
        devices: [AudioInputDevice]
    ) -> AudioCaptureInterruption? {
        devices.contains { $0.id == active.route.effectiveInputDeviceID && $0.isAvailable }
            ? nil
            : .deviceUnavailable
    }

    private func interruptActiveCapture(_ reason: AudioCaptureInterruption) {
        guard let active = activeCapture, active.interruption == nil else {
            return
        }
        if active.pendingStop != nil {
            AppLogger.shared.log(.info, "audio capture release tail ended early session=\(active.id.uuidString) reason=\(reason.rawValue)")
            _ = finalize(active: active, discard: false)
            return
        }
        active.interruption = reason
        active.stream.stop()
        active.stream.drain()
        AppLogger.shared.log(.warning, "audio capture interrupted session=\(active.id.uuidString) reason=\(reason.rawValue) \(active.route.privacySafeLogValue)")
        onEvent?(.interrupted(sessionID: active.id, reason: reason))
    }

    private func finalize(active: ActiveCapture, discard: Bool) -> CapturedAudio {
        // Taken first: the drain below can reach the length limit and come back
        // through interruptActiveCapture while this finalize still runs.
        let pendingStop = active.pendingStop
        active.pendingStop = nil
        active.stream.stop()
        active.stream.drain()
        let samples = discard ? [] : active.samples
        let captured: CapturedAudio
        if let interruption = active.interruption, interruption != .maximumDurationReached {
            captured = .interrupted(sessionID: active.id, reason: interruption, route: active.route)
        } else {
            captured = CapturedAudio(
                sessionID: active.id,
                samples: samples,
                sampleRate: active.route.inputSampleRate,
                route: active.route,
                droppedSampleCount: active.stream.droppedSampleCount
            )
        }
        activeCapture = nil
        deviceMonitor.watch(deviceID: nil)
        onEvent?(.levelsUpdated(sessionID: active.id, levels: Array(repeating: 0, count: AudioLevelMeter.bandCount)))
        logFinalCapture(captured, discarded: discard)
        scheduleReleaseCheck(sessionID: active.id)
        pendingStop?.resume(returning: captured)
        return captured
    }

    private func discardActiveCapture() {
        guard let active = activeCapture else {
            return
        }
        _ = finalize(active: active, discard: true)
    }

    private func scheduleReleaseCheck(sessionID: UUID) {
        controlQueue.asyncAfter(deadline: .now() + .milliseconds(300)) {
            let released = self.hardwareCatalog.processIsRunningInput().map { !$0 }
            AppLogger.shared.log(
                released == false ? .warning : .info,
                "audio input release session=\(sessionID.uuidString) released=\(released.map(String.init) ?? "unknown")"
            )
        }
    }

    private func logFinalCapture(_ captured: CapturedAudio, discarded: Bool) {
        let health = captured.health
        AppLogger.shared.log(
            .info,
            String(
                format: "audio capture stop session=%@ outcome=%@ discarded=%@ frames=%d sr=%d duration=%.2fs rms=%.5f peak=%.5f clipped=%d invalid=%d dropped=%llu",
                captured.sessionID?.uuidString ?? "unknown",
                String(describing: captured.outcome),
                String(discarded),
                health.frameCount,
                captured.sampleRate,
                health.durationSeconds,
                health.rms,
                health.peak,
                health.clippedSampleCount,
                health.nonFiniteSampleCount,
                health.droppedSampleCount
            )
        )
    }
}

extension AudioCaptureService: MicrophoneStreamDelegate {
    func microphoneStream(_ stream: MicrophoneStream, didRead samples: UnsafeBufferPointer<Float>) -> Bool {
        guard let active = activeCapture(for: stream) else { return false }
        return accept(samples, into: active)
    }

    func microphoneStream(_ stream: MicrophoneStream, willFallBack cause: MicrophoneStream.FallbackCause) {}

    func microphoneStream(
        _ stream: MicrophoneStream,
        didStart plan: AudioCapturePlan,
        format: AudioCaptureFormat,
        fallback cause: MicrophoneStream.FallbackCause?
    ) {
        guard let active = activeCapture(for: stream) else { return }
        active.route = plan.snapshot(format: format)
        guard let cause else { return }
        let reason: Error
        switch cause {
        case let .startFailed(error):
            reason = error
        case .noFirstFrame:
            reason = AudioCaptureServiceError.operationFailed("No first audio buffer", kAudio_ParamError)
        }
        onEvent?(.routeChanged(sessionID: active.id, route: active.route))
        AppLogger.shared.log(.warning, "audio backend fallback session=\(active.id.uuidString) reason=\(reason.localizedDescription) \(active.route.privacySafeLogValue)")
    }

    func microphoneStreamConfigurationChanged(_ stream: MicrophoneStream) {
        guard let active = activeCapture(for: stream) else { return }
        handleEngineConfigurationChange(active)
    }

    func microphoneStream(_ stream: MicrophoneStream, deliveredNoAudio standardEngineError: Error?) {
        guard activeCapture(for: stream) != nil else { return }
        interruptActiveCapture(.noAudioArriving)
    }

    private func activeCapture(for stream: MicrophoneStream) -> ActiveCapture? {
        guard let active = activeCapture, active.stream === stream else { return nil }
        return active
    }
}
