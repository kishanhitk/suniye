import XCTest
@testable import SuniyeAnalytics

final class EventQueueTests: XCTestCase {
    // A fixed, recent base time so the default TTL doesn't evict fresh events.
    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private var baseMs: Int64 { Int64(base.timeIntervalSince1970 * 1000) }

    private func event(id: String, offsetMs: Int64 = 0) -> EncodedEvent {
        EncodedEvent(event: .dictationEmpty, eventID: id, eventTS: baseMs + offsetMs, sessionID: "s")
    }

    func testAppendPeekRemove() {
        let queue = EventQueue(fileURL: TestFixtures.tempQueueURL())
        queue.append(event(id: "a", offsetMs: 0), now: base)
        queue.append(event(id: "b", offsetMs: 1), now: base)
        XCTAssertEqual(queue.count, 2)

        let peeked = queue.peek(max: 10, now: base)
        XCTAssertEqual(peeked.map(\.eventID), ["a", "b"])

        queue.removeOldest(1)
        XCTAssertEqual(queue.peek(max: 10, now: base).map(\.eventID), ["b"])
    }

    func testDurabilityAcrossInstances() {
        let url = TestFixtures.tempQueueURL()
        let first = EventQueue(fileURL: url)
        first.append(event(id: "a", offsetMs: 0), now: base)
        first.append(event(id: "b", offsetMs: 1), now: base)

        // Simulate an abrupt termination: brand-new instance reads the same file.
        let second = EventQueue(fileURL: url)
        XCTAssertEqual(second.peek(max: 10, now: base).map(\.eventID), ["a", "b"])
    }

    func testSizeEvictionDropsOldest() {
        let queue = EventQueue(fileURL: TestFixtures.tempQueueURL(), config: .init(maxEvents: 2))
        queue.append(event(id: "a", offsetMs: 0), now: base)
        queue.append(event(id: "b", offsetMs: 1), now: base)
        queue.append(event(id: "c", offsetMs: 2), now: base)
        XCTAssertEqual(queue.peek(max: 10, now: base).map(\.eventID), ["b", "c"])
        XCTAssertEqual(queue.takeEvictedCounts().size, 1) // dropped by size cap, not TTL
        let afterRead = queue.takeEvictedCounts()
        XCTAssertEqual(afterRead.size, 0) // reset after read
        XCTAssertEqual(afterRead.ttl, 0)
    }

    func testTTLEvictionDropsStale() {
        let queue = EventQueue(fileURL: TestFixtures.tempQueueURL(), config: .init(maxEvents: 100, maxAgeSeconds: 60))
        queue.append(event(id: "old", offsetMs: 0), now: base)
        // 2 minutes later, the old event is beyond the 60s TTL.
        let later = base.addingTimeInterval(120)
        queue.append(EncodedEvent(event: .dictationEmpty, eventID: "new", eventTS: Int64(later.timeIntervalSince1970 * 1000), sessionID: "s"), now: later)
        XCTAssertEqual(queue.peek(max: 10, now: later).map(\.eventID), ["new"])
        XCTAssertEqual(queue.takeEvictedCounts().ttl, 1) // dropped by TTL, not size cap
    }

    func testRemoveAll() {
        let queue = EventQueue(fileURL: TestFixtures.tempQueueURL())
        queue.append(event(id: "a", offsetMs: 0), now: base)
        queue.removeAll()
        XCTAssertEqual(queue.count, 0)
    }
}
