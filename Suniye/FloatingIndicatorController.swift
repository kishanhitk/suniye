import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class FloatingIndicatorController {
    var onAction: (() -> Void)?

    private var panel: NSPanel?
    private var hostingView: NSHostingView<FloatingIndicatorView>?
    private var pointerTrackingTimer: Timer?
    private var hoverExitTask: Task<Void, Never>?
    private var baseState: FloatingIndicatorState = .idle
    private var isHovered = false
    private var anchoredScreenID: CGDirectDisplayID?
    private var lastLoggedStateValue: String?
    private let bottomMargin: CGFloat = 28
    private let animationDuration: TimeInterval = 0.11

    deinit {
        pointerTrackingTimer?.invalidate()
        hoverExitTask?.cancel()
        lastLoggedStateValue = nil
    }

    func start() {
        ensurePanel()
        startPointerTracking()
        render()

        guard let panel else { return }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        AppLogger.shared.log(.info, "floating indicator started")
    }

    func stop() {
        pointerTrackingTimer?.invalidate()
        pointerTrackingTimer = nil
        hoverExitTask?.cancel()
        hoverExitTask = nil
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        AppLogger.shared.log(.info, "floating indicator stopped")
    }

    func update(_ state: FloatingIndicatorState) {
        baseState = state
        if state.tracksPointerScreen {
            anchoredScreenID = currentMouseScreen()?.displayID
        } else if anchoredScreenID == nil {
            anchoredScreenID = currentMouseScreen()?.displayID
        }
        if !state.tracksPointerScreen {
            hoverExitTask?.cancel()
            hoverExitTask = nil
            isHovered = false
        }
        render()
    }

    private var effectiveState: FloatingIndicatorState {
        if case .idle = baseState, isHovered {
            return .hover
        }
        return baseState
    }

    private var panelShouldCaptureMouseEvents: Bool {
        switch effectiveState {
        case .idle, .hover:
            return true
        case .listening(_, let source):
            return source == .manual
        case .processing, .error:
            return false
        }
    }

    private func ensurePanel() {
        guard panel == nil else { return }

        let initialSize = size(for: .idle)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.animationBehavior = .none

        let host = NSHostingView(
            rootView: FloatingIndicatorView(
                state: .idle,
                onHoverChanged: { [weak self] isHovered in
                    self?.setHovered(isHovered)
                },
                onAction: { [weak self] in
                    self?.onAction?()
                }
            )
        )
        host.frame = NSRect(origin: .zero, size: initialSize)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.orderOut(nil)

        self.panel = panel
        hostingView = host
    }

    private func setHovered(_ hovered: Bool) {
        guard baseState.tracksPointerScreen else { return }
        if hovered {
            hoverExitTask?.cancel()
            hoverExitTask = nil
            guard !isHovered else { return }
            isHovered = true
            render()
            return
        }

        guard isHovered else { return }
        hoverExitTask?.cancel()
        hoverExitTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard let self, !Task.isCancelled else { return }
            defer { self.hoverExitTask = nil }

            if let panel = self.panel, panel.frame.contains(NSEvent.mouseLocation) {
                return
            }

            self.isHovered = false
            self.render()
        }
    }

    private func render() {
        ensurePanel()

        guard let panel, let hostingView else { return }
        let state = effectiveState
        let size = size(for: state)

        hostingView.rootView = FloatingIndicatorView(
            state: state,
            onHoverChanged: { [weak self] isHovered in
                self?.setHovered(isHovered)
            },
            onAction: { [weak self] in
                self?.onAction?()
            }
        )

        panel.ignoresMouseEvents = !panelShouldCaptureMouseEvents
        positionPanel(size: size, animated: true)
        panel.orderFrontRegardless()
        if lastLoggedStateValue != state.logValue {
            lastLoggedStateValue = state.logValue
            AppLogger.shared.log(.info, "floating indicator update state=\(state.logValue)")
        }
    }

    private func startPointerTracking() {
        guard pointerTrackingTimer == nil else { return }
        pointerTrackingTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickPointerTracking()
            }
        }
    }

    private func tickPointerTracking() {
        guard effectiveState.tracksPointerScreen else { return }
        guard let screen = currentMouseScreen() else { return }

        if anchoredScreenID != screen.displayID {
            anchoredScreenID = screen.displayID
            positionPanel(size: size(for: effectiveState), animated: true)
        }
    }

    private func positionPanel(size: NSSize, animated: Bool) {
        guard let panel else { return }
        let screen = resolvedScreen() ?? currentMouseScreen() ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        anchoredScreenID = screen.displayID
        let frame = screen.visibleFrame
        let x = frame.midX - size.width / 2
        let y = frame.minY + bottomMargin
        let targetFrame = NSRect(x: x, y: y, width: size.width, height: size.height)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = animationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(targetFrame, display: true)
            }
        } else {
            panel.setFrame(targetFrame, display: true)
        }
    }

    private func resolvedScreen() -> NSScreen? {
        guard let anchoredScreenID else { return nil }
        return NSScreen.screens.first(where: { $0.displayID == anchoredScreenID })
    }

    private func currentMouseScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func size(for state: FloatingIndicatorState) -> NSSize {
        switch state {
        case .idle:
            return NSSize(width: 74, height: 7)
        case .hover:
            return NSSize(width: 272, height: 84)
        case .listening:
            return NSSize(width: 116, height: 40)
        case .processing:
            return NSSize(width: 128, height: 40)
        case let .error(message):
            let width = min(max(CGFloat(message.count) * 6.2, 170), 240) + 32
            return NSSize(width: width, height: 52)
        }
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
