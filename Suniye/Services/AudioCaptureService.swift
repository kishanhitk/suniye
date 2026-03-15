import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation

struct CapturedAudio {
    let samples: [Float]
    let sampleRate: Int
}

protocol AudioCaptureServiceProtocol {
    func startCapture(preferredInputDeviceID: String?, echoCancellationEnabled: Bool) throws
    func stopCapture() -> CapturedAudio
    func availableInputDevices() -> [AudioInputDevice]
}

final class AudioCaptureService: AudioCaptureServiceProtocol {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private var targetFormat: AVAudioFormat?
    private var captureSampleRate: Int = 16_000
    private var samples: [Float] = []
    private let lock = NSLock()

    func startCapture(preferredInputDeviceID: String?, echoCancellationEnabled: Bool) throws {
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        lock.unlock()

        let inputNode = engine.inputNode
        inputNode.removeTap(onBus: 0)
        engine.stop()

        // VP must be toggled before reading format or setting device — it replaces the audio unit.
        if inputNode.isVoiceProcessingEnabled != echoCancellationEnabled {
            try inputNode.setVoiceProcessingEnabled(echoCancellationEnabled)
        }

        if echoCancellationEnabled {
            // Disable ducking so system audio volume isn't reduced during recording.
            // Layer 1: AU property 2012 — minimizes the initial volume dip.
            if let au = inputNode.audioUnit {
                var duck: UInt32 = 0
                AudioUnitSetProperty(au, 2012, kAudioUnitScope_Global, 0,
                                     &duck, UInt32(MemoryLayout<UInt32>.size))
            }
            // Layer 2: high-level lifecycle control (macOS 14+).
            if #available(macOS 14.0, *) {
                inputNode.voiceProcessingOtherAudioDuckingConfiguration =
                    AVAudioVoiceProcessingOtherAudioDuckingConfiguration(
                        enableAdvancedDucking: false, duckingLevel: .min)
            }
        }

        // Set input device — must be after VP toggle since VP replaces the audio unit.
        if let preferredInputDeviceID,
           let audioUnit = inputNode.audioUnit,
           let deviceID = Self.audioDeviceID(forUID: preferredInputDeviceID) {
            var currentDevice = deviceID
            let status = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &currentDevice,
                UInt32(MemoryLayout<AudioObjectID>.size)
            )
            if status != noErr {
                AppLogger.shared.log(.warning, "audio input device selection failed status=\(status)")
            }
        }

        // Read format after VP enable — VP changes the node to a multi-channel aggregate.
        let nativeFormat = inputNode.outputFormat(forBus: 0)
        let sampleRate = max(8_000, Int(nativeFormat.sampleRate.rounded()))
        captureSampleRate = sampleRate

        // VP on Apple Silicon reports 5ch (3-mic array + 2-ch speaker ref).
        // AVAudioConverter can't downmix VP multi-channel correctly (produces zeros).
        // The VP unit handles channel extraction internally — just tap mono.
        let tapFormat: AVAudioFormat
        if nativeFormat.channelCount > 1 {
            tapFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                     sampleRate: nativeFormat.sampleRate,
                                     channels: 1, interleaved: false)!
        } else {
            tapFormat = nativeFormat
        }

        inputFormat = tapFormat
        targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: nativeFormat.sampleRate,
            channels: 1,
            interleaved: false
        )
        if let targetFormat {
            converter = AVAudioConverter(from: tapFormat, to: targetFormat)
        } else {
            converter = nil
        }
        AppLogger.shared.log(
            .info,
            "audio capture start sr=\(sampleRate) channels=\(nativeFormat.channelCount) tapChannels=1 aec=\(echoCancellationEnabled)"
        )
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { [weak self] buffer, _ in
            self?.consume(buffer: buffer)
        }

        try engine.start()
    }

    func availableInputDevices() -> [AudioInputDevice] {
        let defaultInputDeviceID = Self.defaultInputDeviceID()
        return Self.allDeviceIDs()
            .filter { Self.inputChannelCount(for: $0) > 0 }
            .compactMap { deviceID in
                guard let uid = Self.deviceUID(for: deviceID),
                      let name = Self.deviceName(for: deviceID) else {
                    return nil
                }
                return AudioInputDevice(
                    id: uid,
                    name: name,
                    isDefault: defaultInputDeviceID == deviceID
                )
            }
            .sorted {
                if $0.isDefault != $1.isDefault {
                    return $0.isDefault
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    func stopCapture() -> CapturedAudio {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        lock.lock()
        let out = samples
        samples.removeAll(keepingCapacity: false)
        lock.unlock()
        let rms = Self.rms(of: out)
        let peak = out.reduce(0) { max($0, abs($1)) }
        let seconds = out.isEmpty ? 0 : Double(out.count) / Double(captureSampleRate)
        AppLogger.shared.log(
            .info,
            String(
                format: "audio capture stop samples=%d sr=%d duration=%.2fs rms=%.5f peak=%.5f",
                out.count,
                captureSampleRate,
                seconds,
                rms,
                peak
            )
        )
        return CapturedAudio(samples: out, sampleRate: captureSampleRate)
    }

    private func consume(buffer: AVAudioPCMBuffer) {
        if let converted = convertToFloatMono(buffer: buffer),
           let channelData = converted.floatChannelData {
            let frameCount = Int(converted.frameLength)
            let ptr = channelData[0]
            let chunk = Array(UnsafeBufferPointer(start: ptr, count: frameCount))

            lock.lock()
            samples.append(contentsOf: chunk)
            lock.unlock()
            return
        }

        appendFloatSamplesDirectly(buffer: buffer)
    }

    private func convertToFloatMono(buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter,
              let inputFormat,
              let targetFormat else {
            return nil
        }

        let ratio = targetFormat.sampleRate / inputFormat.sampleRate
        let targetCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 256

        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: max(512, targetCapacity)) else {
            return nil
        }

        var error: NSError?
        var didProvideInput = false

        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if didProvideInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            didProvideInput = true
            outStatus.pointee = .haveData
            return buffer
        }

        if status == .error || error != nil {
            return nil
        }
        return output
    }

    private func appendFloatSamplesDirectly(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else {
            return
        }

        let frameCount = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        if frameCount == 0 || channels == 0 {
            return
        }

        if channels == 1 {
            let chunk = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
            lock.lock()
            samples.append(contentsOf: chunk)
            lock.unlock()
            return
        }

        var mixed = Array(repeating: Float(0), count: frameCount)
        for channel in 0 ..< channels {
            let ptr = channelData[channel]
            for i in 0 ..< frameCount {
                mixed[i] += ptr[i]
            }
        }
        let scale = Float(1.0 / Double(channels))
        for i in 0 ..< frameCount {
            mixed[i] *= scale
        }
        lock.lock()
        samples.append(contentsOf: mixed)
        lock.unlock()
    }

    private static func rms(of values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        var sum: Double = 0
        for sample in values {
            let v = Double(sample)
            sum += v * v
        }
        return Float((sum / Double(values.count)).squareRoot())
    }

    private static func allDeviceIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = Array(repeating: AudioObjectID(), count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceIDs) == noErr else {
            return []
        }
        return deviceIDs
    }

    private static func defaultInputDeviceID() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID()
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceID) == noErr else {
            return nil
        }
        return deviceID
    }

    private static func audioDeviceID(forUID uid: String) -> AudioObjectID? {
        for deviceID in allDeviceIDs() {
            if deviceUID(for: deviceID) == uid {
                return deviceID
            }
        }
        return nil
    }

    private static func deviceUID(for deviceID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfString: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &cfString) == noErr else {
            return nil
        }
        return cfString as String
    }

    private static func deviceName(for deviceID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfString: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &cfString) == noErr else {
            return nil
        }
        return cfString as String
    }

    private static func inputChannelCount(for deviceID: AudioObjectID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr else {
            return 0
        }

        let rawPointer = UnsafeMutableRawPointer.allocate(byteCount: Int(dataSize), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { rawPointer.deallocate() }

        let bufferListPointer = rawPointer.bindMemory(to: AudioBufferList.self, capacity: 1)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, bufferListPointer) == noErr else {
            return 0
        }

        let buffers = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}
