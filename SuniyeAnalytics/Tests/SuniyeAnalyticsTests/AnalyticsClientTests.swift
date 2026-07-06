import XCTest
@testable import SuniyeAnalytics

final class AnalyticsClientTests: XCTestCase {
    private func makeClient(
        isDebug: Bool = false,
        outcome: UploadOutcome = .accepted(nil),
        config: AnalyticsClient.Config = .init(flushThreshold: 1000, maxBatchSize: 10),
        clock: TestClock = TestClock(),
        ids: TestIDGenerator = TestIDGenerator()
    ) -> (AnalyticsClient, MockUploader, EventQueue) {
        let uploader = MockUploader(outcome: outcome)
        let queue = EventQueue(fileURL: TestFixtures.tempQueueURL())
        let store = AnalyticsSettingsStore(userDefaults: TestFixtures.scratchDefaults(), storageKey: "k")
        let client = AnalyticsClient(
            identity: TestFixtures.identity(isDebug: isDebug),
            store: store, queue: queue, uploader: uploader, config: config,
            now: clock.now, makeID: ids.next, sampler: { 0.0 }
        )
        return (client, uploader, queue)
    }

    func testTrackEnqueues() {
        let (client, _, queue) = makeClient()
        client.track(.dictationEmpty)
        client.track(.dictationEmpty)
        XCTAssertEqual(queue.count, 2)
    }

    func testDebugBuildIsNoOp() {
        let (client, _, queue) = makeClient(isDebug: true)
        client.track(.dictationCompleted(TestFixtures.sampleMetrics))
        XCTAssertEqual(queue.count, 0)
    }

    func testDisabledIsNoOpAndClearsQueue() {
        let (client, _, queue) = makeClient()
        client.track(.dictationEmpty)
        XCTAssertEqual(queue.count, 1)
        client.setEnabled(false)
        XCTAssertEqual(queue.count, 0)      // opt-out drops unsent events
        client.track(.dictationEmpty)
        XCTAssertEqual(queue.count, 0)      // and stops emitting
    }

    func testFlushSendsAndClearsOnAccepted() async {
        let (client, uploader, queue) = makeClient(outcome: .accepted(nil))
        client.track(.dictationEmpty)
        client.track(.dictationEmpty)
        await client.flush()
        XCTAssertEqual(uploader.uploadedEventCount, 2)
        XCTAssertEqual(queue.count, 0)
    }

    func testRetryKeepsEvents() async {
        let (client, _, queue) = makeClient(outcome: .retry)
        client.track(.dictationEmpty)
        await client.flush()
        XCTAssertEqual(queue.count, 1)   // kept for a later attempt
    }

    func testRejectedDropsEvents() async {
        let (client, _, queue) = makeClient(outcome: .rejected)
        client.track(.dictationEmpty)
        await client.flush()
        XCTAssertEqual(queue.count, 0)   // poison dropped, no infinite loop
    }

    func testAmbiguousDropsEventsToAvoidDoubleCount() async {
        let (client, _, queue) = makeClient(outcome: .ambiguous)
        client.track(.dictationEmpty)
        await client.flush()
        XCTAssertEqual(queue.count, 0)
    }

    func testAcceptedDirectiveDisablesEmission() async {
        let (client, uploader, queue) = makeClient()
        uploader.outcome = .accepted(KillSwitchDirective(disabled: true))
        client.track(.dictationEmpty)
        await client.flush()               // receives the kill directive
        client.track(.dictationEmpty)      // now suppressed
        XCTAssertEqual(queue.count, 0)
    }

    func testBatchesRespectMaxSize() async {
        let (client, uploader, _) = makeClient(
            outcome: .accepted(nil),
            config: .init(flushThreshold: 1000, maxBatchSize: 2)
        )
        for _ in 0..<5 { client.track(.dictationEmpty) }
        await client.flush()
        XCTAssertEqual(uploader.uploadedEventCount, 5)
        XCTAssertTrue(uploader.batches.allSatisfy { $0.events.count <= 2 })
    }

    func testSessionRotatesAfterInactivity() {
        let clock = TestClock()
        let (client, _, queue) = makeClient(clock: clock)
        client.track(.dictationEmpty)
        clock.advance(10 * 60)             // exceeds 5-min gap
        client.track(.dictationEmpty)
        let sessions = Set(queue.peek(max: 10, now: clock.now()).map(\.sessionID))
        XCTAssertEqual(sessions.count, 2)
    }

    func testEndSessionEmitsSessionEndAndFlushes() async {
        let (client, uploader, _) = makeClient()
        client.track(.dictationEmpty)
        await client.endSession(cleanExit: true)
        let names = uploader.batches.flatMap { $0.events.map(\.name) }
        XCTAssertTrue(names.contains("session_end"))
    }

    func testBatchCarriesIdentity() async {
        let (client, uploader, _) = makeClient()
        client.track(.dictationEmpty)
        await client.flush()
        let batch = uploader.batches.first
        XCTAssertEqual(batch?.installID, "install-1")
        XCTAssertEqual(batch?.schemaVersion, analyticsSchemaVersion)
    }
}
