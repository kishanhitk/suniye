import XCTest
@testable import Suniye

@MainActor
final class PartialTranscriptionSchedulerTests: XCTestCase {
    func testTickLoopDecodesRepeatedlyOnInterval() async {
        let scheduler = PartialTranscriptionScheduler(tickInterval: 0.05)
        let counter = DecodeCounter()

        scheduler.start(
            snapshotProvider: { (Self.samples, 16_000) },
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
            snapshotProvider: { (Self.samples, 16_000) },
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
            snapshotProvider: { (Self.samples, 16_000) },
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
            snapshotProvider: { (Self.samples, 16_000) },
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

    func testTickWithoutSamplesSkipsDecode() async {
        let scheduler = PartialTranscriptionScheduler(tickInterval: 3_600)
        let counter = DecodeCounter()
        var snapshots: [(samples: [Float], sampleRate: Int)?] = [nil, ([], 16_000)]

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
            snapshotProvider: { (Self.samples, 16_000) },
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

    func testPreviewTailKeepsShortTextIntact() {
        XCTAssertEqual(PartialTranscriptionScheduler.previewTail("hello world"), "hello world")
        XCTAssertEqual(PartialTranscriptionScheduler.previewTail("  padded  "), "padded")
        XCTAssertEqual(PartialTranscriptionScheduler.previewTail(""), "")
    }

    func testPreviewTailTruncatesLongTextToSuffix() {
        let text = String(repeating: "a", count: 120) + String(repeating: "b", count: 80)
        let tail = PartialTranscriptionScheduler.previewTail(text)

        XCTAssertEqual(tail, "…" + String(repeating: "b", count: 80))
        XCTAssertEqual(tail.count, PartialTranscriptionScheduler.previewTailMaxCharacters + 1)
    }

    private static let samples = Array(repeating: Float(0.2), count: 1_600)
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
