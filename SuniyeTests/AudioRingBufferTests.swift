import XCTest
@testable import Suniye

/// Direct coverage of the C ring buffer (AudioRingBuffer.c) via the bridging header:
/// creation guards, NULL-argument guards, wrap-around, overflow accounting, planar
/// silence/mixing paths, and concurrent produce/consume ordering.
final class AudioRingBufferTests: XCTestCase {
    // MARK: - Creation

    func testCreateRejectsCapacitiesBelowTwo() {
        XCTAssertNil(SuniyeAudioRingBufferCreate(0))
        XCTAssertNil(SuniyeAudioRingBufferCreate(1))

        guard let ring = SuniyeAudioRingBufferCreate(2) else {
            return XCTFail("Capacity 2 must be accepted")
        }
        SuniyeAudioRingBufferDestroy(ring)
    }

    func testCreateFailsWhenStorageAllocationOverflows() {
        // capacity * sizeof(float) overflows size_t, so the storage calloc must
        // return NULL and Create must free the header and return NULL.
        XCTAssertNil(SuniyeAudioRingBufferCreate(Int.max))
    }

    // MARK: - NULL guards

    func testNullBufferOperationsAreSafeNoOps() {
        SuniyeAudioRingBufferDestroy(nil)
        SuniyeAudioRingBufferReset(nil)
        XCTAssertEqual(SuniyeAudioRingBufferTotalWritten(nil), 0)
        XCTAssertEqual(SuniyeAudioRingBufferDroppedSamples(nil), 0)

        let samples: [Float] = [1, 2, 3]
        let writtenToNil = samples.withUnsafeBufferPointer {
            SuniyeAudioRingBufferWrite(nil, $0.baseAddress, samples.count)
        }
        XCTAssertEqual(writtenToNil, 0)

        var scratch = [Float](repeating: 0, count: 3)
        let readFromNil = scratch.withUnsafeMutableBufferPointer {
            SuniyeAudioRingBufferRead(nil, $0.baseAddress, 3)
        }
        XCTAssertEqual(readFromNil, 0)

        let planarToNil = samples.withUnsafeBufferPointer { buffer in
            let channels: [UnsafePointer<Float>?] = [buffer.baseAddress]
            return channels.withUnsafeBufferPointer {
                SuniyeAudioRingBufferWritePlanar(nil, $0.baseAddress, 1, 3)
            }
        }
        XCTAssertEqual(planarToNil, 0)
    }

    func testNullSampleAndDestinationPointersAreRejected() {
        guard let ring = SuniyeAudioRingBufferCreate(8) else {
            return XCTFail("Expected ring buffer")
        }
        defer { SuniyeAudioRingBufferDestroy(ring) }

        XCTAssertEqual(SuniyeAudioRingBufferWrite(ring, nil, 4), 0)
        XCTAssertEqual(SuniyeAudioRingBufferRead(ring, nil, 4), 0)
        XCTAssertEqual(SuniyeAudioRingBufferWritePlanar(ring, nil, 2, 4), 0)

        // A zero channel count is rejected even with a valid channel table.
        let samples: [Float] = [1, 2]
        let written = samples.withUnsafeBufferPointer { buffer in
            let channels: [UnsafePointer<Float>?] = [buffer.baseAddress]
            return channels.withUnsafeBufferPointer {
                SuniyeAudioRingBufferWritePlanar(ring, $0.baseAddress, 0, 2)
            }
        }
        XCTAssertEqual(written, 0)

        // None of the rejected calls may have advanced any counter.
        XCTAssertEqual(SuniyeAudioRingBufferTotalWritten(ring), 0)
        XCTAssertEqual(SuniyeAudioRingBufferDroppedSamples(ring), 0)
    }

    // MARK: - Reset and counters

    func testResetClearsIndicesAndCounters() {
        guard let ring = SuniyeAudioRingBufferCreate(4) else {
            return XCTFail("Expected ring buffer")
        }
        defer { SuniyeAudioRingBufferDestroy(ring) }

        XCTAssertEqual(write([1, 2, 3, 4, 5, 6], to: ring), 4)
        XCTAssertEqual(SuniyeAudioRingBufferTotalWritten(ring), 4)
        XCTAssertEqual(SuniyeAudioRingBufferDroppedSamples(ring), 2)

        SuniyeAudioRingBufferReset(ring)

        XCTAssertEqual(SuniyeAudioRingBufferTotalWritten(ring), 0)
        XCTAssertEqual(SuniyeAudioRingBufferDroppedSamples(ring), 0)
        XCTAssertEqual(read(4, from: ring), [])
        XCTAssertEqual(write([7, 8], to: ring), 2)
        XCTAssertEqual(read(4, from: ring), [7, 8])
    }

    func testTotalWrittenAccumulatesAcrossInterleavedAndPlanarWrites() {
        guard let ring = SuniyeAudioRingBufferCreate(16) else {
            return XCTFail("Expected ring buffer")
        }
        defer { SuniyeAudioRingBufferDestroy(ring) }

        XCTAssertEqual(SuniyeAudioRingBufferTotalWritten(ring), 0)
        XCTAssertEqual(write([1, 2, 3], to: ring), 3)
        XCTAssertEqual(SuniyeAudioRingBufferTotalWritten(ring), 3)

        let samples: [Float] = [4, 5]
        let written = samples.withUnsafeBufferPointer { buffer in
            let channels: [UnsafePointer<Float>?] = [buffer.baseAddress]
            return channels.withUnsafeBufferPointer {
                SuniyeAudioRingBufferWritePlanar(ring, $0.baseAddress, 1, 2)
            }
        }
        XCTAssertEqual(written, 2)
        XCTAssertEqual(SuniyeAudioRingBufferTotalWritten(ring), 5)
    }

    // MARK: - Wrap-around and overflow

    func testInterleavedWriteWrapsAroundStorageBoundary() {
        guard let ring = SuniyeAudioRingBufferCreate(4) else {
            return XCTFail("Expected ring buffer")
        }
        defer { SuniyeAudioRingBufferDestroy(ring) }

        XCTAssertEqual(write([1, 2, 3], to: ring), 3)
        XCTAssertEqual(read(3, from: ring), [1, 2, 3])
        // Write index is now 3 of a 4-slot buffer: this write must split into a
        // tail copy of 1 sample plus a wrapped head copy of 3 samples.
        XCTAssertEqual(write([4, 5, 6, 7], to: ring), 4)
        XCTAssertEqual(read(4, from: ring), [4, 5, 6, 7])
        XCTAssertEqual(SuniyeAudioRingBufferDroppedSamples(ring), 0)
    }

    func testOverflowTruncatesWriteAndCountsDroppedSamples() {
        guard let ring = SuniyeAudioRingBufferCreate(4) else {
            return XCTFail("Expected ring buffer")
        }
        defer { SuniyeAudioRingBufferDestroy(ring) }

        XCTAssertEqual(write([1, 2, 3, 4], to: ring), 4)
        // Buffer full: everything is dropped until the reader catches up.
        XCTAssertEqual(write([5, 6], to: ring), 0)
        XCTAssertEqual(SuniyeAudioRingBufferDroppedSamples(ring), 2)
        XCTAssertEqual(read(4, from: ring), [1, 2, 3, 4])
        // Partial room: prefix is accepted, the excess is dropped.
        XCTAssertEqual(write([7, 8, 9, 10, 11], to: ring), 4)
        XCTAssertEqual(SuniyeAudioRingBufferDroppedSamples(ring), 3)
        XCTAssertEqual(read(4, from: ring), [7, 8, 9, 10])
    }

    // MARK: - Planar writes

    func testPlanarWriteWithAllNullChannelsWritesSilence() {
        guard let ring = SuniyeAudioRingBufferCreate(8) else {
            return XCTFail("Expected ring buffer")
        }
        defer { SuniyeAudioRingBufferDestroy(ring) }

        // Pre-fill with non-zero values so silence is observable.
        XCTAssertEqual(write([9, 9, 9], to: ring), 3)
        XCTAssertEqual(read(3, from: ring), [9, 9, 9])

        let channels: [UnsafePointer<Float>?] = [nil, nil]
        let written = channels.withUnsafeBufferPointer {
            SuniyeAudioRingBufferWritePlanar(ring, $0.baseAddress, 2, 3)
        }

        XCTAssertEqual(written, 3)
        XCTAssertEqual(read(3, from: ring), [0, 0, 0])
    }

    func testPlanarNullChannelSilenceWrapsAroundStorageBoundary() {
        guard let ring = SuniyeAudioRingBufferCreate(4) else {
            return XCTFail("Expected ring buffer")
        }
        defer { SuniyeAudioRingBufferDestroy(ring) }

        // Advance write index to 2 so a 4-frame silent write must wrap: 2 frames
        // memset at the tail, 2 frames memset at the head.
        XCTAssertEqual(write([9, 9], to: ring), 2)
        XCTAssertEqual(read(2, from: ring), [9, 9])

        let channels: [UnsafePointer<Float>?] = [nil]
        let written = channels.withUnsafeBufferPointer {
            SuniyeAudioRingBufferWritePlanar(ring, $0.baseAddress, 1, 4)
        }

        XCTAssertEqual(written, 4)
        XCTAssertEqual(read(4, from: ring), [0, 0, 0, 0])
    }

    func testPlanarWriteIgnoresNullChannelInSingleReadableDownmix() {
        guard let ring = SuniyeAudioRingBufferCreate(8) else {
            return XCTFail("Expected ring buffer")
        }
        defer { SuniyeAudioRingBufferDestroy(ring) }

        // Two channel slots but only one non-NULL: the readable channel is copied
        // verbatim (no averaging against the missing channel).
        let mono: [Float] = [0.5, -0.5, 0.25]
        let written = mono.withUnsafeBufferPointer { buffer in
            let channels: [UnsafePointer<Float>?] = [nil, buffer.baseAddress]
            return channels.withUnsafeBufferPointer {
                SuniyeAudioRingBufferWritePlanar(ring, $0.baseAddress, 2, 3)
            }
        }

        XCTAssertEqual(written, 3)
        XCTAssertEqual(read(3, from: ring), [0.5, -0.5, 0.25])
    }

    func testPlanarMultiChannelDownmixWrapsAroundStorageBoundary() {
        guard let ring = SuniyeAudioRingBufferCreate(4) else {
            return XCTFail("Expected ring buffer")
        }
        defer { SuniyeAudioRingBufferDestroy(ring) }

        // Advance write index to 3 so the frame-by-frame mixing loop must wrap.
        XCTAssertEqual(write([9, 9, 9], to: ring), 3)
        XCTAssertEqual(read(3, from: ring), [9, 9, 9])

        let left: [Float] = [1, 0, -1]
        let right: [Float] = [0, 1, 0]
        let written = left.withUnsafeBufferPointer { leftBuffer in
            right.withUnsafeBufferPointer { rightBuffer in
                let channels: [UnsafePointer<Float>?] = [leftBuffer.baseAddress, rightBuffer.baseAddress]
                return channels.withUnsafeBufferPointer {
                    SuniyeAudioRingBufferWritePlanar(ring, $0.baseAddress, 2, 3)
                }
            }
        }

        XCTAssertEqual(written, 3)
        XCTAssertEqual(read(3, from: ring), [0.5, 0.5, -0.5])
    }

    func testPlanarDownmixSkipsNullChannelAmongMultipleReadable() {
        guard let ring = SuniyeAudioRingBufferCreate(8) else {
            return XCTFail("Expected ring buffer")
        }
        defer { SuniyeAudioRingBufferDestroy(ring) }

        // Three slots, middle NULL: mix divides by the 2 readable channels only.
        let left: [Float] = [1, 1]
        let right: [Float] = [0, 1]
        let written = left.withUnsafeBufferPointer { leftBuffer in
            right.withUnsafeBufferPointer { rightBuffer in
                let channels: [UnsafePointer<Float>?] = [
                    leftBuffer.baseAddress,
                    nil,
                    rightBuffer.baseAddress,
                ]
                return channels.withUnsafeBufferPointer {
                    SuniyeAudioRingBufferWritePlanar(ring, $0.baseAddress, 3, 2)
                }
            }
        }

        XCTAssertEqual(written, 2)
        XCTAssertEqual(read(2, from: ring), [0.5, 1])
    }

    // MARK: - Concurrency

    func testConcurrentProduceConsumePreservesOrderAndAccountsForEverySample() {
        guard let ring = SuniyeAudioRingBufferCreate(256) else {
            return XCTFail("Expected ring buffer")
        }
        defer { SuniyeAudioRingBufferDestroy(ring) }

        let chunkCount = 400
        let chunkSize = 37
        let attempted = chunkCount * chunkSize
        let producerFinished = AtomicFlag()

        DispatchQueue.global(qos: .userInitiated).async {
            var next: Float = 0
            for _ in 0 ..< chunkCount {
                var chunk = [Float]()
                chunk.reserveCapacity(chunkSize)
                for _ in 0 ..< chunkSize {
                    chunk.append(next)
                    next += 1
                }
                chunk.withUnsafeBufferPointer {
                    _ = SuniyeAudioRingBufferWrite(ring, $0.baseAddress, chunkSize)
                }
            }
            producerFinished.set()
        }

        var consumed: [Float] = []
        var scratch = [Float](repeating: 0, count: 64)
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            let count = scratch.withUnsafeMutableBufferPointer {
                SuniyeAudioRingBufferRead(ring, $0.baseAddress, 64)
            }
            if count > 0 {
                consumed.append(contentsOf: scratch.prefix(count))
                continue
            }
            if producerFinished.isSet {
                // One final drain after the producer is done; an empty read then
                // means the buffer is exhausted.
                let final = scratch.withUnsafeMutableBufferPointer {
                    SuniyeAudioRingBufferRead(ring, $0.baseAddress, 64)
                }
                if final == 0 {
                    break
                }
                consumed.append(contentsOf: scratch.prefix(final))
            }
        }

        // Drops only ever truncate the tail of a write, so the consumed stream must
        // remain strictly increasing, and written + dropped must equal attempted.
        for index in 1 ..< consumed.count {
            if consumed[index] <= consumed[index - 1] {
                return XCTFail(
                    "Out-of-order sample at \(index): \(consumed[index - 1]) then \(consumed[index])"
                )
            }
        }
        XCTAssertEqual(UInt64(consumed.count), SuniyeAudioRingBufferTotalWritten(ring))
        XCTAssertEqual(
            SuniyeAudioRingBufferTotalWritten(ring) + SuniyeAudioRingBufferDroppedSamples(ring),
            UInt64(attempted)
        )
        XCTAssertGreaterThan(consumed.count, 0)
    }

    // MARK: - Helpers

    private func write(_ samples: [Float], to ring: OpaquePointer) -> Int {
        samples.withUnsafeBufferPointer {
            SuniyeAudioRingBufferWrite(ring, $0.baseAddress, samples.count)
        }
    }

    private func read(_ count: Int, from ring: OpaquePointer) -> [Float] {
        var result = Array(repeating: Float(0), count: count)
        let readCount = result.withUnsafeMutableBufferPointer {
            SuniyeAudioRingBufferRead(ring, $0.baseAddress, count)
        }
        return Array(result.prefix(readCount))
    }
}

private final class AtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
