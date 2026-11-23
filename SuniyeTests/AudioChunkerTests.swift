import XCTest
@testable import Suniye

final class AudioChunkerTests: XCTestCase {
    private let sampleRate = 16_000
    private let chunker = AudioChunker(maxChunkSamples: 35 * 16_000)

    func testReturnsWholeClipUpToTheChunkLimit() {
        XCTAssertEqual(chunker.split([]), [])
        XCTAssertEqual(chunker.split([Float](repeating: 0.1, count: 16_000)), [0 ..< 16_000])
        XCTAssertEqual(
            chunker.split([Float](repeating: 0.1, count: chunker.maxChunkSamples)),
            [0 ..< chunker.maxChunkSamples]
        )
    }

    func testSplitsAtQuietestWindowBeforeTheBoundary() {
        // 50 s of tone with a silent 200 ms gap at 32 s: inside the 30–35 s search
        // span, so the cut lands on the first 100 ms window of that gap.
        var samples = [Float](repeating: 0.3, count: 50 * sampleRate)
        let gapStart = 32 * sampleRate
        for index in gapStart ..< gapStart + 3_200 {
            samples[index] = 0
        }

        let chunks = chunker.split(samples)

        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0], 0 ..< gapStart)
        XCTAssertEqual(chunks[1], gapStart ..< samples.count)
        XCTAssertEqual(chunks.map(\.count).reduce(0, +), samples.count, "chunks tile the clip without overlap")
    }

    func testCutsAtSearchSpanStartWhenEnergyIsUniform() {
        let ranges = chunker.split(sampleCount: chunker.maxChunkSamples + 1) { _ in 1 }

        XCTAssertEqual(ranges.count, 2)
        XCTAssertEqual(ranges[0], 0 ..< chunker.maxChunkSamples - AudioChunker.boundarySearchSamples)
        XCTAssertEqual(ranges[1].upperBound, chunker.maxChunkSamples + 1)
    }

    func testCoversLongUniformAudioWithoutGaps() {
        let sampleCount = 100 * sampleRate
        let ranges = chunker.split(sampleCount: sampleCount) { _ in 1 }

        XCTAssertEqual(ranges.first?.lowerBound, 0)
        XCTAssertEqual(ranges.last?.upperBound, sampleCount)
        for (previous, next) in zip(ranges, ranges.dropFirst()) {
            XCTAssertEqual(previous.upperBound, next.lowerBound)
            XCTAssertLessThanOrEqual(previous.count, chunker.maxChunkSamples)
        }
    }
}
