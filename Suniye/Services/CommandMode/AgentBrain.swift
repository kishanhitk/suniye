import Foundation

/// The decision-maker. Given the task, the latest screen observation, and prior
/// step summaries, returns exactly one tool call chosen from `toolNames`.
@MainActor
protocol AgentBrain {
    func nextToolCall(task: String, observation: String, history: [String], toolNames: [String]) async throws -> ToolCall
}

/// Extracts a `ToolCall` from arbitrary model text. Tolerates prose and ```json
/// fences by scanning for the first balanced `{...}` object, so the loop doesn't
/// break when a small model wraps its answer in chatter.
enum ToolCallParser {
    static func parse(_ raw: String) throws -> ToolCall {
        guard let json = firstJSONObject(in: raw) else {
            throw CommandModeError.malformedToolCall("no JSON object found")
        }
        guard
            let data = json.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let name = obj["tool"] as? String
        else {
            throw CommandModeError.malformedToolCall("missing 'tool'")
        }
        var args: [String: String] = [:]
        if let rawArgs = obj["arguments"] as? [String: Any] {
            for (key, value) in rawArgs { args[key] = String(describing: value) }
        }
        return ToolCall(name: name, arguments: args)
    }

    /// First balanced brace-matched run, so nested objects are captured whole.
    private static func firstJSONObject(in text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var idx = start
        while idx < text.endIndex {
            let character = text[idx]
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 { return String(text[start...idx]) }
            }
            idx = text.index(after: idx)
        }
        return nil
    }
}
