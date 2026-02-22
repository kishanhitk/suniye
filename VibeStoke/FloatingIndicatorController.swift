import AppKit
import SwiftUI

@MainActor
final class FloatingIndicatorController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<FloatingIndicatorView>?
    private var hideTask: Task<Void, Never>?
    private let panelSize = NSSize(width: 320, height: 116)

    deinit {
        hideTask?.cancel()
    }

    func show(_ state: FloatingIndicatorState, autoHideAfter: TimeInterval? = nil) {
        ensurePanel()
        hideTask?.cancel()
        hideTask = nil

        hostingView?.rootView = FloatingIndicatorView(state: state)
        positionPanel()

        guard let panel else { return }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        AppLogger.shared.log(.info, "floating indicator show state=\(state.logValue)")

        if let autoHideAfter {
            let delayNanos = UInt64(max(autoHideAfter, 0) * 1_000_000_000)
            hideTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: delayNanos)
                guard !Task.isCancelled else { return }
                self?.hide()
            }
        }
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        AppLogger.shared.log(.info, "floating indicator hide")
    }

    private func ensurePanel() {
        guard panel == nil else { return }

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.animationBehavior = .none

        let host = NSHostingView(rootView: FloatingIndicatorView(state: .processing))
        host.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(origin: .zero, size: panelSize))
        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        panel.contentView = container
        panel.orderOut(nil)

        self.panel = panel
        hostingView = host
    }

    private func positionPanel() {
        guard let panel else { return }
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        let frame = screen.visibleFrame
        let x = frame.midX - panelSize.width / 2
        let y = frame.maxY - panelSize.height - 44
        panel.setFrame(NSRect(x: x, y: y, width: panelSize.width, height: panelSize.height), display: false)
    }
}
