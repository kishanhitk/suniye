import Foundation
import XCTest
@testable import Suniye

final class ComputerUsePhase5ModelTests: XCTestCase {
    override func tearDown() {
        ComputerUseModelURLProtocol.handler = nil
        super.tearDown()
    }

    func testConfigurationValidationRequiresSafeHTTPConfiguration() {
        let endpoint = URL(string: "https://example.com/v1/chat/completions")!
        let valid = ComputerUseRemoteModelConfiguration(
            endpointURL: endpoint,
            modelID: "model",
            apiKey: "key"
        )
        XCTAssertNil(valid.validationMessage)

        let missingKey = ComputerUseRemoteModelConfiguration(
            endpointURL: endpoint,
            modelID: "model",
            apiKey: " "
        )
        XCTAssertEqual(
            missingKey.validationMessage,
            "A Computer Use model API key is required."
        )

        let invalidScheme = ComputerUseRemoteModelConfiguration(
            endpointURL: URL(string: "file:///tmp/model")!,
            modelID: "model",
            apiKey: "key"
        )
        XCTAssertEqual(
            invalidScheme.validationMessage,
            "The Computer Use model endpoint must use HTTP or HTTPS."
        )

        let missingModel = ComputerUseRemoteModelConfiguration(
            endpointURL: endpoint,
            modelID: " ",
            apiKey: "key"
        )
        XCTAssertEqual(missingModel.validationMessage, "A Computer Use model ID is required.")
        let invalidTimeout = ComputerUseRemoteModelConfiguration(
            endpointURL: endpoint,
            modelID: "model",
            apiKey: "key",
            timeoutSeconds: 121
        )
        XCTAssertEqual(
            invalidTimeout.validationMessage,
            "The Computer Use model timeout must be between 1 and 120 seconds."
        )
        let invalidTokenLimit = ComputerUseRemoteModelConfiguration(
            endpointURL: endpoint,
            modelID: "model",
            apiKey: "key",
            maxTokens: 4_097
        )
        XCTAssertEqual(
            invalidTokenLimit.validationMessage,
            "The Computer Use model token limit must be between 32 and 4,096."
        )
    }

    func testPromptRendererRedactsTypedActionContentAndControlsScreenshotUpload() {
        let observation = makePhase3Observation(generation: 8)
        let screenshot = ComputerUseScreenshot(
            data: Data([0x01, 0x02, 0x03]),
            mimeType: "image/png",
            width: 2,
            height: 2
        )
        let observationWithScreenshot = ComputerUseObservation(
            generation: observation.generation,
            capturedAt: observation.capturedAt,
            target: observation.target,
            accessibility: observation.accessibility,
            screenshot: screenshot
        )
        let request = ComputerUseModelRequest(
            instruction: "Enter the secret only when the task requires it.",
            observation: observationWithScreenshot,
            availableApplications: [observation.target.application],
            recentActionResults: [
                ComputerUseActionResult(
                    action: .typeText("secret-value"),
                    target: observation.target,
                    completedAt: Date(timeIntervalSince1970: 2_000)
                ),
            ],
            iteration: 2
        )

        let textOnly = ComputerUseModelPromptRenderer.render(
            request: request,
            includeScreenshot: false
        )
        XCTAssertNil(textOnly.screenshot)
        XCTAssertTrue(textOnly.text.contains("Type 12 characters"))
        XCTAssertFalse(textOnly.text.contains("secret-value"))
        XCTAssertTrue(textOnly.text.contains("Available applications:"))
        XCTAssertTrue(textOnly.text.contains("Target App (com.example.target)"))

        let multimodal = ComputerUseModelPromptRenderer.render(
            request: request,
            includeScreenshot: true
        )
        XCTAssertEqual(multimodal.screenshot, screenshot)
    }

    func testPromptRendererIncludesAvailableAccessibilityFields() {
        let base = makePhase3Observation(generation: 9)
        let richElement = ComputerUseAXElement(
            index: 2,
            role: "AXTextField",
            subrole: "AXSearchField",
            title: "Search",
            description: "Search field",
            value: "query",
            isEnabled: true,
            isFocused: true,
            isSelected: true,
            bounds: ComputerUseRect(x: 10, y: 20, width: 200, height: 30),
            actions: ["AXPress", "AXShowMenu"],
            childIndexes: []
        )
        let observation = ComputerUseObservation(
            generation: base.generation,
            capturedAt: base.capturedAt,
            target: base.target,
            accessibility: ComputerUseAXSnapshot(
                text: "",
                elements: [richElement],
                wasTruncated: false
            ),
            screenshot: nil
        )

        let prompt = ComputerUseModelPromptRenderer.render(
            request: ComputerUseModelRequest(
                instruction: "Inspect the field.",
                observation: observation,
                recentActionResults: [],
                iteration: 1
            ),
            includeScreenshot: false
        ).text

        XCTAssertTrue(prompt.contains("role=AXTextField"))
        XCTAssertTrue(prompt.contains("subrole=AXSearchField"))
        XCTAssertTrue(prompt.contains("title=\"Search\""))
        XCTAssertTrue(prompt.contains("description=\"Search field\""))
        XCTAssertTrue(prompt.contains("value=\"query\""))
        XCTAssertTrue(prompt.contains("enabled=true"))
        XCTAssertTrue(prompt.contains("focused=true"))
        XCTAssertTrue(prompt.contains("selected=true"))
        XCTAssertTrue(prompt.contains("bounds=10.0,20.0,200.0,30.0"))
        XCTAssertTrue(prompt.contains("actions=AXPress,AXShowMenu"))
    }

    func testDecisionParserAcceptsDirectAndFencedJSON() throws {
        let action = ComputerUseAction.click(point: ComputerUsePoint(x: 10, y: 20))
        let encodedAction = try JSONEncoder().encode(
            ComputerUseModelDecision.action(action)
        )
        let rawAction = String(decoding: encodedAction, as: UTF8.self)

        XCTAssertEqual(
            try ComputerUseModelDecisionParser.parse(rawAction),
            .action(action)
        )
        let fence = String(repeating: Character(UnicodeScalar(96)!), count: 3)
        XCTAssertEqual(
            try ComputerUseModelDecisionParser.parse(
                fence + "json\n" + rawAction + "\n" + fence
            ),
            .action(action)
        )

        XCTAssertEqual(
            try ComputerUseModelDecisionParser.parse(
                #"{"kind":"target","app":"com.google.Chrome"}"#
            ),
            .target(application: "com.google.Chrome")
        )
    }

    func testDecisionParserRejectsMalformedAndEmptyDecisions() {
        assertInvalidResponse("")
        assertInvalidResponse("not json")
        assertInvalidResponse("{\"kind\":\"completed\",\"message\":\"\"}")
        assertInvalidResponse("{\"kind\":\"target\",\"app\":\" \"}")
    }

    func testModelClientSendsTextAndOptionalScreenshotAndParsesDecision() async throws {
        let endpoint = URL(string: "https://example.com/v1/chat/completions")!
        let observation = makePhase3Observation(generation: 12)
        let screenshot = ComputerUseScreenshot(
            data: Data([0x01, 0x02, 0x03]),
            mimeType: "image/png",
            width: 2,
            height: 2
        )
        let request = ComputerUseModelRequest(
            instruction: "Click the button.",
            observation: ComputerUseObservation(
                generation: observation.generation,
                capturedAt: observation.capturedAt,
                target: observation.target,
                accessibility: observation.accessibility,
                screenshot: screenshot
            ),
            recentActionResults: [],
            iteration: 1
        )
        ComputerUseModelURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            let body = try XCTUnwrap(
                try JSONSerialization.jsonObject(
                    with: try XCTUnwrap(ComputerUseModelURLProtocol.bodyData(from: request))
                ) as? [String: Any]
            )
            XCTAssertEqual(body["model"] as? String, "vision-model")
            let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
            XCTAssertEqual(messages[0]["role"] as? String, "system")
            let content = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])
            XCTAssertEqual(content[0]["type"] as? String, "text")
            XCTAssertEqual(content[1]["type"] as? String, "image_url")
            let imageURL = try XCTUnwrap(content[1]["image_url"] as? [String: String])
            XCTAssertEqual(imageURL["url"], "data:image/png;base64,AQID")

            let response = ComputerUseModelDecision.completed(message: "Done.")
            return try Self.response(for: request, decision: response)
        }

        let client = OpenAICompatibleComputerUseModelClient(
            configuration: ComputerUseRemoteModelConfiguration(
                endpointURL: endpoint,
                modelID: "vision-model",
                apiKey: "test-key",
                allowsScreenshotUpload: true
            ),
            completionClient: makeCompletionClient()
        )

        let decision = try await client.decide(
            request: request,
            cancellation: ComputerUseCancellationToken()
        )
        XCTAssertEqual(decision, .completed(message: "Done."))
    }

    func testModelClientDoesNotSendScreenshotWithoutExplicitUploadPermission() async throws {
        let endpoint = URL(string: "https://example.com/v1/chat/completions")!
        let observation = makePhase3Observation(generation: 13)
        let request = ComputerUseModelRequest(
            instruction: "Read the button.",
            observation: ComputerUseObservation(
                generation: observation.generation,
                capturedAt: observation.capturedAt,
                target: observation.target,
                accessibility: observation.accessibility,
                screenshot: ComputerUseScreenshot(
                    data: Data([0x01]),
                    mimeType: "image/png",
                    width: 1,
                    height: 1
                )
            ),
            recentActionResults: [],
            iteration: 1
        )
        ComputerUseModelURLProtocol.handler = { request in
            let body = try XCTUnwrap(
                try JSONSerialization.jsonObject(
                    with: try XCTUnwrap(ComputerUseModelURLProtocol.bodyData(from: request))
                ) as? [String: Any]
            )
            let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
            XCTAssertTrue(messages[1]["content"] is String)
            return try Self.response(
                for: request,
                decision: .blocked(reason: "No action is needed.")
            )
        }

        let client = OpenAICompatibleComputerUseModelClient(
            configuration: ComputerUseRemoteModelConfiguration(
                endpointURL: endpoint,
                modelID: "text-model",
                apiKey: "test-key"
            ),
            completionClient: makeCompletionClient()
        )

        let decision = try await client.decide(
            request: request,
            cancellation: ComputerUseCancellationToken()
        )
        XCTAssertEqual(decision, .blocked(reason: "No action is needed."))
    }

    func testModelClientMapsMalformedProviderOutputToInvalidResponse() async throws {
        let endpoint = URL(string: "https://example.com/v1/chat/completions")!
        ComputerUseModelURLProtocol.handler = { request in
            let responseJSON: [String: Any] = [
                "choices": [
                    ["message": ["content": "not json"]],
                ],
            ]
            let data = try JSONSerialization.data(withJSONObject: responseJSON)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, data)
        }

        let client = OpenAICompatibleComputerUseModelClient(
            configuration: ComputerUseRemoteModelConfiguration(
                endpointURL: endpoint,
                modelID: "text-model",
                apiKey: "test-key"
            ),
            completionClient: makeCompletionClient()
        )

        do {
            _ = try await client.decide(
                request: ComputerUseModelRequest(
                    instruction: "Read the button.",
                    observation: makePhase3Observation(generation: 14),
                    recentActionResults: [],
                    iteration: 1
                ),
                cancellation: ComputerUseCancellationToken()
            )
            XCTFail("Expected invalid response")
        } catch let error as ComputerUseModelError {
            guard case .invalidResponse = error else {
                return XCTFail("Unexpected model error: \(error)")
            }
        }
    }

    private func assertInvalidResponse(
        _ raw: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            _ = try ComputerUseModelDecisionParser.parse(raw)
            XCTFail("Expected invalid response", file: file, line: line)
        } catch let error as ComputerUseModelError {
            guard case .invalidResponse = error else {
                XCTFail("Unexpected model error: \(error)", file: file, line: line)
                return
            }
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    private func makeCompletionClient() -> ChatCompletionClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ComputerUseModelURLProtocol.self]
        return ChatCompletionClient(session: URLSession(configuration: configuration))
    }

    private static func response(
        for request: URLRequest,
        decision: ComputerUseModelDecision
    ) throws -> (HTTPURLResponse, Data) {
        let encodedDecision = try JSONEncoder().encode(decision)
        let responseJSON: [String: Any] = [
            "choices": [
                [
                    "message": [
                        "content": String(decoding: encodedDecision, as: UTF8.self),
                    ],
                ],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, data)
    }
}

private final class ComputerUseModelURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

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

    static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }
}
