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

    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

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
        if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(
                x: screen.visibleFrame.midX - panel.frame.width / 2,
                y: screen.visibleFrame.minY + 96
            ))
        }
        panel.orderFrontRegardless()
        self.panel = panel

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
        panel?.orderOut(nil)
        panel = nil
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
