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
/// The overlay's own back chevron dismisses `PermisoAssistant` directly. The wrapper
/// observes that window close so it can stop polling and report `.dismissed` at once.
@MainActor
final class PermisoAccessibilityOnboarding: AccessibilityOnboardingPresenting {
    private let isTrusted: () -> Bool
    private let pollInterval: TimeInterval
    private let safetyTimeout: TimeInterval
    private let nowProvider: () -> Date
    private let presentOverlay: @MainActor () -> Void
    private let dismissOverlay: @MainActor () -> Void
    private let windowNotificationCenter: NotificationCenter
    private let overlayWindowMatcher: @MainActor (NSWindow) -> Bool

    private var pollTimer: Timer?
    private var deadline: Date?
    private var onEnded: ((AccessibilityOnboardingEnd) -> Void)?
    private var overlayCloseObserver: NSObjectProtocol?

    private(set) var isPresenting = false

    init(
        isTrusted: @escaping () -> Bool = { AXIsProcessTrusted() },
        pollInterval: TimeInterval = 0.5,
        safetyTimeout: TimeInterval = 300,
        nowProvider: @escaping () -> Date = Date.init,
        presentOverlay: @escaping @MainActor () -> Void = { PermisoAssistant.shared.present(panel: .accessibility) },
        dismissOverlay: @escaping @MainActor () -> Void = { PermisoAssistant.shared.dismiss() },
        windowNotificationCenter: NotificationCenter = .default,
        overlayWindowMatcher: @escaping @MainActor (NSWindow) -> Bool = { window in
            window is NSPanel
                && window.styleMask.contains(.borderless)
                && window.level == .statusBar
                && window.frame.size == NSSize(width: 530, height: 109)
        }
    ) {
        self.isTrusted = isTrusted
        self.pollInterval = pollInterval
        self.safetyTimeout = safetyTimeout
        self.nowProvider = nowProvider
        self.presentOverlay = presentOverlay
        self.dismissOverlay = dismissOverlay
        self.windowNotificationCenter = windowNotificationCenter
        self.overlayWindowMatcher = overlayWindowMatcher
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
        observeOverlayDismissal()
        presentOverlay()
        startPolling(onGranted: onGranted)
    }

    func dismiss() {
        end(.dismissed)
    }

    private func end(_ outcome: AccessibilityOnboardingEnd) {
        guard isPresenting else {
            return
        }
        stopPolling()
        stopObservingOverlayDismissal()
        dismissOverlay()
        isPresenting = false
        fireEnded(outcome)
    }

    private func observeOverlayDismissal() {
        stopObservingOverlayDismissal()
        overlayCloseObserver = windowNotificationCenter.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else {
                return
            }
            Task { @MainActor in
                guard let self,
                      self.isPresenting,
                      self.overlayWindowMatcher(window) else {
                    return
                }
                self.end(.dismissed)
            }
        }
    }

    private func stopObservingOverlayDismissal() {
        if let overlayCloseObserver {
            windowNotificationCenter.removeObserver(overlayCloseObserver)
            self.overlayCloseObserver = nil
        }
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
