import Foundation
import ServiceManagement

enum LaunchAtLoginStatus: Equatable {
    case disabled
    case enabled
    case requiresApproval
    case unsupported(String)

    var isEnabledForUI: Bool {
        switch self {
        case .enabled, .requiresApproval:
            return true
        case .disabled, .unsupported:
            return false
        }
    }

    var detailText: String {
        switch self {
        case .disabled:
            return "Launch at login is off."
        case .enabled:
            return "Suniye will open automatically when you log in."
        case .requiresApproval:
            return "macOS requires approval in Login Items before launch at login can take effect."
        case let .unsupported(message):
            return message
        }
    }
}

protocol LaunchAtLoginServiceProtocol {
    func currentStatus() -> LaunchAtLoginStatus
    func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginStatus
}

final class LaunchAtLoginService: LaunchAtLoginServiceProtocol {
    func currentStatus() -> LaunchAtLoginStatus {
        map(SMAppService.mainApp.status)
    }

    func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginStatus {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        return currentStatus()
    }

    private func map(_ status: SMAppService.Status) -> LaunchAtLoginStatus {
        switch status {
        case .notRegistered:
            return .disabled
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .unsupported("Launch at login is unavailable for this build. Signed builds are required.")
        @unknown default:
            return .unsupported("Launch at login returned an unknown state.")
        }
    }
}
