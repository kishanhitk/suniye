import AudioToolbox
import CoreAudio
import Foundation

/// The "Them" track: one mono Core Audio process tap over every app except
/// Suniye, in a private aggregate device that holds only the tap.
///
/// - Tap autostart stays off and `AudioDeviceStart` runs explicitly: autostart
///   waits for a tapped app and can make Zoom hang on join.
/// - The aggregate device takes the first free UID of two fixed ones, so a
///   crash cannot pile up hidden devices with fresh UIDs.
/// - An output route change does not rebuild the tap; the tap sits before the
///   output device, and a rebuild can lose the other side of the call.
/// - macOS asks for the system audio permission on the first start. No public
///   API reports the answer: a denied tap delivers silence, which the recorder
///   reports after a while without sound.
@available(macOS 14.4, *)
final class SystemAudioTap: MeetingAudioSource, @unchecked Sendable {
    enum TapError: LocalizedError {
        case coreAudio(String, OSStatus)
        case noTap

        var errorDescription: String? {
            switch self {
            case let .coreAudio(step, status):
                return "Could not record system audio (\(step), Core Audio \(status))."
            case .noTap:
                return "Could not record system audio (no tap)."
            }
        }
    }

    static let aggregateUIDs = ["dev.suniye.meeting.system-audio", "dev.suniye.meeting.system-audio.2"]

    var onSamples: (([Float]) -> Void)? {
        get { withCallbackLock { sampleCallback } }
        set { withCallbackLock { sampleCallback = newValue } }
    }

    var onEvent: ((MeetingAudioSourceEvent) -> Void)? {
        get { withCallbackLock { eventCallback } }
        set { withCallbackLock { eventCallback = newValue } }
    }

    private let queue = DispatchQueue(label: "dev.suniye.meeting.system-audio", qos: .userInitiated)
    private let ioQueue = DispatchQueue(label: "dev.suniye.meeting.system-audio.io", qos: .userInteractive)
    private let callbackLock = NSLock()
    private let ringCapacity = 1_048_576
    private let drainCapacity = 32_768
    private let drainScratch: UnsafeMutablePointer<Float>
    private let mixScratchCapacity = 16_384
    private let mixScratch: UnsafeMutablePointer<Float>

    private var sampleCallback: (([Float]) -> Void)?
    private var eventCallback: ((MeetingAudioSourceEvent) -> Void)?
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var ring: OpaquePointer?
    private var resampler: MeetingResampler?
    private var drainTimer: DispatchSourceTimer?
    private var channelCount = 1
    private var interleaved = true

    init() {
        drainScratch = .allocate(capacity: drainCapacity)
        mixScratch = .allocate(capacity: mixScratchCapacity)
    }

    deinit {
        tearDown()
        drainScratch.deallocate()
        mixScratch.deallocate()
    }

    func start() throws {
        try queue.sync {
            guard tapID == kAudioObjectUnknown else { return }
            do {
                try build()
            } catch {
                tearDown()
                throw error
            }
        }
    }

    func stop() {
        queue.sync {
            drainRing()
            if let tail = resampler?.flush(), !tail.isEmpty {
                onSamples?(tail)
            }
            tearDown()
        }
    }

    // MARK: - Build and tear down (on `queue`)

    private func build() throws {
        let ownProcess = Self.processObject(for: ProcessInfo.processInfo.processIdentifier)
        let description = CATapDescription(monoGlobalTapButExcludeProcesses: ownProcess.map { [$0] } ?? [])
        description.uuid = UUID()
        description.name = "Suniye meeting"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var newTap = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateProcessTap(description, &newTap), "create tap")
        guard newTap != kAudioObjectUnknown else { throw TapError.noTap }
        tapID = newTap

        var format = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var formatAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        try check(AudioObjectGetPropertyData(tapID, &formatAddress, 0, nil, &formatSize, &format), "read tap format")
        channelCount = max(1, Int(format.mChannelsPerFrame))
        interleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
        resampler = try MeetingResampler(inputSampleRate: Int(format.mSampleRate))

        aggregateID = try createAggregate(tapUID: description.uuid.uuidString)

        guard let ring = SuniyeAudioRingBufferCreate(ringCapacity) else {
            throw AudioCaptureServiceError.ringBufferUnavailable
        }
        self.ring = ring
        try check(
            AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, ioQueue) { [weak self] _, inputData, _, _, _ in
                self?.write(inputData)
            },
            "create IO proc"
        )
        try check(AudioDeviceStart(aggregateID, ioProcID), "start device")
        startDrainTimer()
        AppLogger.shared.log(.info, "meeting system audio tap started rate=\(Int(format.mSampleRate)) channels=\(channelCount) excludedSelf=\(ownProcess != nil)")
    }

    private func createAggregate(tapUID: String) throws -> AudioObjectID {
        var lastStatus: OSStatus = noErr
        for uid in Self.aggregateUIDs {
            let description: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Suniye meeting audio",
                kAudioAggregateDeviceUIDKey: uid,
                kAudioAggregateDeviceIsPrivateKey: 1,
                kAudioAggregateDeviceIsStackedKey: 0,
                kAudioAggregateDeviceTapAutoStartKey: 0,
                kAudioAggregateDeviceTapListKey: [[
                    kAudioSubTapUIDKey: tapUID,
                    kAudioSubTapDriftCompensationKey: 1,
                ]],
            ]
            var device = AudioObjectID(kAudioObjectUnknown)
            lastStatus = AudioHardwareCreateAggregateDevice(description as CFDictionary, &device)
            if lastStatus == noErr, device != kAudioObjectUnknown {
                return device
            }
            AppLogger.shared.log(.warning, "meeting system audio aggregate create failed uid=\(uid) status=\(lastStatus)")
        }
        throw TapError.coreAudio("create aggregate device", lastStatus)
    }

    private func tearDown() {
        drainTimer?.cancel()
        drainTimer = nil
        if aggregateID != kAudioObjectUnknown {
            if let ioProcID {
                AudioDeviceStop(aggregateID, ioProcID)
                AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        ioProcID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        tapID = AudioObjectID(kAudioObjectUnknown)
        if let ring {
            SuniyeAudioRingBufferDestroy(ring)
        }
        ring = nil
        resampler = nil
    }

    // MARK: - Audio (IO queue writes, `queue` drains)

    private func write(_ inputData: UnsafePointer<AudioBufferList>) {
        guard let ring else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
        if !interleaved, buffers.count > 1 {
            let frames = Int(buffers[0].mDataByteSize) / MemoryLayout<Float>.size
            var channels: [UnsafePointer<Float>?] = []
            channels.reserveCapacity(buffers.count)
            for buffer in buffers {
                guard let data = buffer.mData else { return }
                channels.append(UnsafePointer(data.assumingMemoryBound(to: Float.self)))
            }
            channels.withUnsafeBufferPointer { pointers in
                _ = SuniyeAudioRingBufferWritePlanar(ring, pointers.baseAddress, UInt32(pointers.count), UInt32(frames))
            }
            return
        }
        guard let buffer = buffers.first, let data = buffer.mData else { return }
        let samples = data.assumingMemoryBound(to: Float.self)
        let total = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        guard channelCount > 1 else {
            _ = SuniyeAudioRingBufferWrite(ring, samples, total)
            return
        }
        let frames = min(total / channelCount, mixScratchCapacity)
        for frame in 0 ..< frames {
            var sum: Float = 0
            for channel in 0 ..< channelCount {
                sum += samples[frame * channelCount + channel]
            }
            mixScratch[frame] = sum / Float(channelCount)
        }
        _ = SuniyeAudioRingBufferWrite(ring, mixScratch, frames)
    }

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
            drained += resampler.process(UnsafeBufferPointer(start: drainScratch, count: count))
            count = SuniyeAudioRingBufferRead(ring, drainScratch, drainCapacity)
        }
        if !drained.isEmpty {
            onSamples?(drained)
        }
    }

    // MARK: - Helpers

    private func check(_ status: OSStatus, _ step: String) throws {
        guard status == noErr else { throw TapError.coreAudio(step, status) }
    }

    static func processObject(for pid: pid_t) -> AudioObjectID? {
        var pid = pid
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            UInt32(MemoryLayout<pid_t>.size),
            &pid,
            &size,
            &object
        )
        return status == noErr && object != kAudioObjectUnknown ? object : nil
    }

    private func withCallbackLock<T>(_ work: () -> T) -> T {
        callbackLock.lock()
        defer { callbackLock.unlock() }
        return work()
    }
}
