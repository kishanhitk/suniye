import ApplicationServices
import CoreGraphics
import Foundation

final class SystemComputerUsePermissionService: ComputerUsePermissionManaging {
    private let accessibilityTrustProvider: () -> Bool
    private let accessibilityPromptRequester: () -> Bool
    private let screenRecordingAccessProvider: () -> Bool
    private let screenRecordingRequester: () -> Bool

    init(
        accessibilityTrustProvider: @escaping () -> Bool = { AXIsProcessTrusted() },
        accessibilityPromptRequester: @escaping () -> Bool = {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        },
        screenRecordingAccessProvider: @escaping () -> Bool = {
            CGPreflightScreenCaptureAccess()
        },
        screenRecordingRequester: @escaping () -> Bool = {
            CGRequestScreenCaptureAccess()
        }
    ) {
        self.accessibilityTrustProvider = accessibilityTrustProvider
        self.accessibilityPromptRequester = accessibilityPromptRequester
        self.screenRecordingAccessProvider = screenRecordingAccessProvider
        self.screenRecordingRequester = screenRecordingRequester
    }

    func snapshot() -> ComputerUsePermissionSnapshot {
        ComputerUsePermissionSnapshot(
            accessibility: accessibilityTrustProvider() ? .granted : .notGranted,
            screenRecording: screenRecordingAccessProvider() ? .granted : .notGranted
        )
    }

    @discardableResult
    func requestAccessibility() -> Bool {
        accessibilityPromptRequester()
    }

    @discardableResult
    func requestScreenRecording() -> Bool {
        screenRecordingRequester()
    }
}
