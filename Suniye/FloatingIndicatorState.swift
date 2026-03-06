import Foundation

enum FloatingIndicatorState: Equatable {
    case listening
    case stopped
    case processing
    case done(words: Int)
    case error(message: String)

    var logValue: String {
        switch self {
        case .listening:
            return "listening"
        case .stopped:
            return "stopped"
        case .processing:
            return "processing"
        case .done:
            return "done"
        case .error:
            return "error"
        }
    }
}
