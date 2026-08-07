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

    func testModelClientRejectsInvalidConfigurationAndPreflightCancellation() async {
        let request = ComputerUseModelRequest(
            instruction: "Inspect the app.",
            observation: makePhase3Observation(generation: 7),
            recentActionResults: [],
            iteration: 1
        )
        let invalidClient = OpenAICompatibleComputerUseModelClient(
            configuration: ComputerUseRemoteModelConfiguration(
                endpointURL: URL(string: "file:///tmp/model")!,
                modelID: "model",
                apiKey: "key"
            )
        )

        do {
            _ = try await invalidClient.decide(
                request: request,
                cancellation: ComputerUseCancellationToken()
            )
            XCTFail("Expected invalid configuration to fail")
        } catch let error as ComputerUseModelError {
            XCTAssertEqual(
                error,
                .requestFailed("The Computer Use model endpoint must use HTTP or HTTPS.")
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let cancellation = ComputerUseCancellationToken()
        cancellation.cancel()
        let validClient = OpenAICompatibleComputerUseModelClient(
            configuration: ComputerUseRemoteModelConfiguration(
                endpointURL: URL(string: "https://example.com/v1/chat/completions")!,
                modelID: "model",
                apiKey: "key"
            )
        )
        do {
            _ = try await validClient.decide(request: request, cancellation: cancellation)
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPromptRendererRedactsTypedActionContentAndIncludesTheObservationScreenshot() {
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
            observationFreshness: .stale,
            conversation: [
                ComputerUseConversationMessage(role: .user, text: "Open the form."),
                ComputerUseConversationMessage(role: .assistant, text: "The form is open."),
            ],
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

        let rendered = ComputerUseModelPromptRenderer.render(request: request)
        XCTAssertEqual(rendered.screenshot, screenshot)
        XCTAssertTrue(rendered.text.contains("Type 12 characters"))
        XCTAssertFalse(rendered.text.contains("secret-value"))
        XCTAssertTrue(rendered.text.contains("Available applications:"))
        XCTAssertTrue(rendered.text.contains("Target App (com.example.target)"))
        XCTAssertTrue(rendered.text.contains("Observation freshness: stale"))
        XCTAssertTrue(rendered.text.contains("Actions allowed from this observation: no"))
        XCTAssertTrue(rendered.text.contains("User: Open the form."))
        XCTAssertTrue(rendered.text.contains("Assistant: The form is open."))
    }

    func testPromptRendererIncludesNativeAccessibilityText() {
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
                text: "Search field: query (AXTextField, focused, selected, enabled)",
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
            )
        ).text

        XCTAssertTrue(prompt.contains("Search field: query (AXTextField, focused, selected, enabled)"))
        XCTAssertFalse(prompt.contains("role=AXTextField"))
        XCTAssertFalse(prompt.contains("bounds=10.0,20.0,200.0,30.0"))
    }

    func testSystemPromptEnforcesVerifiedDesktopWorkflowRules() {
        let prompt = ComputerUseRemoteModelDefaults.systemPrompt

        XCTAssertTrue(prompt.contains("An action is valid only when Observation freshness is fresh."))
        XCTAssertTrue(prompt.contains("Prefer Accessibility element actions over coordinates."))
        XCTAssertTrue(prompt.contains("Element indexes and exposed action names belong only to the current observation."))
        XCTAssertTrue(prompt.contains("The host captures fresh state after every action"))
        XCTAssertTrue(prompt.contains("cannot invoke global shortcuts"))
        XCTAssertTrue(prompt.contains("Never invent a target, element index, or action name."))
    }

    func testDecisionParserAcceptsCanonicalAndFencedJSON() throws {
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
        XCTAssertEqual(
            try ComputerUseModelDecisionParser.parse(
                #"{"kind":"action","action":{"kind":"press_key","key":"Control_L+a"}}"#
            ),
            .action(
                .keyPress(
                    key: .character("a"),
                    modifiers: ComputerUseKeyModifiers(control: true)
                )
            )
        )
        XCTAssertEqual(
            try ComputerUseModelDecisionParser.parse(
                #"{"kind":"action","action":{"kind":"press_key","key":"Control_L+greater"}}"#
            ),
            .action(
                .keyPress(
                    key: .character("."),
                    modifiers: ComputerUseKeyModifiers(control: true, shift: true)
                )
            )
        )
    }

    func testDecisionParserRejectsMalformedAndEmptyDecisions() {
        assertInvalidResponse("")
        assertInvalidResponse("not json")
        assertInvalidResponse("{\"kind\":\"completed\",\"message\":\"\"}")
        assertInvalidResponse("{\"kind\":\"target\",\"app\":\" \"}")
    }

    func testModelClientSendsTextAndScreenshotAndParsesDecision() async throws {
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
            XCTAssertEqual(
                body["max_tokens"] as? Int,
                ComputerUseRemoteModelDefaults.maxTokens
            )
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
                apiKey: "test-key"
            ),
            completionClient: makeCompletionClient()
        )

        let decision = try await client.decide(
            request: request,
            cancellation: ComputerUseCancellationToken()
        )
        XCTAssertEqual(decision, .completed(message: "Done."))
    }

    func testModelClientSendsAvailableScreenshot() async throws {
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
            let content = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])
            XCTAssertEqual(content[0]["type"] as? String, "text")
            XCTAssertEqual(content[1]["type"] as? String, "image_url")
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

    func testModelClientHonorsCancellationAfterProviderResponse() async {
        let endpoint = URL(string: "https://example.com/v1/chat/completions")!
        let cancellation = ComputerUseCancellationToken()
        ComputerUseModelURLProtocol.handler = { request in
            cancellation.cancel()
            return try Self.response(for: request, decision: .completed(message: "Done."))
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
                    instruction: "Inspect the app.",
                    observation: makePhase3Observation(generation: 15),
                    recentActionResults: [],
                    iteration: 1
                ),
                cancellation: cancellation
            )
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
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
