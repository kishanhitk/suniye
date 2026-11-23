import Foundation

struct ASRModelBannerState: Equatable {
    enum Tone: Equatable {
        case info
        case error

        var icon: String {
            switch self {
            case .info:
                return "arrow.triangle.2.circlepath.circle.fill"
            case .error:
                return "exclamationmark.triangle.fill"
            }
        }
    }

    let title: String
    let detail: String
    let tone: Tone
    let progress: Double?
}
