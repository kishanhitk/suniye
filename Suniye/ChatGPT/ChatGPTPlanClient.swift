import Foundation

/// A model that the signed-in ChatGPT account can use.
struct ChatGPTModel: Equatable, Identifiable, Sendable {
    let slug: String
    let displayName: String

    var id: String { slug }
}

/// Requests to api.openai.com that use the user's ChatGPT plan: the model
/// list, and one streamed answer of the Responses API.
actor ChatGPTPlanClient {
    static let modelsURL = URL(string: "https://api.openai.com/v1/models")!
    static let responsesURL = URL(string: "https://api.openai.com/v1/responses")!
    static let defaultModel = "gpt-6.1-sol"
    static let usageURL = URL(string: "https://chatgpt.com/settings/usage")!

    private static let planLimitCode = "subscription_sharing_usage_limit_exceeded"
    private static let planNotAllowedCode = "subscription_sharing_user_not_eligible"

    private let connection: ChatGPTConnection
    private let session: URLSession
    /// A model that reasons first sends nothing for a time.
    private let idleTimeoutSeconds: Double
    private let totalTimeoutSeconds: Double
    /// Set by a plan limit or a plan that is not allowed. OpenAI asks for no
    /// new request then, so each next answer fails at once with the same
    /// cause until the user acts.
    private var pause: ChatGPTError?

    init(connection: ChatGPTConnection, session: URLSession = .shared, idleTimeoutSeconds: Double = 120, totalTimeoutSeconds: Double = 900) {
        self.connection = connection
        self.session = session
        self.idleTimeoutSeconds = idleTimeoutSeconds
        self.totalTimeoutSeconds = totalTimeoutSeconds
    }

    /// The user asked again, or opened the ChatGPT settings.
    func endPause() {
        pause = nil
    }

    /// The models that the account shows in a list, in the server's order.
    func models() async throws -> [ChatGPTModel] {
        struct List: Decodable {
            struct Model: Decodable {
                let slug: String
                let displayName: String?
                let visibility: String?

                enum CodingKeys: String, CodingKey {
                    case slug
                    case displayName = "display_name"
                    case visibility
                }
            }

            let models: [Model]
        }

        let (bytes, status) = try await authorized { token in
            var request = URLRequest(url: Self.modelsURL, timeoutInterval: 30)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            return request
        }
        let data = try await body(of: bytes)
        guard status == 200, let list = try? JSONDecoder().decode(List.self, from: data) else {
            AppLogger.shared.log(.error, "chatgpt model list failed status=\(status)")
            throw ChatGPTError.service
        }
        return list.models
            .filter { $0.visibility == "list" }
            .map { ChatGPTModel(slug: $0.slug, displayName: $0.displayName ?? $0.slug) }
    }

    /// The whole text of one answer. `store` is off, so OpenAI keeps no
    /// copy of the answer for a later request.
    func respond(model: String, instructions: String, input: String) async throws -> String {
        if let pause {
            throw pause
        }
        // The preview refuses `max_output_tokens`, `temperature` and a
        // system role item.
        let body = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "instructions": instructions,
            "input": [["role": "user", "content": input]],
            "store": false,
            "stream": true,
        ] as [String: Any])
        do {
            return try await withTimeout(seconds: totalTimeoutSeconds) {
                try await self.answer(to: body)
            }
        } catch is TimeoutError {
            throw ChatGPTError.timeout
        } catch let error as ChatGPTError {
            if error == .planLimit || error == .planNotAllowed {
                pause = error
            }
            throw error
        }
    }

    private func answer(to body: Data) async throws -> String {
        let (bytes, status) = try await authorized { [idleTimeoutSeconds] token in
            var request = URLRequest(url: Self.responsesURL, timeoutInterval: idleTimeoutSeconds)
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            return request
        }
        guard status == 200 else {
            throw Self.failure(status: status, code: Self.errorCode(in: try await self.body(of: bytes)))
        }
        struct Event: Decodable {
            struct Response: Decodable {
                struct Failure: Decodable {
                    let code: String?
                }

                let error: Failure?
            }

            let type: String
            let delta: String?
            let code: String?
            let response: Response?
        }

        var text = ""
        do {
            for try await line in bytes.lines {
                guard line.hasPrefix("data:"),
                      let event = try? JSONDecoder().decode(Event.self, from: Data(line.dropFirst(5).utf8))
                else { continue }
                switch event.type {
                case "response.output_text.delta":
                    text += event.delta ?? ""
                case "response.completed":
                    return text
                case "response.incomplete":
                    throw ChatGPTError.incomplete
                case "response.failed":
                    throw Self.failure(status: status, code: event.response?.error?.code)
                case "error":
                    throw Self.failure(status: status, code: event.code)
                default:
                    continue
                }
            }
        } catch let error as ChatGPTError {
            throw error
        } catch {
            throw try ChatGPTError(transport: error)
        }
        // Only `response.completed` is a whole answer.
        AppLogger.shared.log(.error, "chatgpt answer ended with no last event")
        throw ChatGPTError.network
    }

    /// Sends the request with the access token. When the service refuses
    /// the token, one refresh and one more send follow.
    private func authorized(_ request: @Sendable (String) -> URLRequest) async throws -> (URLSession.AsyncBytes, Int) {
        var refreshed = false
        while true {
            let token = try await connection.accessToken(refreshing: refreshed)
            let bytes: URLSession.AsyncBytes
            let response: URLResponse
            do {
                (bytes, response) = try await session.bytes(for: request(token))
            } catch {
                throw try ChatGPTError(transport: error)
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401, !refreshed {
                refreshed = true
                continue
            }
            if status != 200 {
                let requestID = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "x-request-id") ?? "none"
                AppLogger.shared.log(.error, "chatgpt request failed status=\(status) request_id=\(requestID)")
            }
            return (bytes, status)
        }
    }

    private func body(of bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        do {
            for try await byte in bytes {
                data.append(byte)
            }
        } catch {
            throw try ChatGPTError(transport: error)
        }
        return data
    }

    /// The body can be `{"error": {"code": …}}` or `{"detail": "…"}`. Only
    /// the code is read: the other text is for people and is never logged.
    private static func errorCode(in body: Data) -> String? {
        let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        return (object?["error"] as? [String: Any])?["code"] as? String
    }

    private static func failure(status: Int, code: String?) -> ChatGPTError {
        AppLogger.shared.log(.error, "chatgpt answer failed status=\(status) code=\(code ?? "none")")
        switch code {
        case planLimitCode:
            return .planLimit
        case planNotAllowedCode:
            return .planNotAllowed
        default:
            return .service
        }
    }
}
