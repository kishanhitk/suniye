import Foundation

/// An OpenAI-compatible chat endpoint behind `StubURLProtocol` that keeps every request it gets.
final class ChatEndpoint: @unchecked Sendable {
    struct Request {
        let url: URL?
        let authorization: String?
        let body: [String: Any]

        var messages: [[String: String]] {
            body["messages"] as? [[String: String]] ?? []
        }

        func content(of role: String) -> String? {
            messages.first { $0["role"] == role }?["content"]
        }
    }

    private let lock = NSLock()
    private var received: [Request] = []

    var requests: [Request] {
        lock.withLock { received }
    }

    init(reply: String, finishReason: String = "stop", statusCode: Int = 200) {
        StubURLProtocol.handler = { [self] request in
            let data = StubURLProtocol.requestBody(of: request) ?? Data()
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            lock.withLock {
                received.append(Request(url: request.url, authorization: request.value(forHTTPHeaderField: "Authorization"), body: body))
            }
            let answer: [String: Any] = statusCode == 200
                ? ["choices": [["message": ["role": "assistant", "content": reply], "finish_reason": finishReason]]]
                : ["error": ["message": reply]]
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, try JSONSerialization.data(withJSONObject: answer))
        }
    }
}
