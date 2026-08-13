import Foundation

/// The one place that knows how JSON leaving Computer Use is shaped.
enum ComputerUseCompactJSON {
    static func encode<T: Encodable>(
        _ value: T,
        dateEncodingStrategy: JSONEncoder.DateEncodingStrategy = .deferredToDate
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = dateEncodingStrategy
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}

/// Persists tool results as JSON and decodes them back. Encode and decode are
/// kept symmetric here so replayed conversation history can rebuild the typed
/// `ComputerUseToolResult` and share the live model-visible projection.
enum ComputerUseToolResultEncoder {
    static func encode(_ result: ComputerUseToolResult) throws -> String {
        switch result {
        case let .applications(applications):
            return try ComputerUseCompactJSON.encode(applications, dateEncodingStrategy: .iso8601)
        case let .appState(state):
            return try ComputerUseCompactJSON.encode(state, dateEncodingStrategy: .iso8601)
        case .actionCompleted:
            return "null"
        }
    }

    static func encode(error: String) throws -> String {
        try ComputerUseCompactJSON.encode(["error": error], dateEncodingStrategy: .iso8601)
    }

    /// Returns nil for error payloads and unrecognized shapes; callers fall
    /// back to the raw persisted string.
    static func decode(toolName: String, output: String) -> ComputerUseToolResult? {
        if output == "null" {
            return .actionCompleted
        }
        guard let data = output.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        switch toolName {
        case ComputerUseToolName.getAppState.rawValue:
            return (try? decoder.decode(ComputerUseAppState.self, from: data)).map { .appState($0) }
        case ComputerUseToolName.listApps.rawValue:
            return (try? decoder.decode([ComputerUseApplication].self, from: data)).map { .applications($0) }
        default:
            return nil
        }
    }
}
