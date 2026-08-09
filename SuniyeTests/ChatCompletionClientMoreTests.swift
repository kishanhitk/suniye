import Foundation
import XCTest
@testable import Suniye

final class ChatCompletionClientMoreTests: XCTestCase {
    override func tearDown() {
        ScriptedResponseURLProtocol.handler = nil
        super.tearDown()
    }

    func testNonHTTPResponseThrowsMalformedResponse() async {
        let client = makeClient()
        ScriptedResponseURLProtocol.handler = { request in
            let response = URLResponse(
                url: request.url!,
                mimeType: "application/json",
                expectedContentLength: 2,
                textEncodingName: nil
            )
            return (response, Data("{}".utf8))
        }

        await assertMalformed(client: client)
    }

    func testMessageContentPartsAreJoined() async throws {
        let client = makeClient()
        ScriptedResponseURLProtocol.handler = { request in
            let json: [String: Any] = [
                "choices": [
                    [
                        "message": [
                            "content": [
                                ["text": "part one"],
                                ["text": "part two"],
                            ],
                        ],
                    ],
                ],
            ]
            return try Self.httpResponse(for: request, json: json)
        }

        let output = try await client.complete(
            endpointURL: endpointURL,
            apiKey: "key",
            payload: makePayload(),
            timeoutSeconds: 3
        )

        XCTAssertEqual(output, "part one\npart two")
    }

    func testEmptyChoicesThrowsMalformedResponse() async {
        let client = makeClient()
        ScriptedResponseURLProtocol.handler = { request in
            try Self.httpResponse(for: request, json: ["choices": []])
        }

        await assertMalformed(client: client)
    }

    func testLegacyTextChoiceIsReturned() async throws {
        let client = makeClient()
        ScriptedResponseURLProtocol.handler = { request in
            try Self.httpResponse(for: request, json: ["choices": [["text": "legacy completion"]]])
        }

        let output = try await client.complete(
            endpointURL: endpointURL,
            apiKey: "key",
            payload: makePayload(),
            timeoutSeconds: 3
        )

        XCTAssertEqual(output, "legacy completion")
    }

    func testChoiceWithoutUsableContentThrowsMalformedResponse() async {
        let client = makeClient()
        ScriptedResponseURLProtocol.handler = { request in
            try Self.httpResponse(for: request, json: ["choices": [["text": ""]]])
        }

        await assertMalformed(client: client)
    }

    func testStructuredToolCallResultPreservesItsIdentityAndArguments() async throws {
        let client = makeClient()
        ScriptedResponseURLProtocol.handler = { request in
            let json: [String: Any] = [
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
            return try Self.httpResponse(for: request, json: json)
        }

        let result = try await client.completeResult(
            endpointURL: endpointURL,
            apiKey: "key",
            requestBody: Data("{}".utf8),
            timeoutSeconds: 3
        )

        XCTAssertEqual(
            result,
            ChatCompletionResult(
                text: nil,
                toolCalls: [
                    ChatCompletionToolCall(
                        id: "call-state",
                        name: "get_app_state",
                        arguments: #"{"app":"Calculator"}"#
                    ),
                ]
            )
        )
    }

    // MARK: - Helpers

    private var endpointURL: URL {
        URL(string: "https://example.com/v1/chat/completions")!
    }

    private func makeClient() -> ChatCompletionClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScriptedResponseURLProtocol.self]
        return ChatCompletionClient(session: URLSession(configuration: config))
    }

    private func makePayload() -> ChatCompletionPayload {
        ChatCompletionPayload(
            model: "test",
            messages: [ChatCompletionMessage(role: "user", content: "hello")],
            maxTokens: 8
        )
    }

    private static func httpResponse(for request: URLRequest, json: [String: Any]) throws -> (URLResponse, Data) {
        let data = try JSONSerialization.data(withJSONObject: json)
        let response: URLResponse = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, data)
    }

    private func assertMalformed(client: ChatCompletionClient) async {
        do {
            _ = try await client.complete(
                endpointURL: endpointURL,
                apiKey: "key",
                payload: makePayload(),
                timeoutSeconds: 3
            )
            XCTFail("Expected malformed response")
        } catch let error as LLMPostProcessorError {
            XCTAssertEqual(error.logValue, LLMPostProcessorError.malformedResponse.logValue)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private final class ScriptedResponseURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (URLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = ScriptedResponseURLProtocol.handler else {
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
