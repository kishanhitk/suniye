import AVFoundation
import Foundation

final class AudioCaptureService {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private let targetFormat: AVAudioFormat
    private var samples: [Float] = []
    private let lock = NSLock()

    init() {
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false) else {
            fatalError("Unable to create 16k mono target format")
        }
        self.targetFormat = target
    }

    func startCapture() throws {
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        lock.unlock()

        let inputNode = engine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)

        inputFormat = hardwareFormat
        converter = AVAudioConverter(from: hardwareFormat, to: targetFormat)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: hardwareFormat) { [weak self] buffer, _ in
            self?.consume(buffer: buffer)
        }

        engine.prepare()
        try engine.start()
    }

    func stopCapture() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        lock.lock()
        let out = samples
        samples.removeAll(keepingCapacity: false)
        lock.unlock()
        return out
    }

    private func consume(buffer: AVAudioPCMBuffer) {
        guard let converted = convertTo16kMono(buffer: buffer),
              let channelData = converted.floatChannelData else {
            return
        }

        let frameCount = Int(converted.frameLength)
        let ptr = channelData[0]
        let chunk = Array(UnsafeBufferPointer(start: ptr, count: frameCount))

        lock.lock()
        samples.append(contentsOf: chunk)
        lock.unlock()
    }

    private func convertTo16kMono(buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter,
              let inputFormat else {
            return nil
        }

        let ratio = targetFormat.sampleRate / inputFormat.sampleRate
        let targetCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024

        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: max(1024, targetCapacity)) else {
            return nil
        }

        var error: NSError?
        var didProvideInput = false

        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if didProvideInput {
                outStatus.pointee = .endOfStream
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
}
