import Foundation

/// Splits 16 kHz audio that an engine cannot take in one call into chunks cut
/// at the quietest 100 ms inside the last 5 s before each boundary, matching
/// the Cohere Transcribe reference feature extractor. Chunks do not overlap.
struct AudioChunker {
    static let boundarySearchSamples = 5 * 16_000
    static let energyWindowSamples = 1_600

    let maxChunkSamples: Int

    func split(sampleCount: Int, energy: (Range<Int>) -> Float) -> [Range<Int>] {
        guard sampleCount > maxChunkSamples else {
            return sampleCount > 0 ? [0 ..< sampleCount] : []
        }

        var chunks: [Range<Int>] = []
        var start = 0
        while start < sampleCount {
            if start + maxChunkSamples >= sampleCount {
                chunks.append(start ..< sampleCount)
                break
            }
            let boundary = start + maxChunkSamples
            let end = Self.quietestPoint(in: boundary - Self.boundarySearchSamples ..< boundary, energy: energy)
            chunks.append(start ..< end)
            start = end
        }
        return chunks
    }

    func split(_ samples: [Float]) -> [Range<Int>] {
        split(sampleCount: samples.count) { window in
            var sum: Float = 0
            for sample in samples[window] {
                sum += sample * sample
            }
            return (sum / Float(window.count)).squareRoot()
        }
    }

    private static func quietestPoint(in range: Range<Int>, energy: (Range<Int>) -> Float) -> Int {
        var quietest = range.lowerBound
        var minimum = Float.infinity
        for offset in stride(from: 0, to: range.count - energyWindowSamples, by: energyWindowSamples) {
            let window = (range.lowerBound + offset) ..< (range.lowerBound + offset + energyWindowSamples)
            let value = energy(window)
            if value < minimum {
                minimum = value
                quietest = window.lowerBound
            }
        }
        return quietest
    }
}
