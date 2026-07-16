import AppKit
import ApplicationServices
import Foundation

/// How an Accessibility onboarding presentation ended.
enum AccessibilityOnboardingEnd: Equatable {
    case granted
    /// The user backed out of the overlay (its back chevron or an external close).
    case dismissed
    /// The safety timeout fired with no grant.
    case timedOut
}

/// Seam that isolates the (vendored, reverse-engineered) Permiso drag-to-grant
/// overlay from `AppState` and the views. Everything Permiso-specific lives behind
/// this protocol so the kill switch, the unit tests, and a future rip-out each touch
/// exactly one file.
@MainActor
protocol AccessibilityOnboardingPresenting: AnyObject {
    var isPresenting: Bool { get }
    /// Presents the Accessibility helper. Calls `onGranted` once the permission flips
    /// to trusted (or immediately if it is already granted). `onEnded` fires exactly
    /// once per presentation with how it ended. Re-presenting while already presenting
    /// restarts the flow (the previous presentation ends as `.dismissed`).
    func present(onGranted: @escaping () -> Void, onEnded: @escaping (AccessibilityOnboardingEnd) -> Void)
    func dismiss()
}

/// Live implementation backed by `PermisoAssistant`.
///
/// Permiso is presentation-only — it floats the draggable app row but never detects the
/// grant. This wrapper owns that missing piece: a lightweight poller on `AXIsProcessTrusted()`
/// that auto-dismisses the overlay, refocuses the app, and fires `onGranted` the moment the
/// user drags Suniye into the Accessibility list. A safety timeout guards against a leaked timer
/// if the user wanders off.
///
/// The overlay's own back chevron dismisses `PermisoAssistant` directly; the assistant's
/// `onDismiss` hook keeps this wrapper's `isPresenting` in sync so the Enable button is
/// immediately re-pressable (previously it silently no-opped until the 300s timeout).
@MainActor
final class PermisoAccessibilityOnboarding: AccessibilityOnboardingPresenting {
    private let isTrusted: () -> Bool
    private let pollInterval: TimeInterval
    private let safetyTimeout: TimeInterval
    private let nowProvider: () -> Date

    private var pollTimer: Timer?
    private var deadline: Date?
    private var onEnded: ((AccessibilityOnboardingEnd) -> Void)?

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

    func present(onGranted: @escaping () -> Void, onEnded: @escaping (AccessibilityOnboardingEnd) -> Void) {
        // Self-heal a stale latch: a lingering presentation (user backed out via a
        // path we didn't observe) must never make Enable a dead button.
        if isPresenting {
            end(.dismissed)
        }
        // Already granted: nothing to show, report success immediately.
        if isTrusted() {
            onGranted()
            onEnded(.granted)
            return
        }

        isPresenting = true
        self.onEnded = onEnded
        AppLogger.shared.log(.info, "accessibility onboarding: presenting Permiso overlay")
        PermisoAssistant.shared.onDismiss = { [weak self] in
            self?.handleExternalDismiss()
        }
        PermisoAssistant.shared.present(panel: .accessibility)
        startPolling(onGranted: onGranted)
    }

    func dismiss() {
        end(.dismissed)
    }

    /// The overlay was dismissed by Permiso itself (back chevron). Sync our state
    /// without re-entering `PermisoAssistant.dismiss()`.
    private func handleExternalDismiss() {
        guard isPresenting else {
            return
        }
        AppLogger.shared.log(.info, "accessibility onboarding: overlay dismissed by user")
        stopPolling()
        isPresenting = false
        fireEnded(.dismissed)
    }

    private func end(_ outcome: AccessibilityOnboardingEnd) {
        guard isPresenting else {
            return
        }
        stopPolling()
        PermisoAssistant.shared.onDismiss = nil
        PermisoAssistant.shared.dismiss()
        isPresenting = false
        fireEnded(outcome)
    }

    private func fireEnded(_ outcome: AccessibilityOnboardingEnd) {
        let callback = onEnded
        onEnded = nil
        callback?(outcome)
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
            end(.granted)
            NSApp.activate(ignoringOtherApps: true)
            onGranted()
            return
        }
        if let deadline, nowProvider() >= deadline {
            AppLogger.shared.log(.info, "accessibility onboarding: safety timeout, dismissing overlay")
            end(.timedOut)
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        deadline = nil
    }
}
