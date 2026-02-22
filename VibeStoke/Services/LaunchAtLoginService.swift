import Foundation
import ServiceManagement

protocol LaunchAtLoginServiceProtocol {
    func isEnabled() -> Bool
    func setEnabled(_ enabled: Bool) throws
}

enum LaunchAtLoginError: LocalizedError {
    case unsupportedOS
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedOS:
            return "Launch at login requires macOS 13 or newer."
        case let .operationFailed(reason):
            return "Launch at login update failed: \(reason)"
        }
    }
}

final class LaunchAtLoginService: LaunchAtLoginServiceProtocol {
    func isEnabled() -> Bool {
        guard #available(macOS 13.0, *) else {
            return false
        }
        return SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        guard #available(macOS 13.0, *) else {
            throw LaunchAtLoginError.unsupportedOS
        }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            throw LaunchAtLoginError.operationFailed(error.localizedDescription)
        }
    }
}
