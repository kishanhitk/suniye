import Foundation

/// Linear-interpolation resampler for the always-listening path. The wake-word
/// and VAD models expect 16 kHz; capture devices commonly deliver 44.1/48 kHz.
enum AudioResampler {
    static func resample(_ samples: [Float], from sourceRate: Double, to targetRate: Double) -> [Float] {
        guard sourceRate > 0, targetRate > 0, !samples.isEmpty else {
            return []
        }
        if sourceRate == targetRate {
            return samples
        }
        let ratio = sourceRate / targetRate
        let outputCount = max(1, Int((Double(samples.count) / ratio).rounded(.down)))
        var output = [Float](repeating: 0, count: outputCount)
        for index in 0..<outputCount {
            let position = Double(index) * ratio
            let lower = Int(position)
            let upper = min(lower + 1, samples.count - 1)
            let fraction = Float(position - Double(lower))
            output[index] = samples[lower] * (1 - fraction) + samples[upper] * fraction
        }
        return output
    }
}
