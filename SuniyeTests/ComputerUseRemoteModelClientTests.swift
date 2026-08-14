import XCTest
@testable import Suniye

final class ComputerUseRemoteModelClientTests: XCTestCase {
    override func tearDown() {
        ComputerUseModelURLProtocol.handler = nil
        super.tearDown()
    }

    func testProviderRequestUsesSelectedModelOrderedMessagesAndExactTools() async throws {
        var capturedBody: [String: Any]?
        ComputerUseModelURLProtocol.handler = { request in
            capturedBody = try XCTUnwrap(
                JSONSerialization.jsonObject(with: try Self.requestBody(request))
                    as? [String: Any]
            )
            let response: [String: Any] = [
                "choices": [[
                    "message": [
                        "content": NSNull(),
                        "tool_calls": [[
                            "id": "call-state",
                            "type": "function",
                            "function": [
                                "name": "get_app_state",
                                "arguments": #"{"app":"Calculator"}"#,
                            ],
                        ]],
                    ],
                ]],
            ]
            return try Self.response(for: request, json: response)
        }
        let configuration = ComputerUseRemoteModelConfiguration(
            endpointURL: URL(string: "https://example.com/v1/chat/completions")!,
            modelID: "gpt-5.6-luna",
            apiKey: "secret"
        )
        let client = ComputerUseRemoteModelClient(
            configuration: configuration,
            completionClient: ChatCompletionClient(session: makeSession())
        )

        let result = try await client.respond(
            to: [.text(role: .user, text: "Read the Calculator result.")]
        )

        XCTAssertEqual(
            result,
            .toolCall(
                id: "call-state",
                name: "get_app_state",
                arguments: #"{"app":"Calculator"}"#
            )
        )
        let body = try XCTUnwrap(capturedBody)
        XCTAssertEqual(body["model"] as? String, "gpt-5.6-luna")
        XCTAssertEqual(body["parallel_tool_calls"] as? Bool, false)
        XCTAssertEqual(body["stream"] as? Bool, false)
        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        XCTAssertEqual(
            tools.compactMap { ($0["function"] as? [String: Any])?["name"] as? String },
            ComputerUseToolName.allCases.map(\.rawValue)
        )
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.compactMap { $0["role"] as? String }, ["system", "user"])
        let systemInstructions = try XCTUnwrap(messages.first?["content"] as? String)
        XCTAssertTrue(systemInstructions.contains("never substitute or inspect an unrelated app"))
        XCTAssertTrue(
            systemInstructions.contains(
                "A target appearing in a list, search result, menu, or tree proves only that"
            )
        )
        XCTAssertTrue(
            systemInstructions.contains(
                "You may not report success for a requested UI change after an observation-only path"
            )
        )
        XCTAssertTrue(
            systemInstructions.contains(
                "confirm the requested result in the fresh state captured after that action"
            )
        )
        XCTAssertTrue(
            systemInstructions.contains(
                "A focused or selected item is not proof that it was activated or opened"
            )
        )
        XCTAssertTrue(
            systemInstructions.contains(
                "If a click focuses the intended control without activating it, press Return"
            )
        )
        XCTAssertTrue(
            systemInstructions.contains(
                "do not repeat an action that left the observed state unchanged"
            )
        )
        XCTAssertTrue(
            systemInstructions.contains(
                "The current app content may be unrelated to the user's request"
            )
        )
        XCTAssertTrue(
            systemInstructions.contains(
                "Match the requested subject before acting on a visible result"
            )
        )
        XCTAssertEqual(messages.last?["content"] as? String, "Read the Calculator result.")

    }

    func testProviderRequestPreservesToolResultAndScreenshotOrdering() async throws {
        var capturedMessages: [[String: Any]] = []
        ComputerUseModelURLProtocol.handler = { request in
            let body = try XCTUnwrap(
                JSONSerialization.jsonObject(with: try Self.requestBody(request))
                    as? [String: Any]
            )
            capturedMessages = try XCTUnwrap(body["messages"] as? [[String: Any]])
            return try Self.response(
                for: request,
                json: ["choices": [["message": ["content": "The result is 42."]]]]
            )
        }
        let client = ComputerUseRemoteModelClient(
            configuration: ComputerUseRemoteModelConfiguration(
                endpointURL: URL(string: "https://example.com/v1/chat/completions")!,
                modelID: "model",
                apiKey: "secret"
            ),
            completionClient: ChatCompletionClient(session: makeSession())
        )

        let result = try await client.respond(
            to: [
                .text(role: .user, text: "Read the result."),
                .toolCall(
                    id: "call-state",
                    name: "get_app_state",
                    arguments: #"{"app":"Calculator"}"#
                ),
                .toolResult(
                    id: "call-state",
                    content: #"{"app":"Calculator","text":"0 AXStaticText: 42"}"#
                ),
                .image(
                    role: .user,
                    text: "Current Calculator screenshot.",
                    dataURL: "data:image/jpeg;base64,AQID"
                ),
            ]
        )

        XCTAssertEqual(result, .text("The result is 42."))
        XCTAssertEqual(
            capturedMessages.compactMap { $0["role"] as? String },
            ["system", "user", "assistant", "tool", "user"]
        )
        let assistant = capturedMessages[2]
        let toolCalls = try XCTUnwrap(assistant["tool_calls"] as? [[String: Any]])
        XCTAssertEqual(toolCalls.first?["id"] as? String, "call-state")
        let tool = capturedMessages[3]
        XCTAssertEqual(tool["tool_call_id"] as? String, "call-state")
        let imageContent = try XCTUnwrap(capturedMessages[4]["content"] as? [[String: Any]])
        XCTAssertEqual(imageContent.compactMap { $0["type"] as? String }, ["text", "image_url"])
        let imageURL = try XCTUnwrap(imageContent[1]["image_url"] as? [String: Any])
        XCTAssertEqual(imageURL["url"] as? String, "data:image/jpeg;base64,AQID")
    }

    func testTransientNetworkFailureUsesReferenceRequestRetryBudget() async throws {
        var requestCount = 0
        ComputerUseModelURLProtocol.handler = { request in
            requestCount += 1
            if requestCount <= 4 {
                throw URLError(.networkConnectionLost)
            }
            return try Self.response(
                for: request,
                json: ["choices": [["message": ["content": "Recovered."]]]]
            )
        }
        let sleeper = RecordingComputerUseModelRetrySleeper()
        let client = ComputerUseRemoteModelClient(
            configuration: ComputerUseRemoteModelConfiguration(
                endpointURL: URL(string: "https://example.com/v1/chat/completions")!,
                modelID: "model",
                apiKey: "secret"
            ),
            completionClient: ChatCompletionClient(session: makeSession()),
            retrySleeper: sleeper,
            retryJitter: { 1 }
        )

        let result = try await client.respond(to: [.text(role: .user, text: "Continue.")])
        let delays = await sleeper.delays

        XCTAssertEqual(result, .text("Recovered."))
        XCTAssertEqual(requestCount, 5)
        XCTAssertEqual(
            delays,
            [.milliseconds(200), .milliseconds(400), .milliseconds(800), .milliseconds(1_600)]
        )
    }

    func testTransientMalformedProviderResponseIsRetriedWithoutReplayingAnAction() async throws {
        var requestCount = 0
        ComputerUseModelURLProtocol.handler = { request in
            requestCount += 1
            if requestCount == 1 {
                return try Self.response(for: request, json: ["choices": []])
            }
            return try Self.response(
                for: request,
                json: ["choices": [["message": ["content": "Recovered."]]]]
            )
        }
        let sleeper = RecordingComputerUseModelRetrySleeper()
        let client = ComputerUseRemoteModelClient(
            configuration: ComputerUseRemoteModelConfiguration(
                endpointURL: URL(string: "https://example.com/v1/chat/completions")!,
                modelID: "model",
                apiKey: "secret"
            ),
            completionClient: ChatCompletionClient(session: makeSession()),
            retrySleeper: sleeper,
            retryJitter: { 1 }
        )

        let result = try await client.respond(to: [.text(role: .user, text: "Continue.")])
        let delays = await sleeper.delays

        XCTAssertEqual(result, .text("Recovered."))
        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(delays, [.milliseconds(200)])
    }

    func testNonRetryableProviderFailureIsNotReplayed() async {
        var requestCount = 0
        ComputerUseModelURLProtocol.handler = { request in
            requestCount += 1
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: XCTUnwrap(request.url),
                    statusCode: 429,
                    httpVersion: nil,
                    headerFields: nil
                )
            )
            return (response, Data("{}".utf8))
        }
        let sleeper = RecordingComputerUseModelRetrySleeper()
        let client = ComputerUseRemoteModelClient(
            configuration: ComputerUseRemoteModelConfiguration(
                endpointURL: URL(string: "https://example.com/v1/chat/completions")!,
                modelID: "model",
                apiKey: "secret"
            ),
            completionClient: ChatCompletionClient(session: makeSession()),
            retrySleeper: sleeper,
            retryJitter: { 1 }
        )

        do {
            _ = try await client.respond(to: [.text(role: .user, text: "Continue.")])
            XCTFail("Expected the provider failure")
        } catch let error as ComputerUseModelError {
            XCTAssertEqual(
                error,
                .requestFailed("LLM provider error: http_429")
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let delays = await sleeper.delays
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(delays, [])
    }

    func testRetryPolicyMatchesProviderFailureClassificationAndBackoffBounds() {
        let policy = ComputerUseModelRetryPolicy.referenceAligned

        XCTAssertTrue(policy.shouldRetry(.network("lost")))
        XCTAssertTrue(policy.shouldRetry(.timeout))
        XCTAssertTrue(policy.shouldRetry(.provider("http_500")))
        XCTAssertTrue(policy.shouldRetry(.provider("http_599")))
        XCTAssertFalse(policy.shouldRetry(.provider("http_429")))
        XCTAssertFalse(policy.shouldRetry(.provider("unavailable")))
        XCTAssertFalse(policy.shouldRetry(.invalidConfiguration("missing")))
        XCTAssertFalse(policy.shouldRetry(.unauthorized))
        XCTAssertTrue(policy.shouldRetry(.malformedResponse))
        XCTAssertTrue(policy.shouldRetry(.emptyOutput))
        XCTAssertEqual(policy.delay(afterFailedAttempt: 0, jitter: 0), .milliseconds(180))
        XCTAssertEqual(policy.delay(afterFailedAttempt: 0, jitter: 2), .milliseconds(220))
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ComputerUseModelURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func response(
        for request: URLRequest,
        json: [String: Any]
    ) throws -> (URLResponse, Data) {
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
        )
        return (response, try JSONSerialization.data(withJSONObject: json))
    }

    private static func requestBody(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody {
            return body
        }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else {
                throw XCTSkip("Could not read request body")
            }
            if count == 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }
}

private actor RecordingComputerUseModelRetrySleeper: ComputerUseModelRetrySleeping {
    private(set) var delays: [Duration] = []

    func sleep(for duration: Duration) async throws {
        delays.append(duration)
    }
}

private final class ComputerUseModelURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (URLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
