import XCTest
@testable import SuniyeAnalytics

/// Events from `track` to the ingest endpoint, with only the network stubbed.
final class AnalyticsFlowTests: XCTestCase {
    private static let endpoint = URL(string: "https://ingest.suniye.test/v1/events")!

    override func setUp() {
        super.setUp()
        IngestServer.reset(answer: "{}")
    }

    /// A fresh install: its own queue file and settings, with sharing on.
    private func makeClient(isDebug: Bool = false) -> (AnalyticsClient, EventQueue) {
        let name = "suniye-analytics-\(UUID().uuidString)"
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        addTeardownBlock {
            UserDefaults().removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: root)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [IngestServer.self]
        let queue = EventQueue(fileURL: root.appendingPathComponent("queue.jsonl"))
        let client = AnalyticsClient(
            identity: AnalyticsIdentity(installID: "install-1", appVersion: "0.0.82", build: "82", channel: "stable", isDebug: isDebug, device: nil),
            store: AnalyticsSettingsStore(userDefaults: UserDefaults(suiteName: name)!),
            queue: queue,
            uploader: AnalyticsUploader(endpoint: Self.endpoint, session: URLSession(configuration: configuration))
        )
        return (client, queue)
    }

    /// The client writes the queue file off the caller's thread; a check that
    /// nothing was sent waits for those writes first.
    private func afterPendingWrites() async {
        try? await Task.sleep(for: .milliseconds(200))
    }

    private func track(_ client: AnalyticsClient, _ queue: EventQueue, _ count: Int) async {
        let before = queue.count
        for _ in 0 ..< count {
            client.track(.dictationEmpty(reason: .noSpeech))
        }
        for _ in 0 ..< 200 where queue.count < before + count {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    func testEventsGoOutAsOneBatchAndTheServerCanStopThem() async throws {
        let (client, queue) = makeClient()
        await track(client, queue, 2)
        IngestServer.reset(answer: #"{"disabled":true}"#)

        await client.flush()

        let batch = try XCTUnwrap(IngestServer.bodies.first)
        XCTAssertEqual(IngestServer.bodies.count, 1)
        XCTAssertEqual(batch["install_id"] as? String, "install-1")
        let events = try XCTUnwrap(batch["events"] as? [[String: Any]])
        XCTAssertEqual(events.map { $0["name"] as? String }, ["dictation_empty", "dictation_empty"])
        XCTAssertEqual(queue.count, 0, "sent events leave the queue")

        client.track(.dictationEmpty(reason: .noSpeech))
        await afterPendingWrites()
        await client.flush()
        XCTAssertEqual(queue.count, 0)
        XCTAssertEqual(IngestServer.bodies.count, 1, "the server's kill switch stops sending")
    }

    func testNothingIsSentWhenSharingIsOffOrTheBuildIsADebugBuild() async {
        let (client, queue) = makeClient()
        await track(client, queue, 1)
        client.setEnabled(false)
        client.track(.dictationEmpty(reason: .noSpeech))

        let (debugClient, debugQueue) = makeClient(isDebug: true)
        debugClient.track(.dictationEmpty(reason: .noSpeech))

        await afterPendingWrites()
        await client.flush()
        await debugClient.flush()
        XCTAssertEqual(queue.count, 0, "turning sharing off drops the events not yet sent")
        XCTAssertEqual(debugQueue.count, 0)
        XCTAssertTrue(IngestServer.bodies.isEmpty)
    }
}

/// The ingest endpoint: keeps each JSON body and answers 200 with the set answer.
final class IngestServer: URLProtocol {
    private static let lock = NSLock()
    private static var received: [[String: Any]] = []
    private static var answer = Data()

    static var bodies: [[String: Any]] {
        lock.withLock { received }
    }

    static func reset(answer: String) {
        lock.withLock {
            received = []
            self.answer = Data(answer.utf8)
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let body = request.httpBody ?? request.httpBodyStream.map(Self.read) ?? Data()
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        let answer = Self.lock.withLock {
            Self.received.append(json)
            return Self.answer
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: answer)
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
