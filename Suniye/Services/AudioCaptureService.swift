import AudioToolbox
import AVFoundation
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
    var onLevelsUpdate: ((UUID, [Float]) -> Void)? { get set }
    var onDevicesChanged: (([AudioInputDevice]) -> Void)? { get set }
    var onRouteChanged: ((UUID, AudioRouteSnapshot) -> Void)? { get set }
    var onCaptureInterrupted: ((UUID, AudioCaptureInterruption) -> Void)? { get set }

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

private func audioCaptureHALInputCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    let context = Unmanaged<HALInputCallbackContext>.fromOpaque(inRefCon).takeUnretainedValue()
    return context.render(
        ioActionFlags: ioActionFlags,
        inTimeStamp: inTimeStamp,
        inNumberFrames: inNumberFrames,
        inBusNumber: inBusNumber
    )
}

private final class HALInputCallbackContext {
    let unit: AudioUnit
    let ring: OpaquePointer
    let scratch: UnsafeMutablePointer<Float>
    let scratchCapacity: Int

    init(unit: AudioUnit, ring: OpaquePointer, scratchCapacity: Int) {
        self.unit = unit
        self.ring = ring
        self.scratchCapacity = scratchCapacity
        self.scratch = .allocate(capacity: scratchCapacity)
    }

    deinit {
        scratch.deallocate()
    }

    func render(
        ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        inTimeStamp: UnsafePointer<AudioTimeStamp>,
        inNumberFrames: UInt32,
        inBusNumber: UInt32
    ) -> OSStatus {
        guard Int(inNumberFrames) <= scratchCapacity else {
            return kAudio_ParamError
        }

        let buffer = AudioBuffer(
            mNumberChannels: 1,
            mDataByteSize: inNumberFrames * UInt32(MemoryLayout<Float>.size),
            mData: scratch
        )
        var list = AudioBufferList(mNumberBuffers: 1, mBuffers: buffer)
        let status = AudioUnitRender(
            unit,
            ioActionFlags,
            inTimeStamp,
            inBusNumber,
            inNumberFrames,
            &list
        )
        guard status == noErr else {
            return status
        }
        SuniyeAudioRingBufferWrite(ring, scratch, Int(inNumberFrames))
        return noErr
    }
}

final class AudioCaptureService: AudioCaptureServiceProtocol, @unchecked Sendable {
    var onLevelsUpdate: ((UUID, [Float]) -> Void)? {
        get { withCallbackLock { levelsCallback } }
        set { withCallbackLock { levelsCallback = newValue } }
    }
    var onDevicesChanged: (([AudioInputDevice]) -> Void)? {
        get { withCallbackLock { devicesChangedCallback } }
        set { withCallbackLock { devicesChangedCallback = newValue } }
    }
    var onRouteChanged: ((UUID, AudioRouteSnapshot) -> Void)? {
        get { withCallbackLock { routeChangedCallback } }
        set { withCallbackLock { routeChangedCallback = newValue } }
    }
    var onCaptureInterrupted: ((UUID, AudioCaptureInterruption) -> Void)? {
        get { withCallbackLock { captureInterruptedCallback } }
        set { withCallbackLock { captureInterruptedCallback = newValue } }
    }

    private final class ActiveCapture {
        let id: UUID
        let preferredInputDeviceID: String?
        let requestedEchoCancellation: Bool
        let ring: OpaquePointer
        var route: AudioRouteSnapshot
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
            route: AudioRouteSnapshot,
            ring: OpaquePointer
        ) {
            self.id = id
            self.preferredInputDeviceID = preferredInputDeviceID
            self.requestedEchoCancellation = requestedEchoCancellation
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
    private let callbackLock = NSLock()
    private let ringCapacity = 1_048_576
    private let drainCapacity = 32_768
    private let maximumDurationSeconds: Double
    private let firstFrameDeadlineSeconds: Double
    private let drainScratch: UnsafeMutablePointer<Float>

    private var levelsCallback: ((UUID, [Float]) -> Void)?
    private var devicesChangedCallback: (([AudioInputDevice]) -> Void)?
    private var routeChangedCallback: ((UUID, AudioRouteSnapshot) -> Void)?
    private var captureInterruptedCallback: ((UUID, AudioCaptureInterruption) -> Void)?
    private var activeCapture: ActiveCapture?
    private var engine: AVAudioEngine?
    private var engineConfigurationObserver: NSObjectProtocol?
    private var halInputUnit: AudioUnit?
    private var halCallbackContext: HALInputCallbackContext?

    init(
        deviceMonitor: AudioDeviceMonitorProtocol = CoreAudioDeviceMonitor(),
        maximumDurationSeconds: Double = 10 * 60,
        firstFrameDeadlineSeconds: Double = 1.5
    ) {
        self.deviceMonitor = deviceMonitor
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
            self.stopHardware()
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
                    let resolution = try CoreAudioDeviceCatalog.resolveRoute(
                        preferredInputDeviceID: preferredInputDeviceID,
                        echoCancellationEnabled: echoCancellationEnabled
                    )
                    guard let ring = SuniyeAudioRingBufferCreate(self.ringCapacity) else {
                        throw AudioCaptureServiceError.ringBufferUnavailable
                    }

                    let active = ActiveCapture(
                        id: sessionID,
                        preferredInputDeviceID: preferredInputDeviceID,
                        requestedEchoCancellation: echoCancellationEnabled,
                        route: resolution.snapshot,
                        ring: ring
                    )
                    self.activeCapture = active
                    self.startDrainTimer(for: active)

                    do {
                        try self.startHardware(for: resolution, active: active)
                    } catch {
                        try self.fallbackToStandardEngine(active: active, originalError: error)
                    }

                    self.deviceMonitor.watch(
                        deviceID: CoreAudioDeviceCatalog.deviceID(forUID: active.route.effectiveInputDeviceID)
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
                    continuation.resume(returning: CapturedAudio(
                        sessionID: sessionID,
                        samples: [],
                        sampleRate: 16_000,
                        outcome: .interrupted(.ioStoppedAbnormally)
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
        CoreAudioDeviceCatalog.availableInputDevices()
    }

    func routeSnapshot(preferredInputDeviceID: String?, echoCancellationEnabled: Bool) throws -> AudioRouteSnapshot {
        try CoreAudioDeviceCatalog.resolveRoute(
            preferredInputDeviceID: preferredInputDeviceID,
            echoCancellationEnabled: echoCancellationEnabled
        ).snapshot
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
            self.onDevicesChanged?(CoreAudioDeviceCatalog.availableInputDevices())
        }
    }

    static func captureBackend(
        echoCancellationEnabled: Bool,
        inputDeviceUsesBluetooth: Bool? = nil,
        outputDeviceUsesBluetooth: Bool? = nil
    ) -> String {
        if echoCancellationEnabled,
           inputDeviceUsesBluetooth == false,
           outputDeviceUsesBluetooth == false {
            return AudioCaptureBackend.voiceProcessingEngine.rawValue
        }
        return AudioCaptureBackend.inputOnlyHAL.rawValue
    }

    private func startHardware(for resolution: CoreAudioRouteResolution, active: ActiveCapture) throws {
        switch active.route.backend {
        case .inputOnlyHAL:
            try startHALCapture(inputDeviceID: resolution.inputDeviceID, active: active)
        case .voiceProcessingEngine:
            try startEngineCapture(inputDeviceID: resolution.inputDeviceID, voiceProcessing: true, active: active)
        case .standardEngine:
            try startEngineCapture(inputDeviceID: resolution.inputDeviceID, voiceProcessing: false, active: active)
        }
    }

    private func fallbackToStandardEngine(active: ActiveCapture, originalError: Error) throws {
        stopHardware()
        active.fallbackAttempted = true
        SuniyeAudioRingBufferReset(active.ring)
        let resolution = try CoreAudioDeviceCatalog.resolveRoute(
            preferredInputDeviceID: active.preferredInputDeviceID,
            echoCancellationEnabled: active.requestedEchoCancellation,
            preferredBackend: .standardEngine,
            fallbackReason: "backend_start_failed"
        )
        active.route = resolution.snapshot
        try startEngineCapture(inputDeviceID: resolution.inputDeviceID, voiceProcessing: false, active: active)
        onRouteChanged?(active.id, active.route)
        AppLogger.shared.log(.warning, "audio backend fallback session=\(active.id.uuidString) reason=\(originalError.localizedDescription) \(active.route.privacySafeLogValue)")
    }

    private func startEngineCapture(inputDeviceID: AudioObjectID, voiceProcessing: Bool, active: ActiveCapture) throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        engine.stop()

        if inputNode.isVoiceProcessingEnabled != voiceProcessing {
            try inputNode.setVoiceProcessingEnabled(voiceProcessing)
        }
        if voiceProcessing {
            inputNode.voiceProcessingOtherAudioDuckingConfiguration =
                AVAudioVoiceProcessingOtherAudioDuckingConfiguration(
                    enableAdvancedDucking: false,
                    duckingLevel: .min
                )
        }

        try select(inputDeviceID: inputDeviceID, on: inputNode)
        let nativeFormat = inputNode.outputFormat(forBus: 0)
        guard nativeFormat.sampleRate > 0, nativeFormat.channelCount > 0 else {
            throw AudioCaptureServiceError.invalidInputFormat
        }

        let tapFormat: AVAudioFormat?
        if voiceProcessing, nativeFormat.channelCount > 1 {
            tapFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: nativeFormat.sampleRate,
                channels: 1,
                interleaved: false
            )
        } else {
            tapFormat = nativeFormat
        }
        guard let tapFormat else {
            throw AudioCaptureServiceError.invalidInputFormat
        }

        let ring = active.ring
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { buffer, _ in
            guard let channels = buffer.floatChannelData else { return }
            _ = channels.withMemoryRebound(
                to: Optional<UnsafePointer<Float>>.self,
                capacity: Int(buffer.format.channelCount)
            ) { channelPointers in
                SuniyeAudioRingBufferWritePlanar(
                    ring,
                    channelPointers,
                    buffer.format.channelCount,
                    buffer.frameLength
                )
            }
        }

        engine.prepare()
        try engine.start()
        self.engine = engine
        engineConfigurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            self?.controlQueue.async {
                self?.interruptActiveCapture(.engineConfigurationChanged)
            }
        }
    }

    private func startHALCapture(inputDeviceID: AudioObjectID, active: ActiveCapture) throws {
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &description) else {
            throw AudioCaptureServiceError.operationFailed("Create input-only audio component", kAudio_ParamError)
        }

        var maybeUnit: AudioUnit?
        try check(AudioComponentInstanceNew(component, &maybeUnit), operation: "Create input-only audio unit")
        guard let unit = maybeUnit else {
            throw AudioCaptureServiceError.operationFailed("Create input-only audio unit", kAudio_ParamError)
        }

        do {
            var enableInput: UInt32 = 1
            try check(AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_EnableIO,
                kAudioUnitScope_Input,
                1,
                &enableInput,
                UInt32(MemoryLayout<UInt32>.size)
            ), operation: "Enable input-only capture")

            var disableOutput: UInt32 = 0
            try check(AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_EnableIO,
                kAudioUnitScope_Output,
                0,
                &disableOutput,
                UInt32(MemoryLayout<UInt32>.size)
            ), operation: "Disable capture output")

            var currentDevice = inputDeviceID
            try check(AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &currentDevice,
                UInt32(MemoryLayout<AudioObjectID>.size)
            ), operation: "Select input-only microphone")

            var deviceFormat = AudioStreamBasicDescription()
            var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try check(AudioUnitGetProperty(
                unit,
                kAudioUnitProperty_StreamFormat,
                kAudioUnitScope_Input,
                1,
                &deviceFormat,
                &formatSize
            ), operation: "Read input hardware format")
            guard deviceFormat.mSampleRate > 0, deviceFormat.mChannelsPerFrame > 0 else {
                throw AudioCaptureServiceError.invalidInputFormat
            }

            var clientFormat = AudioStreamBasicDescription(
                mSampleRate: deviceFormat.mSampleRate,
                mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
                mBytesPerPacket: UInt32(MemoryLayout<Float>.size),
                mFramesPerPacket: 1,
                mBytesPerFrame: UInt32(MemoryLayout<Float>.size),
                mChannelsPerFrame: 1,
                mBitsPerChannel: UInt32(MemoryLayout<Float>.size * 8),
                mReserved: 0
            )
            try check(AudioUnitSetProperty(
                unit,
                kAudioUnitProperty_StreamFormat,
                kAudioUnitScope_Output,
                1,
                &clientFormat,
                UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            ), operation: "Set input-only client format")

            var maximumFrames: UInt32 = 0
            var maximumFramesSize = UInt32(MemoryLayout<UInt32>.size)
            if AudioUnitGetProperty(
                unit,
                kAudioUnitProperty_MaximumFramesPerSlice,
                kAudioUnitScope_Global,
                0,
                &maximumFrames,
                &maximumFramesSize
            ) != noErr || maximumFrames == 0 {
                maximumFrames = 32_768
            }
            let scratchCapacity = max(32_768, Int(maximumFrames))
            let callbackContext = HALInputCallbackContext(
                unit: unit,
                ring: active.ring,
                scratchCapacity: scratchCapacity
            )

            var callback = AURenderCallbackStruct(
                inputProc: audioCaptureHALInputCallback,
                inputProcRefCon: Unmanaged.passUnretained(callbackContext).toOpaque()
            )
            try check(AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_SetInputCallback,
                kAudioUnitScope_Global,
                0,
                &callback,
                UInt32(MemoryLayout<AURenderCallbackStruct>.size)
            ), operation: "Install input-only callback")

            halInputUnit = unit
            halCallbackContext = callbackContext
            try check(AudioUnitInitialize(unit), operation: "Initialize input-only capture")
            try check(AudioOutputUnitStart(unit), operation: "Start input-only capture")
        } catch {
            halCallbackContext = nil
            halInputUnit = nil
            AudioComponentInstanceDispose(unit)
            throw error
        }
    }

    private func select(inputDeviceID: AudioObjectID, on inputNode: AVAudioInputNode) throws {
        guard let audioUnit = inputNode.audioUnit else {
            throw AudioCaptureServiceError.noInputDevice
        }
        var device = inputDeviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &device,
            UInt32(MemoryLayout<AudioObjectID>.size)
        )
        guard status == noErr else {
            throw AudioCaptureServiceError.failedToSelectInput(status)
        }
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
        onLevelsUpdate?(active.id, active.smoothedLevels)
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
        onDevicesChanged?(CoreAudioDeviceCatalog.availableInputDevices())

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
            interruption = CoreAudioDeviceCatalog.processInputIsMuted() == true ? .inputMuted : nil
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
            let resolution = try CoreAudioDeviceCatalog.resolveRoute(
                preferredInputDeviceID: active.preferredInputDeviceID,
                echoCancellationEnabled: active.requestedEchoCancellation
            )
            return resolution.snapshot.effectiveInputDeviceID == active.route.effectiveInputDeviceID
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
        stopHardware()
        drain(active)
        active.drainTimer?.cancel()
        active.drainTimer = nil
        AppLogger.shared.log(.warning, "audio capture interrupted session=\(active.id.uuidString) reason=\(reason.rawValue) \(active.route.privacySafeLogValue)")
        onCaptureInterrupted?(active.id, reason)
    }

    private func finalize(active: ActiveCapture, discard: Bool) -> CapturedAudio {
        stopHardware()
        drain(active)
        active.drainTimer?.cancel()
        active.drainTimer = nil
        let samples = discard ? [] : active.samples
        let outcome = active.interruption == .maximumDurationReached
            ? AudioCaptureOutcome.complete
            : active.interruption.map(AudioCaptureOutcome.interrupted)
        let captured = CapturedAudio(
            sessionID: active.id,
            samples: samples,
            sampleRate: active.route.inputSampleRate,
            outcome: outcome,
            route: active.route,
            droppedSampleCount: SuniyeAudioRingBufferDroppedSamples(active.ring)
        )
        activeCapture = nil
        deviceMonitor.watch(deviceID: nil)
        onLevelsUpdate?(active.id, Array(repeating: 0, count: 12))
        logFinalCapture(captured, discarded: discard)
        scheduleReleaseCheck(sessionID: active.id)
        return captured
    }

    private func discardActiveCapture() {
        guard let active = activeCapture else {
            stopHardware()
            return
        }
        _ = finalize(active: active, discard: true)
    }

    private func stopHardware() {
        if let observer = engineConfigurationObserver {
            NotificationCenter.default.removeObserver(observer)
            engineConfigurationObserver = nil
        }
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            if engine.inputNode.isVoiceProcessingEnabled {
                try? engine.inputNode.setVoiceProcessingEnabled(false)
            }
            engine.reset()
            self.engine = nil
        }
        if let halInputUnit {
            AudioOutputUnitStop(halInputUnit)
            AudioUnitUninitialize(halInputUnit)
            AudioComponentInstanceDispose(halInputUnit)
            self.halInputUnit = nil
        }
        halCallbackContext = nil
    }

    private func scheduleReleaseCheck(sessionID: UUID) {
        controlQueue.asyncAfter(deadline: .now() + .milliseconds(300)) {
            let released = CoreAudioDeviceCatalog.processIsRunningInput().map { !$0 }
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

    private func check(_ status: OSStatus, operation: String) throws {
        guard status == noErr else {
            throw AudioCaptureServiceError.operationFailed(operation, status)
        }
    }

    private func withCallbackLock<T>(_ work: () -> T) -> T {
        callbackLock.lock()
        defer { callbackLock.unlock() }
        return work()
    }
}
