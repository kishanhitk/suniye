import AVFoundation

/// One-shot audio conversion through `AVAudioConverter` for engines whose model
/// wants a fixed input format while capture runs at the device's native rate.
enum AudioResampler {
    struct ResampleError: LocalizedError {
        var errorDescription: String? {
            "Failed to resample audio"
        }
    }

    /// Mono float32 PCM buffer holding `samples`; `nil` only if AVFoundation rejects the format.
    static func monoBuffer(_ samples: [Float], sampleRate: Int) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(sampleRate), channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            if let base = source.baseAddress {
                buffer.floatChannelData?[0].update(from: base, count: samples.count)
            }
        }
        return buffer
    }

    /// Converts a whole buffer (rate and/or layout) in a single pass.
    static func convert(_ source: AVAudioPCMBuffer, to targetFormat: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard let converter = AVAudioConverter(from: source.format, to: targetFormat) else {
            throw ResampleError()
        }

        // Capacity = resampled length + a ~100 ms margin covering the resampler's
        // filter delay, so the whole input converts in one pass without dropping
        // tail frames.
        let ratio = targetFormat.sampleRate / source.format.sampleRate
        let capacity = AVAudioFrameCount((Double(source.frameLength) * ratio).rounded(.up))
            + AVAudioFrameCount(targetFormat.sampleRate / 10) + 1
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
            return source
        }
        // The margin above guarantees one pass reaches .endOfStream; only a hard
        // converter error is a real failure.
        guard status != .error, conversionError == nil else {
            throw ResampleError()
        }
        return output
    }

    static func resample(_ samples: [Float], from sourceRate: Int, to targetRate: Int) throws -> [Float] {
        guard sourceRate != targetRate, !samples.isEmpty else {
            return samples
        }
        guard let source = monoBuffer(samples, sampleRate: sourceRate),
              let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(targetRate), channels: 1, interleaved: false) else {
            throw ResampleError()
        }
        let output = try convert(source, to: targetFormat)
        guard let channel = output.floatChannelData?[0] else {
            throw ResampleError()
        }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }
}
