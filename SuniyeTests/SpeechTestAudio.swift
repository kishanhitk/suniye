import AVFoundation
import Foundation

/// Real-audio inputs for the opt-in engine tests: a recorded WAV resampled to
/// the engine's rate, or speech synthesized on the fly (no fixture to ship).
enum SpeechTestAudio {
    static func loadWAV(path: String, sampleRate: Double) throws -> [Float] {
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            return []
        }
        try file.read(into: source)
        return convert(source, to: target)
    }

    static func synthesizeSpeech(_ text: String, sampleRate: Double) async -> [Float] {
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false) else {
            return []
        }
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text)

        var floats: [Float] = []
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var resumed = false
            synthesizer.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                if pcm.frameLength == 0 {
                    if !resumed { resumed = true; continuation.resume() }
                    return
                }
                floats.append(contentsOf: convert(pcm, to: target))
            }
        }
        _ = synthesizer // keep alive across the write callbacks
        return floats
    }

    /// One-shot convert a PCM buffer to the target format and return its mono float samples.
    static func convert(_ input: AVAudioPCMBuffer, to target: AVAudioFormat) -> [Float] {
        if input.format == target {
            guard let channel = input.floatChannelData?[0] else { return [] }
            return Array(UnsafeBufferPointer(start: channel, count: Int(input.frameLength)))
        }
        guard let converter = AVAudioConverter(from: input.format, to: target) else { return [] }
        let capacity = AVAudioFrameCount((Double(input.frameLength) * target.sampleRate / input.format.sampleRate).rounded(.up)) + 4096
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return [] }

        var fed = false
        var error: NSError?
        _ = converter.convert(to: output, error: &error) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true
            status.pointee = .haveData
            return input
        }
        guard let channel = output.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }
}
