import Foundation
import XCTest
@testable import Suniye

final class OpenRouterPostProcessorTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        URLProtocol.registerClass(MockURLProtocol.self)
    }

    override class func tearDown() {
        URLProtocol.unregisterClass(MockURLProtocol.self)
        super.tearDown()
    }

    func testPolishBuildsRequestAndParsesResponse() async throws {
        let session = makeSession()
        let processor = OpenRouterPostProcessor(session: session)

        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/chat/completions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

            let body = try XCTUnwrap(MockURLProtocol.requestBodyData(from: request))
            let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["model"] as? String, "google/gemini-2.5-flash")
            XCTAssertEqual(json["max_tokens"] as? Int, 128)
            let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
            let system = try XCTUnwrap(messages.first(where: { $0["role"] == "system" })?["content"])
            XCTAssertTrue(system.contains("prompt"))
            XCTAssertTrue(system.contains("Keyword hints: swift"))

            let responseJSON: [String: Any] = [
                "choices": [
                    [
                        "message": [
                            "content": "Output: hello world."
                        ],
                    ],
                ],
            ]
            let data = try JSONSerialization.data(withJSONObject: responseJSON)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let config = LLMConfig(
            modelId: "google/gemini-2.5-flash",
            endpointURL: URL(string: "https://openrouter.ai/api/v1/chat/completions")!,
            systemPrompt: "prompt",
            keywords: ["swift"],
            timeoutSeconds: 3,
            maxTokens: 128,
            apiKey: "test-key"
        )

        let output = try await processor.polish(text: "hello world", config: config)
        XCTAssertEqual(output, "hello world.")
    }

    func testPolishUsesConfiguredEndpoint() async throws {
        let session = makeSession()
        let processor = OpenRouterPostProcessor(session: session)

        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/v1/chat/completions")
            let responseJSON: [String: Any] = [
                "choices": [["message": ["content": "hello"]]],
            ]
            let data = try JSONSerialization.data(withJSONObject: responseJSON)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let config = LLMConfig(
            modelId: "google/gemini-2.5-flash",
            endpointURL: URL(string: "https://example.com/v1/chat/completions")!,
            systemPrompt: "prompt",
            keywords: [],
            timeoutSeconds: 3,
            maxTokens: 128,
            apiKey: "test-key"
        )

        let output = try await processor.polish(text: "hello", config: config)
        XCTAssertEqual(output, "hello")
    }

    func testPolishThrowsMalformedForInvalidResponse() async {
        let session = makeSession()
        let processor = OpenRouterPostProcessor(session: session)

        MockURLProtocol.handler = { request in
            let data = Data("{}".utf8)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let config = LLMConfig(
            modelId: "google/gemini-2.5-flash",
            endpointURL: URL(string: "https://openrouter.ai/api/v1/chat/completions")!,
            systemPrompt: "prompt",
            keywords: [],
            timeoutSeconds: 3,
            maxTokens: 128,
            apiKey: "test-key"
        )

        do {
            _ = try await processor.polish(text: "hello", config: config)
            XCTFail("Expected malformed response error")
        } catch let error as LLMPostProcessorError {
            XCTAssertEqual(error.errorDescription, LLMPostProcessorError.malformedResponse.errorDescription)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSanitizeOutputRemovesFencesAndPrefix() {
        let processor = OpenRouterPostProcessor(session: makeSession())
        let raw = "```\nPolished: hello\nworld\n```"
        let output = processor.sanitizeOutput(raw)
        XCTAssertEqual(output, "hello\nworld")
    }

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

private final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    static func requestBodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer {
            stream.close()
        }

        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read < 0 {
                return nil
            }
            if read == 0 {
                break
            }
            data.append(buffer, count: read)
        }

        return data
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.path.hasSuffix("/chat/completions") == true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else {
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
