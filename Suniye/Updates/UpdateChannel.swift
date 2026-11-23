import Foundation

enum UpdateChannel: String, Codable, CaseIterable, Identifiable {
    case stable
    case tip

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stable:
            return "Stable"
        case .tip:
            return "Tip"
        }
    }

    var detail: String {
        switch self {
        case .stable:
            return "Stable releases only."
        case .tip:
            return "Latest main-branch builds."
        }
    }

    var appcastURLString: String {
        switch self {
        case .stable:
            return "https://suniye.kishans.in/appcast.xml"
        case .tip:
            return "https://suniye.kishans.in/appcast-tip.xml"
        }
    }

    var sparkleAllowedChannels: Set<String> {
        switch self {
        case .stable:
            return []
        case .tip:
            return [rawValue]
        }
    }
}
