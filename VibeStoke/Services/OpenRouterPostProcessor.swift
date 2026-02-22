import Foundation

final class OpenRouterPostProcessor: LLMPostProcessor {
    private let session: URLSession
    private let endpoint: URL

    init(session: URLSession = .shared, endpoint: URL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!) {
        self.session = session
        self.endpoint = endpoint
    }

    func polish(text: String, config: LLMConfig) async throws -> String {
        let trimmedInput = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
            throw LLMPostProcessorError.emptyOutput
        }
        guard LLMDefaults.isValidModelId(config.modelId) else {
            throw LLMPostProcessorError.invalidConfiguration("model_id")
        }
        guard !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMPostProcessorError.invalidConfiguration("api_key")
        }

        let payload = makePayload(inputText: trimmedInput, config: config)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = config.timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await withTimeout(seconds: config.timeoutSeconds) {
                try await self.session.data(for: request)
            }

            guard let http = response as? HTTPURLResponse else {
                throw LLMPostProcessorError.malformedResponse
            }

            switch http.statusCode {
            case 200 ..< 300:
                break
            case 401, 403:
                throw LLMPostProcessorError.unauthorized
            default:
                throw LLMPostProcessorError.provider("http_\(http.statusCode)")
            }

            let output = try extractText(from: data)
            let sanitized = sanitizeOutput(output)
            guard !sanitized.isEmpty else {
                throw LLMPostProcessorError.emptyOutput
            }
            return sanitized
        } catch let error as LLMPostProcessorError {
            throw error
        } catch {
            if (error as NSError).code == NSURLErrorTimedOut || error is TimeoutError {
                throw LLMPostProcessorError.timeout
            }
            throw LLMPostProcessorError.network(error.localizedDescription)
        }
    }

    private func makePayload(inputText: String, config: LLMConfig) -> [String: Any] {
        let keywordsSection: String
        if config.keywords.isEmpty {
            keywordsSection = "No keyword hints provided."
        } else {
            let joined = config.keywords.joined(separator: ", ")
            keywordsSection = "Keyword hints: \(joined)"
        }

        let system = """
\(config.systemPrompt)

Rules:
- Return plain text only.
- No markdown.
- No explanations or prefixes.
- Preserve meaning and intent.
\(keywordsSection)
"""

        let messages: [[String: String]] = [
            ["role": "system", "content": system],
            ["role": "user", "content": inputText],
        ]

        return [
            "model": config.modelId,
            "messages": messages,
            "temperature": 0.1,
            "top_p": 0.2,
            "max_tokens": max(1, config.maxTokens),
        ]
    }

    private func extractText(from data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first else {
            throw LLMPostProcessorError.malformedResponse
        }

        if let message = first["message"] as? [String: Any],
           let content = message["content"] {
            if let text = content as? String {
                return text
            }
            if let parts = content as? [[String: Any]] {
                let collected = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
                if !collected.isEmpty {
                    return collected
                }
            }
        }

        if let text = first["text"] as? String {
            return text
        }

        throw LLMPostProcessorError.malformedResponse
    }

    func sanitizeOutput(_ raw: String) -> String {
        var output = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if output.hasPrefix("```") {
            let lines = output.components(separatedBy: .newlines)
            let filtered = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }
            output = filtered.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let prefixes = ["output:", "polished:", "rewritten:", "text:"]
        for prefix in prefixes {
            if output.lowercased().hasPrefix(prefix),
               let range = output.range(of: ":") {
                output = String(output[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        return output
    }

    private struct TimeoutError: Error {}

    private func withTimeout<T>(seconds: Double, operation: @escaping () async throws -> T) async throws -> T {
        let workTask = Task { try await operation() }
        let timeoutTask = Task {
            let nanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
            try await Task.sleep(nanoseconds: nanoseconds)
            workTask.cancel()
        }

        defer {
            timeoutTask.cancel()
        }

        do {
            return try await workTask.value
        } catch is CancellationError {
            throw TimeoutError()
        } catch {
            throw error
        }
    }
}
