import XCTest
@testable import Suniye

/// Exercises cancellation and timeout through the REAL ChatCompletionClient +
/// URLSession stack (via a hanging URLProtocol), so a regression in the
/// cancellation forwarding inside `withTimeout` cannot hide behind
/// cancellation-responsive test fakes.
final class ChatCompletionClientTests: XCTestCase {
    override func tearDown() {
        HangingURLProtocol.reset()
        super.tearDown()
    }

    func testCallerCancellationSurfacesAsCancellationErrorAndAbortsRequest() async {
        let client = ChatCompletionClient(session: makeHangingSession())

        let request = Task<Error?, Never> {
            do {
                _ = try await client.complete(
                    endpointURL: URL(string: "http://127.0.0.1:9/v1/chat/completions")!,
                    apiKey: "key",
                    payload: makePayload(),
                    timeoutSeconds: 30
                )
                return nil
            } catch {
                return error
            }
        }

        await HangingURLProtocol.waitUntilLoading()
        request.cancel()
        let error = await request.value

        XCTAssertTrue(error is CancellationError, "expected CancellationError, got \(String(describing: error))")
        XCTAssertTrue(HangingURLProtocol.stopLoadingCalled, "cancellation must abort the underlying URL request")
    }

    func testTimeoutWithoutCallerCancellationSurfacesAsTimeout() async {
        let client = ChatCompletionClient(session: makeHangingSession())

        do {
            _ = try await client.complete(
                endpointURL: URL(string: "http://127.0.0.1:9/v1/chat/completions")!,
                apiKey: "key",
                payload: makePayload(),
                timeoutSeconds: 0.2
            )
            XCTFail("Expected timeout")
        } catch let error as LLMPostProcessorError {
            XCTAssertEqual(error.logValue, LLMPostProcessorError.timeout.logValue)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makePayload() -> ChatCompletionPayload {
        ChatCompletionPayload(
            model: "test",
            messages: [ChatCompletionMessage(role: "user", content: "hello")],
            maxTokens: 8
        )
    }

    private func makeHangingSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HangingURLProtocol.self]
        return URLSession(configuration: config)
    }
}

/// Never responds; records when loading starts and when the request is torn down.
private final class HangingURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var _loadingStarted = false
    private static var _stopLoadingCalled = false

    static var stopLoadingCalled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _stopLoadingCalled
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        _loadingStarted = false
        _stopLoadingCalled = false
    }

    static func waitUntilLoading() async {
        for _ in 0 ..< 500 {
            lock.lock()
            let started = _loadingStarted
            lock.unlock()
            if started {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        Self._loadingStarted = true
        Self.lock.unlock()
        // Intentionally never responds.
    }

    override func stopLoading() {
        Self.lock.lock()
        Self._stopLoadingCalled = true
        Self.lock.unlock()
    }
}
