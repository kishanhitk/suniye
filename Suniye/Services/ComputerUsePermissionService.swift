import ApplicationServices
import AppKit
import CoreGraphics
import Foundation

enum ComputerUsePermissionState: Equatable, Sendable {
    case granted
    case notGranted
}

enum ComputerUsePermissionKind: Equatable, Sendable {
    case accessibility
    case screenRecording
}

struct ComputerUsePermissionSnapshot: Equatable, Sendable {
    let accessibility: ComputerUsePermissionState
    let screenRecording: ComputerUsePermissionState

    static let granted = ComputerUsePermissionSnapshot(
        accessibility: .granted,
        screenRecording: .granted
    )
    static let notGranted = ComputerUsePermissionSnapshot(
        accessibility: .notGranted,
        screenRecording: .notGranted
    )

    var canControlComputer: Bool {
        accessibility == .granted && screenRecording == .granted
    }
}

protocol ComputerUsePermissionServing: Sendable {
    func snapshot() async -> ComputerUsePermissionSnapshot
    func request(_ permission: ComputerUsePermissionKind) async -> ComputerUsePermissionSnapshot
}

@MainActor
protocol ComputerUsePermissionSettingsOpening {
    func openSettings(for permission: ComputerUsePermissionKind)
}

struct SystemComputerUsePermissionSettingsOpener: ComputerUsePermissionSettingsOpening {
    func openSettings(for permission: ComputerUsePermissionKind) {
        let locations: [String]
        switch permission {
        case .accessibility:
            locations = [
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            ]
        case .screenRecording:
            locations = [
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture",
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
            ]
        }
        for location in locations {
            guard let url = URL(string: location) else {
                continue
            }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}

actor SystemComputerUsePermissionService: ComputerUsePermissionServing {
    private let accessibilityStatus: @Sendable () -> Bool
    private let accessibilityRequest: @Sendable () -> Bool
    private let screenRecordingStatus: @Sendable () -> Bool
    private let screenRecordingRequest: @Sendable () -> Bool

    init(
        accessibilityStatus: @escaping @Sendable () -> Bool = { AXIsProcessTrusted() },
        accessibilityRequest: @escaping @Sendable () -> Bool = {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        },
        screenRecordingStatus: @escaping @Sendable () -> Bool = {
            CGPreflightScreenCaptureAccess()
        },
        screenRecordingRequest: @escaping @Sendable () -> Bool = {
            CGRequestScreenCaptureAccess()
        }
    ) {
        self.accessibilityStatus = accessibilityStatus
        self.accessibilityRequest = accessibilityRequest
        self.screenRecordingStatus = screenRecordingStatus
        self.screenRecordingRequest = screenRecordingRequest
    }

    func snapshot() -> ComputerUsePermissionSnapshot {
        currentSnapshot()
    }

    func request(_ permission: ComputerUsePermissionKind) -> ComputerUsePermissionSnapshot {
        switch permission {
        case .accessibility:
            _ = accessibilityRequest()
        case .screenRecording:
            _ = screenRecordingRequest()
        }
        return currentSnapshot()
    }

    private func currentSnapshot() -> ComputerUsePermissionSnapshot {
        ComputerUsePermissionSnapshot(
            accessibility: accessibilityStatus() ? .granted : .notGranted,
            screenRecording: screenRecordingStatus() ? .granted : .notGranted
        )
    }
}
