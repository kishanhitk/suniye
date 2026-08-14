import AppKit
import ApplicationServices
import Foundation

/// Key events are delivered per-process and carry no window routing, so some
/// apps route them only to their key window. Raising and activating the
/// observed window before typing keeps keystrokes from landing nowhere.
struct SystemComputerUseFocusEnforcer: ComputerUseFocusEnforcing {
    func focusForKeyInput(target: ComputerUseObservedTarget) async throws {
        guard let pid = target.application.processIdentifier else { return }
        let ordinal = target.window.accessibilityOrdinal
        // AXUIElementPerformAction is a synchronous AX round-trip; keep it off
        // the main thread (matches SystemComputerUseAccessibilityActions.run).
        try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let application = AXUIElementCreateApplication(pid)
            let result = SystemComputerUseAccessibilityAPI.applicationWindowElements(
                from: application
            )
            guard result.error == .success,
                  result.windows.indices.contains(ordinal) else {
                return
            }
            AXUIElementPerformAction(result.windows[ordinal], kAXRaiseAction as CFString)
        }.value
        try Task.checkCancellation()
        await activate(pid: pid)
    }

    /// `activate(from:)` names Suniye as the source so the macOS focus-steal
    /// policy permits handing the foreground to the target app.
    @MainActor
    private func activate(pid: Int32) {
        _ = NSRunningApplication(processIdentifier: pid)?
            .activate(from: .current, options: [])
    }
}
