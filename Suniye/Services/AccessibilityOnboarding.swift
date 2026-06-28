import AppKit
import ApplicationServices
import Foundation

/// Seam that isolates the (vendored, reverse-engineered) Permiso drag-to-grant
/// overlay from `AppState` and the views. Everything Permiso-specific lives behind
/// this protocol so the kill switch, the unit tests, and a future rip-out each touch
/// exactly one file.
@MainActor
protocol AccessibilityOnboardingPresenting: AnyObject {
    var isPresenting: Bool { get }
    /// Presents the Accessibility helper. Calls `onGranted` once the permission flips
    /// to trusted (or immediately if it is already granted). No-op while already presenting.
    func present(onGranted: @escaping () -> Void)
    func dismiss()
}

/// Live implementation backed by `PermisoAssistant`.
///
/// Permiso is presentation-only — it floats the draggable app row but never detects the
/// grant. This wrapper owns that missing piece: a lightweight poller on `AXIsProcessTrusted()`
/// that auto-dismisses the overlay, refocuses the app, and fires `onGranted` the moment the
/// user drags Suniye into the Accessibility list. A safety timeout guards against a leaked timer
/// if the user wanders off.
@MainActor
final class PermisoAccessibilityOnboarding: AccessibilityOnboardingPresenting {
    private let isTrusted: () -> Bool
    private let pollInterval: TimeInterval
    private let safetyTimeout: TimeInterval
    private let nowProvider: () -> Date

    private var pollTimer: Timer?
    private var deadline: Date?

    private(set) var isPresenting = false

    init(
        isTrusted: @escaping () -> Bool = { AXIsProcessTrusted() },
        pollInterval: TimeInterval = 0.5,
        safetyTimeout: TimeInterval = 300,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.isTrusted = isTrusted
        self.pollInterval = pollInterval
        self.safetyTimeout = safetyTimeout
        self.nowProvider = nowProvider
    }

    func present(onGranted: @escaping () -> Void) {
        guard !isPresenting else {
            return
        }
        // Already granted: nothing to show, report success immediately.
        if isTrusted() {
            onGranted()
            return
        }

        isPresenting = true
        AppLogger.shared.log(.info, "accessibility onboarding: presenting Permiso overlay")
        PermisoAssistant.shared.present(panel: .accessibility)
        startPolling(onGranted: onGranted)
    }

    func dismiss() {
        guard isPresenting else {
            return
        }
        stopPolling()
        PermisoAssistant.shared.dismiss()
        isPresenting = false
    }

    private func startPolling(onGranted: @escaping () -> Void) {
        stopPolling()
        deadline = nowProvider().addingTimeInterval(safetyTimeout)
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick(onGranted: onGranted)
            }
        }
    }

    private func tick(onGranted: @escaping () -> Void) {
        if isTrusted() {
            AppLogger.shared.log(.info, "accessibility onboarding: granted, dismissing overlay")
            dismiss()
            NSApp.activate(ignoringOtherApps: true)
            onGranted()
            return
        }
        if let deadline, nowProvider() >= deadline {
            AppLogger.shared.log(.info, "accessibility onboarding: safety timeout, dismissing overlay")
            dismiss()
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        deadline = nil
    }
}
