import Foundation

enum ComputerUseToolResultEncoder {
    static func encode(_ result: ComputerUseToolResult) throws -> String {
        switch result {
        case let .applications(applications):
            return try encode(applications)
        case let .appState(state):
            return try encode(state)
        case .actionCompleted:
            return "null"
        }
    }

    static func encode(error: String) throws -> String {
        try encode(["error": error])
    }

    private static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}
