import AudioToolbox
import CoreAudio
import Foundation
import QuartzCore

enum AudioCaptureServiceError: LocalizedError, Equatable {
    case noInputDevice
    case preferredDeviceUnavailable
    case invalidInputFormat
    case failedToSelectInput(Int32)
    case ringBufferUnavailable
    case operationFailed(String, Int32)

    var errorDescription: String? {
        switch self {
        case .noInputDevice:
            return "No microphone is available."
        case .preferredDeviceUnavailable:
            return "The selected microphone is unavailable."
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
    func cancelCapture(sessionID: UUID, reason: AudioCaptureInterruption?) async
    func availableInputDevices() -> [AudioInputDevice]
    func routeSnapshot(preferredInputDeviceID: String?, echoCancellationEnabled: Bool) throws -> AudioRouteSnapshot
    func handleSystemSleep() async
    func handleSystemWake()
}

final class AudioCaptureService: AudioCaptureServiceProtocol, @unchecked Sendable {
    var onEvent: ((AudioCaptureEvent) -> Void)? {
        get { withCallbackLock { eventCallback } }
        set { withCallbackLock { eventCallback = newValue } }
    }

    private final class ActiveCapture {
        let id: UUID
        let preferredInputDeviceID: String?
        let requestedEchoCancellation: Bool
        let inputDeviceID: AudioObjectID
        let deviceRoute: AudioDeviceRoute
        let ring: OpaquePointer
        var route: AudioRouteSnapshot
        var driver: AudioCaptureDriver?
        var samples: [Float] = []
        var interruption: AudioCaptureInterruption?
        var fallbackAttempted = false
        var firstFrameSeen = false
        var smoothedLevels = Array(repeating: Float(0), count: 12)
        var lastLevelEmissionTime: CFTimeInterval = 0
        var drainTimer: DispatchSourceTimer?

        init(
            id: UUID,
            preferredInputDeviceID: String?,
            requestedEchoCancellation: Bool,
            inputDeviceID: AudioObjectID,
            deviceRoute: AudioDeviceRoute,
            route: AudioRouteSnapshot,
            ring: OpaquePointer
        ) {
            self.id = id
            self.preferredInputDeviceID = preferredInputDeviceID
            self.requestedEchoCancellation = requestedEchoCancellation
            self.inputDeviceID = inputDeviceID
            self.deviceRoute = deviceRoute
            self.route = route
            self.ring = ring
        }

        deinit {
            SuniyeAudioRingBufferDestroy(ring)
        }
    }

    private let controlQueue = DispatchQueue(label: "dev.suniye.audio.capture", qos: .userInitiated)
    private let controlQueueKey = DispatchSpecificKey<Void>()
    private let deviceMonitor: AudioDeviceMonitorProtocol
    private let hardwareCatalog: AudioCaptureHardwareCatalogProtocol
    private let driverFactory: AudioCaptureDriverFactoryProtocol
    private let callbackLock = NSLock()
    private let ringCapacity = 1_048_576
    private let drainCapacity = 32_768
    private let maximumDurationSeconds: Double
    private let firstFrameDeadlineSeconds: Double
    private let drainScratch: UnsafeMutablePointer<Float>

    private var eventCallback: ((AudioCaptureEvent) -> Void)?
    private var activeCapture: ActiveCapture?

    init(
        deviceMonitor: AudioDeviceMonitorProtocol = CoreAudioDeviceMonitor(),
        hardwareCatalog: AudioCaptureHardwareCatalogProtocol = CoreAudioCaptureHardwareCatalog(),
        driverFactory: AudioCaptureDriverFactoryProtocol = DefaultAudioCaptureDriverFactory(),
        maximumDurationSeconds: Double = 10 * 60,
        firstFrameDeadlineSeconds: Double = 1.5
    ) {
        self.deviceMonitor = deviceMonitor
        self.hardwareCatalog = hardwareCatalog
        self.driverFactory = driverFactory
        self.maximumDurationSeconds = maximumDurationSeconds
        self.firstFrameDeadlineSeconds = firstFrameDeadlineSeconds
        self.drainScratch = .allocate(capacity: drainCapacity)
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
            self.stopHardware(for: self.activeCapture)
            self.activeCapture?.drainTimer?.cancel()
            self.activeCapture = nil
        }
        if DispatchQueue.getSpecific(key: controlQueueKey) != nil {
            cleanup()
        } else {
            controlQueue.sync(execute: cleanup)
        }
        drainScratch.deallocate()
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
                    let plan = AudioCapturePolicy.primaryPlan(
                        for: resolution.route,
                        echoCancellationEnabled: echoCancellationEnabled
                    )
                    guard let ring = SuniyeAudioRingBufferCreate(self.ringCapacity) else {
                        throw AudioCaptureServiceError.ringBufferUnavailable
                    }

                    let active = ActiveCapture(
                        id: sessionID,
                        preferredInputDeviceID: preferredInputDeviceID,
                        requestedEchoCancellation: echoCancellationEnabled,
                        inputDeviceID: resolution.inputDeviceID,
                        deviceRoute: resolution.route,
                        route: plan.snapshot(),
                        ring: ring
                    )
                    self.activeCapture = active
                    self.startDrainTimer(for: active)

                    do {
                        try self.startDriver(for: plan, active: active)
                    } catch {
                        try self.fallbackToStandardEngine(active: active, originalError: error)
                    }

                    self.deviceMonitor.watch(
                        deviceID: self.hardwareCatalog.deviceID(forUID: active.route.effectiveInputDeviceID)
                    )
                    self.scheduleFirstFrameDeadline(for: active)
                    AppLogger.shared.log(.info, "audio capture start session=\(sessionID.uuidString) \(active.route.privacySafeLogValue)")
                    continuation.resume(returning: AudioCaptureSession(id: sessionID, route: active.route))
                } catch {
                    self.discardActiveCapture()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stopCapture(sessionID: UUID) async -> CapturedAudio {
        await withCheckedContinuation { continuation in
            controlQueue.async {
                guard let active = self.activeCapture, active.id == sessionID else {
                    continuation.resume(returning: CapturedAudio.interrupted(
                        sessionID: sessionID,
                        reason: .ioStoppedAbnormally
                    ))
                    return
                }
                let captured = self.finalize(active: active, discard: false)
                continuation.resume(returning: captured)
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

    private func fallbackToStandardEngine(active: ActiveCapture, originalError: Error) throws {
        stopHardware(for: active)
        active.fallbackAttempted = true
        SuniyeAudioRingBufferReset(active.ring)
        let plan = AudioCapturePolicy.fallbackPlan(
            for: active.deviceRoute,
            echoCancellationEnabled: active.requestedEchoCancellation,
            reason: .backendStartFailed
        )
        try startDriver(for: plan, active: active)
        onEvent?(.routeChanged(sessionID: active.id, route: active.route))
        AppLogger.shared.log(.warning, "audio backend fallback session=\(active.id.uuidString) reason=\(originalError.localizedDescription) \(active.route.privacySafeLogValue)")
    }

    private func startDriver(for plan: AudioCapturePlan, active: ActiveCapture) throws {
        let started = try driverFactory.startDriver(
            for: plan,
            inputDeviceID: active.inputDeviceID,
            ring: active.ring
        ) { [weak self, weak active] in
            self?.controlQueue.async {
                guard let self, let active, self.activeCapture === active else { return }
                self.interruptActiveCapture(.engineConfigurationChanged)
            }
        }
        active.driver = started.driver
        active.route = plan.snapshot(format: started.format)
    }

    private func startDrainTimer(for active: ActiveCapture) {
        let timer = DispatchSource.makeTimerSource(queue: controlQueue)
        timer.schedule(deadline: .now() + .milliseconds(20), repeating: .milliseconds(20), leeway: .milliseconds(4))
        timer.setEventHandler { [weak self, weak active] in
            guard let self, let active, self.activeCapture === active else { return }
            self.drain(active)
        }
        active.drainTimer = timer
        timer.resume()
    }

    private func drain(_ active: ActiveCapture) {
        var count = SuniyeAudioRingBufferRead(active.ring, drainScratch, drainCapacity)
        while count > 0 {
            active.firstFrameSeen = true
            let remainingCapacity = max(0, maximumSampleCount(for: active) - active.samples.count)
            let accepted = min(count, remainingCapacity)
            if accepted > 0 {
                active.samples.append(contentsOf: UnsafeBufferPointer(start: drainScratch, count: accepted))
                updateLevels(active: active, values: UnsafeBufferPointer(start: drainScratch, count: accepted))
            }
            if accepted < count || active.samples.count >= maximumSampleCount(for: active) {
                interruptActiveCapture(.maximumDurationReached)
                return
            }
            count = SuniyeAudioRingBufferRead(active.ring, drainScratch, drainCapacity)
        }
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
            next[index] = min(max(rms * 12, 0), 1)
        }
        for index in next.indices {
            active.smoothedLevels[index] = active.smoothedLevels[index] * 0.62 + next[index] * 0.38
        }
        let now = CACurrentMediaTime()
        guard now - active.lastLevelEmissionTime >= 1.0 / 30.0 else { return }
        active.lastLevelEmissionTime = now
        onEvent?(.levelsUpdated(sessionID: active.id, levels: active.smoothedLevels))
    }

    private func maximumSampleCount(for active: ActiveCapture) -> Int {
        Int(Double(max(8_000, active.route.inputSampleRate)) * maximumDurationSeconds)
    }

    private func scheduleFirstFrameDeadline(for active: ActiveCapture) {
        controlQueue.asyncAfter(deadline: .now() + firstFrameDeadlineSeconds) { [weak self, weak active] in
            guard let self,
                  let active,
                  self.activeCapture === active,
                  active.interruption == nil,
                  !active.firstFrameSeen else {
                return
            }
            if active.route.backend != .standardEngine, !active.fallbackAttempted {
                do {
                    try self.fallbackToStandardEngine(
                        active: active,
                        originalError: AudioCaptureServiceError.operationFailed("No first audio buffer", kAudio_ParamError)
                    )
                    self.scheduleFirstFrameDeadline(for: active)
                } catch {
                    self.interruptActiveCapture(.noAudioArriving)
                }
            } else {
                self.interruptActiveCapture(.noAudioArriving)
            }
        }
    }

    private func handleDeviceChange(_ reason: AudioDeviceChangeReason) {
        if reason == .serviceRestarted {
            deviceMonitor.stop()
            deviceMonitor.start()
        }
        onEvent?(.devicesChanged(hardwareCatalog.availableInputDevices()))

        guard let active else { return }
        let interruption: AudioCaptureInterruption?
        switch reason {
        case .defaultInput:
            interruption = active.preferredInputDeviceID == nil ? .deviceChanged : nil
        case .defaultOutput:
            interruption = active.route.backend == .voiceProcessingEngine ? .deviceChanged : nil
        case .devices, .selectedDeviceAlive:
            interruption = resolvedRouteChangeInterruption(for: active)
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

    private func resolvedRouteChangeInterruption(for active: ActiveCapture) -> AudioCaptureInterruption? {
        do {
            let resolution = try hardwareCatalog.resolveDeviceRoute(
                preferredInputDeviceID: active.preferredInputDeviceID
            )
            return resolution.route.effectiveInputDeviceID == active.route.effectiveInputDeviceID
                ? nil
                : .deviceChanged
        } catch {
            return .deviceUnavailable
        }
    }

    private func interruptActiveCapture(_ reason: AudioCaptureInterruption) {
        guard let active = activeCapture, active.interruption == nil else {
            return
        }
        active.interruption = reason
        stopHardware(for: active)
        drain(active)
        active.drainTimer?.cancel()
        active.drainTimer = nil
        AppLogger.shared.log(.warning, "audio capture interrupted session=\(active.id.uuidString) reason=\(reason.rawValue) \(active.route.privacySafeLogValue)")
        onEvent?(.interrupted(sessionID: active.id, reason: reason))
    }

    private func finalize(active: ActiveCapture, discard: Bool) -> CapturedAudio {
        stopHardware(for: active)
        drain(active)
        active.drainTimer?.cancel()
        active.drainTimer = nil
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
                droppedSampleCount: SuniyeAudioRingBufferDroppedSamples(active.ring)
            )
        }
        activeCapture = nil
        deviceMonitor.watch(deviceID: nil)
        onEvent?(.levelsUpdated(sessionID: active.id, levels: Array(repeating: 0, count: 12)))
        logFinalCapture(captured, discarded: discard)
        scheduleReleaseCheck(sessionID: active.id)
        return captured
    }

    private func discardActiveCapture() {
        guard let active = activeCapture else {
            return
        }
        _ = finalize(active: active, discard: true)
    }

    private func stopHardware(for active: ActiveCapture?) {
        active?.driver?.stop()
        active?.driver = nil
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

    private func withCallbackLock<T>(_ work: () -> T) -> T {
        callbackLock.lock()
        defer { callbackLock.unlock() }
        return work()
    }
}
