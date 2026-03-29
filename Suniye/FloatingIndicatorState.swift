import Foundation

enum FloatingIndicatorState: Equatable {
    enum Source: String, Equatable {
        case hotkey
        case manual
    }

    case idle
    case hover
    case listening(levels: [Float], source: Source)
    case processing
    case error(message: String)

    var logValue: String {
        switch self {
        case .idle:
            return "idle"
        case .hover:
            return "hover"
        case .listening:
            return "listening"
        case .processing:
            return "processing"
        case .error:
            return "error"
        }
    }

    var tracksPointerScreen: Bool {
        switch self {
        case .idle, .hover:
            return true
        case .listening, .processing, .error:
            return false
        }
    }
}
