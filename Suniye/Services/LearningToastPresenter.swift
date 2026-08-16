import AppKit
import SwiftUI

@MainActor
protocol LearningToastPresenting: AnyObject {
    func showLearnedTerms(_ terms: [String], onUndo: @escaping () -> Void)
}

/// Transient bottom-center panel announcing auto-learned vocabulary with an Undo action.
@MainActor
final class LearningToastPresenter: LearningToastPresenting {
    static let displayDuration: TimeInterval = 5
    /// The toast lives 96pt off the bottom edge, so it enters and leaves along
    /// that edge — the same path in both directions.
    private static let travel: CGFloat = 8
    private static let enterDuration: TimeInterval = 0.22
    private static let exitDuration: TimeInterval = 0.15

    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    /// Reduce Motion keeps the fade (it is not vestibular) and drops the travel.
    private var prefersReducedMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    nonisolated init() {}

    func showLearnedTerms(_ terms: [String], onUndo: @escaping () -> Void) {
        dismiss()

        let hosting = NSHostingController(rootView: LearningToastView(
            terms: terms,
            onUndo: { [weak self] in
                onUndo()
                self?.dismiss()
            }
        ))

        let panel = NSPanel(contentViewController: hosting)
        panel.styleMask = [.borderless, .nonactivatingPanel]
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]

        hosting.view.layoutSubtreeIfNeeded()
        panel.setContentSize(hosting.view.fittingSize)

        var restingOrigin = panel.frame.origin
        if let screen = NSScreen.main {
            restingOrigin = NSPoint(
                x: screen.visibleFrame.midX - panel.frame.width / 2,
                y: screen.visibleFrame.minY + 96
            )
        }

        // Appearing out of nowhere in the corner of the user's eye reads as a
        // glitch; rise into place from the edge the toast belongs to.
        let travel = prefersReducedMotion ? 0 : Self.travel
        panel.setFrameOrigin(NSPoint(x: restingOrigin.x, y: restingOrigin.y - travel))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        self.panel = panel

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.enterDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrameOrigin(restingOrigin)
        }

        dismissTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(Self.displayDuration * 1_000_000_000))
            } catch {
                return
            }
            self?.dismiss()
        }
    }

    private func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil

        guard let panel else {
            return
        }
        // Hand the panel to the exit animation and drop our reference now, so a
        // toast arriving mid-exit is never confused with the one leaving.
        self.panel = nil

        let travel = prefersReducedMotion ? 0 : Self.travel
        let exitOrigin = NSPoint(x: panel.frame.origin.x, y: panel.frame.origin.y - travel)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.exitDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrameOrigin(exitOrigin)
        } completionHandler: {
            panel.orderOut(nil)
        }
    }
}

private struct LearningToastView: View {
    let terms: [String]
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("✨ Learned \(terms.map { "“\($0)”" }.joined(separator: ", "))")
                .font(.system(size: 12, weight: .medium))
            Button("Undo", action: onUndo)
                .buttonStyle(.link)
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
    }
}
