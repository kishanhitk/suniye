import AVFoundation
import AudioToolbox
import Foundation

struct CapturedAudio {
    let samples: [Float]
    let sampleRate: Int
}

final class AudioCaptureService {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private var targetFormat: AVAudioFormat?
    private var captureSampleRate: Int = 16_000
    private var samples: [Float] = []
    private let lock = NSLock()
    private let audioDeviceService: AudioDeviceServiceProtocol

    init(audioDeviceService: AudioDeviceServiceProtocol = AudioDeviceService()) {
        self.audioDeviceService = audioDeviceService
    }

    func startCapture(selectedInputDeviceUID: String? = nil) throws {
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        lock.unlock()

        let inputNode = engine.inputNode
        if let selectedInputDeviceUID {
            try setInputDevice(uid: selectedInputDeviceUID, inputNode: inputNode)
        }

        let hardwareFormat = inputNode.outputFormat(forBus: 0)
        let sampleRate = max(8_000, Int(hardwareFormat.sampleRate.rounded()))
        captureSampleRate = sampleRate

        inputFormat = hardwareFormat
        targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: hardwareFormat.sampleRate,
            channels: 1,
            interleaved: false
        )
        if let targetFormat {
            converter = AVAudioConverter(from: hardwareFormat, to: targetFormat)
        } else {
            converter = nil
        }
        AppLogger.shared.log(
            .info,
            "audio capture start sr=\(sampleRate) channels=\(hardwareFormat.channelCount) format=\(hardwareFormat.commonFormat.rawValue)"
        )

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: hardwareFormat) { [weak self] buffer, _ in
            self?.consume(buffer: buffer)
        }

        engine.prepare()
        try engine.start()
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

    private func setInputDevice(uid: String, inputNode: AVAudioInputNode) throws {
        guard let deviceID = audioDeviceService.coreAudioDeviceID(forUID: uid) else {
            throw NSError(
                domain: "Suniye.AudioCapture",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "Selected input device not found"]
            )
        }

        guard let audioUnit = inputNode.audioUnit else {
            throw NSError(
                domain: "Suniye.AudioCapture",
                code: 1002,
                userInfo: [NSLocalizedDescriptionKey: "Unable to access audio input unit"]
            )
        }

        var mutableDeviceID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutableDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        guard status == noErr else {
            throw NSError(
                domain: "Suniye.AudioCapture",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Failed to switch audio input device (OSStatus \(status))"]
            )
        }
    }
}
