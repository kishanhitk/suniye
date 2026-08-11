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
        XCTAssertTrue(
            try XCTUnwrap(messages.first?["content"] as? String)
                .contains("never substitute or inspect an unrelated app")
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
