import XCTest
@testable import Suniye

@MainActor
final class PartialTranscriptionSchedulerTests: XCTestCase {
    func testTickLoopDecodesRepeatedlyOnInterval() async {
        let scheduler = PartialTranscriptionScheduler(tickInterval: 0.05)
        let counter = DecodeCounter()

        scheduler.start(
            snapshotProvider: { Self.snapshot },
            decode: { _, _ in
                counter.increment()
                return "partial"
            },
            onPartial: { _ in }
        )
        try? await Task.sleep(nanoseconds: 400_000_000)
        scheduler.stop()

        let count = counter.value
        XCTAssertGreaterThanOrEqual(count, 2, "expected repeated ticks at ~50ms interval")
        XCTAssertLessThanOrEqual(count, 12, "ticks should be throttled by the interval")
    }

    func testTickSkipsWhileDecodeInFlight() async {
        let scheduler = PartialTranscriptionScheduler(tickInterval: 3_600)
        let gate = AsyncGate()
        let counter = DecodeCounter()
        let decodeStarted = expectation(description: "decode started")

        scheduler.start(
            snapshotProvider: { Self.snapshot },
            decode: { _, _ in
                counter.increment()
                decodeStarted.fulfill()
                await gate.wait()
                return "partial"
            },
            onPartial: { _ in }
        )

        let blockedTick = Task { await scheduler.tickNow() }
        await fulfillment(of: [decodeStarted], timeout: 1)

        // A tick while a decode is in flight is skipped, never queued.
        await scheduler.tickNow()
        XCTAssertEqual(counter.value, 1)
        XCTAssertTrue(scheduler.isDecodeInFlight)

        gate.open()
        await blockedTick.value
        XCTAssertEqual(counter.value, 1)
        XCTAssertFalse(scheduler.isDecodeInFlight)
        scheduler.stop()
    }

    func testStopCancelsFutureTicks() async {
        let scheduler = PartialTranscriptionScheduler(tickInterval: 0.03)
        let counter = DecodeCounter()

        scheduler.start(
            snapshotProvider: { Self.snapshot },
            decode: { _, _ in
                counter.increment()
                return "partial"
            },
            onPartial: { _ in }
        )
        try? await Task.sleep(nanoseconds: 200_000_000)
        scheduler.stop()
        XCTAssertFalse(scheduler.isActive)

        let countAtStop = counter.value
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(counter.value, countAtStop)
    }

    func testStopSuppressesLateDecodeResult() async {
        let scheduler = PartialTranscriptionScheduler(tickInterval: 3_600)
        let gate = AsyncGate()
        let decodeStarted = expectation(description: "decode started")
        var publishedPartials: [String] = []

        scheduler.start(
            snapshotProvider: { Self.snapshot },
            decode: { _, _ in
                decodeStarted.fulfill()
                await gate.wait()
                return "stale partial"
            },
            onPartial: { publishedPartials.append($0) }
        )

        let blockedTick = Task { await scheduler.tickNow() }
        await fulfillment(of: [decodeStarted], timeout: 1)
        scheduler.stop()
        gate.open()
        await blockedTick.value

        XCTAssertEqual(publishedPartials, [])
    }

    func testRestartIsNotBlockedByPriorSessionDecode() async {
        let scheduler = PartialTranscriptionScheduler(tickInterval: 3_600)
        let gate = AsyncGate()
        let staleDecodeStarted = expectation(description: "stale decode started")
        let counter = DecodeCounter()
        var publishedPartials: [String] = []

        scheduler.start(
            snapshotProvider: { Self.snapshot },
            decode: { _, _ in
                staleDecodeStarted.fulfill()
                await gate.wait()
                return "stale partial"
            },
            onPartial: { publishedPartials.append($0) }
        )
        let blockedTick = Task { await scheduler.tickNow() }
        await fulfillment(of: [staleDecodeStarted], timeout: 1)

        // Restart while the old session's decode is still in flight: the new
        // session's first tick must not be blocked by the stale decode.
        scheduler.start(
            snapshotProvider: { Self.snapshot },
            decode: { _, _ in
                counter.increment()
                return "fresh partial"
            },
            onPartial: { publishedPartials.append($0) }
        )
        await scheduler.tickNow()
        XCTAssertEqual(counter.value, 1)
        XCTAssertEqual(publishedPartials, ["fresh partial"])

        gate.open()
        await blockedTick.value
        XCTAssertEqual(publishedPartials, ["fresh partial"])
        scheduler.stop()
    }

    func testTickWithoutSamplesSkipsDecode() async {
        let scheduler = PartialTranscriptionScheduler(tickInterval: 3_600)
        let counter = DecodeCounter()
        var snapshots: [AudioSampleSnapshot?] = [nil, AudioSampleSnapshot(samples: [], sampleRate: 16_000)]

        scheduler.start(
            snapshotProvider: { snapshots.isEmpty ? nil : snapshots.removeFirst() },
            decode: { _, _ in
                counter.increment()
                return "partial"
            },
            onPartial: { _ in }
        )
        await scheduler.tickNow()
        await scheduler.tickNow()
        scheduler.stop()

        XCTAssertEqual(counter.value, 0)
    }

    func testTickAfterStopDoesNothing() async {
        let scheduler = PartialTranscriptionScheduler(tickInterval: 3_600)
        let counter = DecodeCounter()

        scheduler.start(
            snapshotProvider: { Self.snapshot },
            decode: { _, _ in
                counter.increment()
                return "partial"
            },
            onPartial: { _ in }
        )
        scheduler.stop()
        await scheduler.tickNow()

        XCTAssertEqual(counter.value, 0)
    }

    private static let snapshot = AudioSampleSnapshot(
        samples: Array(repeating: Float(0.2), count: 1_600),
        sampleRate: 16_000
    )
}

/// Thread-safe counter; scheduler decode closures may hop executors.
private final class DecodeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}
