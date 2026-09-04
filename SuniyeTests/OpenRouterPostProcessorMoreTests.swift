import Foundation
import XCTest
@testable import Suniye

final class OpenRouterPostProcessorMoreTests: XCTestCase {
    override func tearDown() {
        MoreTestsChatURLProtocol.handler = nil
        super.tearDown()
    }

    // MARK: - truncation (KIS-214)

    func testPolishRejectsOutputTheProviderCutShort() async {
        let processor = OpenRouterPostProcessor(session: makeSession())
        MoreTestsChatURLProtocol.handler = { request in
            try MoreTestsChatURLProtocol.jsonResponse(for: request, content: "Only the first half of the", finishReason: "length")
        }

        do {
            _ = try await processor.polish(text: "raw text", config: makeConfig())
            XCTFail("Expected outputTruncated")
        } catch let error as LLMPostProcessorError {
            XCTAssertEqual(error.logValue, "output_truncated")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGenerateRejectsOutputTheProviderCutShort() async {
        let processor = OpenRouterPostProcessor(session: makeSession())
        MoreTestsChatURLProtocol.handler = { request in
            try MoreTestsChatURLProtocol.jsonResponse(for: request, content: "Rewritten up to", finishReason: "length")
        }

        do {
            _ = try await processor.generate(instructions: "sys", userText: "user", config: makeConfig())
            XCTFail("Expected outputTruncated")
        } catch let error as LLMPostProcessorError {
            XCTAssertEqual(error.logValue, "output_truncated")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - generate

    func testGenerateBuildsEditModeRequestAndSanitizesOutput() async throws {
        let processor = OpenRouterPostProcessor(session: makeSession())

        MoreTestsChatURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/chat/completions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

            let body = try XCTUnwrap(MoreTestsChatURLProtocol.requestBodyData(from: request))
            let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["model"] as? String, "google/gemini-2.5-flash")
            XCTAssertNil(json["max_tokens"])
            let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
            XCTAssertEqual(messages.first?["role"], "system")
            XCTAssertEqual(messages.first?["content"], "Rewrite instructions.")
            XCTAssertEqual(messages.last?["role"], "user")
            XCTAssertEqual(messages.last?["content"], "user payload")

            return try MoreTestsChatURLProtocol.jsonResponse(
                for: request,
                content: "  rewritten output  "
            )
        }

        let output = try await processor.generate(
            instructions: "Rewrite instructions.",
            userText: "user payload",
            config: makeConfig()
        )

        XCTAssertEqual(output, "rewritten output")
    }

    func testGenerateThrowsEmptyOutputForWhitespaceResponse() async {
        let processor = OpenRouterPostProcessor(session: makeSession())

        MoreTestsChatURLProtocol.handler = { request in
            try MoreTestsChatURLProtocol.jsonResponse(for: request, content: "   ")
        }

        do {
            _ = try await processor.generate(instructions: "sys", userText: "user", config: makeConfig())
            XCTFail("Expected empty output")
        } catch let error as LLMPostProcessorError {
            XCTAssertEqual(error.logValue, LLMPostProcessorError.emptyOutput.logValue)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - testSetup

    func testSetupThrowsEmptyOutputForWhitespaceResponse() async {
        let processor = OpenRouterPostProcessor(session: makeSession())

        MoreTestsChatURLProtocol.handler = { request in
            try MoreTestsChatURLProtocol.jsonResponse(for: request, content: " \n ")
        }

        do {
            try await processor.testSetup(config: makeConfig())
            XCTFail("Expected empty output")
        } catch let error as LLMPostProcessorError {
            XCTAssertEqual(error.logValue, LLMPostProcessorError.emptyOutput.logValue)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - config validation

    func testInvalidModelIdIsRejectedBeforeAnyRequest() async {
        let processor = OpenRouterPostProcessor(session: makeSession())
        MoreTestsChatURLProtocol.handler = { _ in
            XCTFail("No request should be sent for an invalid model id")
            throw URLError(.badURL)
        }

        do {
            _ = try await processor.polish(text: "hello", config: makeConfig(modelId: "   "))
            XCTFail("Expected invalid configuration")
        } catch let error as LLMPostProcessorError {
            XCTAssertEqual(
                error.errorDescription,
                LLMPostProcessorError.invalidConfiguration("model_id").errorDescription
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMissingAPIKeyIsRejectedBeforeAnyRequest() async {
        let processor = OpenRouterPostProcessor(session: makeSession())
        MoreTestsChatURLProtocol.handler = { _ in
            XCTFail("No request should be sent without an API key")
            throw URLError(.badURL)
        }

        do {
            _ = try await processor.generate(
                instructions: "sys",
                userText: "user",
                config: makeConfig(apiKey: "   ")
            )
            XCTFail("Expected invalid configuration")
        } catch let error as LLMPostProcessorError {
            XCTAssertEqual(
                error.errorDescription,
                LLMPostProcessorError.invalidConfiguration("api_key").errorDescription
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeConfig(
        modelId: String = "google/gemini-2.5-flash",
        apiKey: String = "test-key"
    ) -> LLMConfig {
        LLMConfig(
            modelId: modelId,
            endpointURL: URL(string: "https://openrouter.ai/api/v1/chat/completions")!,
            systemPrompt: "prompt",
            keywords: [],
            timeoutSeconds: 3,
            apiKey: apiKey
        )
    }

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MoreTestsChatURLProtocol.self]
        return URLSession(configuration: config)
    }
}

private final class MoreTestsChatURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    static func jsonResponse(for request: URLRequest, content: String, finishReason: String? = nil) throws -> (HTTPURLResponse, Data) {
        var choice: [String: Any] = ["message": ["content": content]]
        if let finishReason {
            choice["finish_reason"] = finishReason
        }
        let responseJSON: [String: Any] = ["choices": [choice]]
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, data)
    }

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
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = MoreTestsChatURLProtocol.handler else {
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
