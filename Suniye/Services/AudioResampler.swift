import AVFoundation

/// Mono float resampling through `AVAudioConverter`, for engines whose model
/// expects a fixed input rate while capture runs at the device's native one.
enum AudioResampler {
    struct ResampleError: LocalizedError {
        var errorDescription: String? {
            "Failed to resample audio"
        }
    }

    static func resample(_ samples: [Float], from sourceRate: Int, to targetRate: Int) throws -> [Float] {
        guard sourceRate != targetRate, !samples.isEmpty else {
            return samples
        }
        guard let sourceFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(sourceRate), channels: 1, interleaved: false),
              let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(targetRate), channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: sourceFormat, to: targetFormat),
              let input = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(samples.count)) else {
            throw ResampleError()
        }
        input.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer in
            input.floatChannelData?[0].update(from: buffer.baseAddress!, count: samples.count)
        }

        // Capacity = resampled length + a ~100 ms margin covering the resampler's
        // filter delay, so the whole input converts in one pass without dropping
        // tail frames.
        let ratio = Double(targetRate) / Double(sourceRate)
        let capacity = AVAudioFrameCount((Double(samples.count) * ratio).rounded(.up)) + AVAudioFrameCount(targetRate / 10) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            throw ResampleError()
        }

        var providedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if providedInput {
                inputStatus.pointee = .endOfStream
                return nil
            }
            providedInput = true
            inputStatus.pointee = .haveData
            return input
        }
        guard status != .error, conversionError == nil, let channel = output.floatChannelData?[0] else {
            throw ResampleError()
        }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }
}
