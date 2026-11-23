import AVFoundation

/// Converts a mono stream at the device rate to 16 kHz block by block. One
/// converter lives for the whole stream, so its filter state carries across
/// blocks and the joins between blocks stay clean.
final class MeetingResampler {
    enum ResamplerError: LocalizedError {
        case unsupportedRate(Int)

        var errorDescription: String? {
            switch self {
            case let .unsupportedRate(rate):
                return "Cannot convert \(rate) Hz audio to 16 kHz."
            }
        }
    }

    let inputSampleRate: Int
    private let converter: AVAudioConverter?
    private let inputFormat: AVAudioFormat
    private let outputFormat: AVAudioFormat

    init(inputSampleRate: Int) throws {
        guard inputSampleRate >= 8_000,
              let input = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(inputSampleRate), channels: 1, interleaved: false),
              let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(MeetingAudioFormat.sampleRate), channels: 1, interleaved: false) else {
            throw ResamplerError.unsupportedRate(inputSampleRate)
        }
        self.inputSampleRate = inputSampleRate
        inputFormat = input
        outputFormat = output
        if inputSampleRate == MeetingAudioFormat.sampleRate {
            converter = nil
        } else {
            guard let converter = AVAudioConverter(from: input, to: output) else {
                throw ResamplerError.unsupportedRate(inputSampleRate)
            }
            self.converter = converter
        }
    }

    func process(_ samples: UnsafeBufferPointer<Float>) -> [Float] {
        guard !samples.isEmpty else { return [] }
        guard let converter else { return Array(samples) }
        guard let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(samples.count)),
              let base = samples.baseAddress else {
            return []
        }
        input.frameLength = AVAudioFrameCount(samples.count)
        input.floatChannelData?[0].update(from: base, count: samples.count)
        return convert(input, with: converter, endOfStream: false)
    }

    /// Returns the samples the converter still holds. Call once at the end.
    func flush() -> [Float] {
        guard let converter else { return [] }
        return convert(nil, with: converter, endOfStream: true)
    }

    private func convert(_ input: AVAudioPCMBuffer?, with converter: AVAudioConverter, endOfStream: Bool) -> [Float] {
        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let inputFrames = Double(input?.frameLength ?? 0)
        // Room for this block plus what the converter may still hold from earlier blocks.
        let capacity = AVAudioFrameCount((inputFrames * ratio).rounded(.up)) + 1_024
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return []
        }
        var pending = input
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if let buffer = pending {
                pending = nil
                inputStatus.pointee = .haveData
                return buffer
            }
            inputStatus.pointee = endOfStream ? .endOfStream : .noDataNow
            return nil
        }
        guard status != .error, conversionError == nil, let channel = output.floatChannelData?[0] else {
            AppLogger.shared.log(.warning, "meeting resampler conversion failed rate=\(inputSampleRate) error=\(conversionError?.localizedDescription ?? "unknown")")
            return []
        }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }
}
