import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation

protocol AudioCaptureDriver: AnyObject {
    var backend: AudioCaptureBackend { get }
    var format: AudioCaptureFormat { get }
    func stop()
}

struct AudioCaptureDriverStart {
    let driver: AudioCaptureDriver
    let format: AudioCaptureFormat
}

protocol AudioCaptureDriverFactoryProtocol {
    func startDriver(
        for plan: AudioCapturePlan,
        inputDeviceID: AudioObjectID,
        ring: OpaquePointer,
        onConfigurationChange: @escaping () -> Void
    ) throws -> AudioCaptureDriverStart
}

struct DefaultAudioCaptureDriverFactory: AudioCaptureDriverFactoryProtocol {
    func startDriver(
        for plan: AudioCapturePlan,
        inputDeviceID: AudioObjectID,
        ring: OpaquePointer,
        onConfigurationChange: @escaping () -> Void
    ) throws -> AudioCaptureDriverStart {
        let driver: AudioCaptureDriver
        switch plan.backend {
        case .inputOnlyHAL:
            driver = try HALCaptureDriver(inputDeviceID: inputDeviceID, ring: ring)
        case .standardEngine:
            driver = try EngineCaptureDriver(
                inputDeviceID: inputDeviceID,
                ring: ring,
                voiceProcessing: false,
                onConfigurationChange: onConfigurationChange
            )
        case .voiceProcessingEngine:
            driver = try EngineCaptureDriver(
                inputDeviceID: inputDeviceID,
                ring: ring,
                voiceProcessing: true,
                onConfigurationChange: onConfigurationChange
            )
        }
        return AudioCaptureDriverStart(driver: driver, format: driver.format)
    }
}

private final class EngineCaptureDriver: AudioCaptureDriver {
    let backend: AudioCaptureBackend
    private(set) var format: AudioCaptureFormat

    private let engine: AVAudioEngine
    private var configurationObserver: NSObjectProtocol?
    private var tapInstalled = false

    init(
        inputDeviceID: AudioObjectID,
        ring: OpaquePointer,
        voiceProcessing: Bool,
        onConfigurationChange: @escaping () -> Void
    ) throws {
        backend = voiceProcessing ? .voiceProcessingEngine : .standardEngine
        format = AudioCaptureFormat(sampleRate: 16_000, channelCount: 1)
        engine = AVAudioEngine()

        do {
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

            try Self.select(inputDeviceID: inputDeviceID, on: inputNode)
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
            tapInstalled = true

            engine.prepare()
            try engine.start()
            format = AudioCaptureFormat(
                sampleRate: max(8_000, Int(tapFormat.sampleRate.rounded())),
                channelCount: 1
            )
            configurationObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange,
                object: engine,
                queue: nil
            ) { _ in
                onConfigurationChange()
            }
        } catch {
            stop()
            throw error
        }
    }

    deinit {
        stop()
    }

    func stop() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
        if engine.inputNode.isVoiceProcessingEnabled {
            try? engine.inputNode.setVoiceProcessingEnabled(false)
        }
        engine.reset()
    }

    private static func select(inputDeviceID: AudioObjectID, on inputNode: AVAudioInputNode) throws {
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
        scratch = .allocate(capacity: scratchCapacity)
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

private final class HALCaptureDriver: AudioCaptureDriver {
    let backend = AudioCaptureBackend.inputOnlyHAL
    private(set) var format = AudioCaptureFormat(sampleRate: 16_000, channelCount: 1)

    private var unit: AudioUnit?
    private var callbackContext: HALInputCallbackContext?

    init(inputDeviceID: AudioObjectID, ring: OpaquePointer) throws {
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
        try checkAudioStatus(
            AudioComponentInstanceNew(component, &maybeUnit),
            operation: "Create input-only audio unit"
        )
        guard let unit = maybeUnit else {
            throw AudioCaptureServiceError.operationFailed("Create input-only audio unit", kAudio_ParamError)
        }
        self.unit = unit

        do {
            var enableInput: UInt32 = 1
            try checkAudioStatus(AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_EnableIO,
                kAudioUnitScope_Input,
                1,
                &enableInput,
                UInt32(MemoryLayout<UInt32>.size)
            ), operation: "Enable input-only capture")

            var disableOutput: UInt32 = 0
            try checkAudioStatus(AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_EnableIO,
                kAudioUnitScope_Output,
                0,
                &disableOutput,
                UInt32(MemoryLayout<UInt32>.size)
            ), operation: "Disable capture output")

            var currentDevice = inputDeviceID
            try checkAudioStatus(AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &currentDevice,
                UInt32(MemoryLayout<AudioObjectID>.size)
            ), operation: "Select input-only microphone")

            var deviceFormat = AudioStreamBasicDescription()
            var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            // The device's true hardware format lives on the INPUT scope of element 1 (TN2091).
            // The OUTPUT scope of element 1 is the *client* format we set below, and reading it
            // here (before it is configured) returns AUHAL's default (e.g. 44.1kHz), not the real
            // device rate (e.g. 48kHz). A mismatched client rate makes the input callback never
            // fire, so no audio is captured (KIS-141). Read the hardware format from the input scope.
            try checkAudioStatus(AudioUnitGetProperty(
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
            try checkAudioStatus(AudioUnitSetProperty(
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
            let context = HALInputCallbackContext(
                unit: unit,
                ring: ring,
                scratchCapacity: max(32_768, Int(maximumFrames))
            )
            callbackContext = context

            var callback = AURenderCallbackStruct(
                inputProc: audioCaptureHALInputCallback,
                inputProcRefCon: Unmanaged.passUnretained(context).toOpaque()
            )
            try checkAudioStatus(AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_SetInputCallback,
                kAudioUnitScope_Global,
                0,
                &callback,
                UInt32(MemoryLayout<AURenderCallbackStruct>.size)
            ), operation: "Install input-only callback")

            try checkAudioStatus(AudioUnitInitialize(unit), operation: "Initialize input-only capture")
            try checkAudioStatus(AudioOutputUnitStart(unit), operation: "Start input-only capture")
            format = AudioCaptureFormat(
                sampleRate: max(8_000, Int(deviceFormat.mSampleRate.rounded())),
                channelCount: 1
            )
        } catch {
            stop()
            throw error
        }
    }

    deinit {
        stop()
    }

    func stop() {
        guard let unit else {
            callbackContext = nil
            return
        }
        AudioOutputUnitStop(unit)
        AudioUnitUninitialize(unit)
        AudioComponentInstanceDispose(unit)
        self.unit = nil
        callbackContext = nil
    }
}

private func checkAudioStatus(_ status: OSStatus, operation: String) throws {
    guard status == noErr else {
        throw AudioCaptureServiceError.operationFailed(operation, status)
    }
}
