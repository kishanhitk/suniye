import AppKit
import QuartzCore
import SwiftUI

enum FloatingIndicatorLayout {
    static func frame(
        for size: NSSize,
        in visibleFrame: NSRect,
        placement: FloatingIndicatorPlacement?,
        bottomMargin: CGFloat
    ) -> NSRect {
        guard let placement else {
            return defaultFrame(for: size, in: visibleFrame, bottomMargin: bottomMargin)
        }

        let centerX = visibleFrame.minX + visibleFrame.width * placement.centerXRatio.clampedToUnitInterval()
        let bottomY = visibleFrame.minY + visibleFrame.height * placement.bottomYRatio.clampedToUnitInterval()
        let frame = NSRect(
            x: centerX - size.width / 2,
            y: bottomY,
            width: size.width,
            height: size.height
        )
        return clampedFrame(frame, within: visibleFrame)
    }

    static func defaultFrame(for size: NSSize, in visibleFrame: NSRect, bottomMargin: CGFloat) -> NSRect {
        let x = visibleFrame.midX - size.width / 2
        let y = visibleFrame.minY + bottomMargin
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    static func placement(for frame: NSRect, in visibleFrame: NSRect) -> FloatingIndicatorPlacement {
        let clampedFrame = clampedFrame(frame, within: visibleFrame)
        let centerXRatio = visibleFrame.width > 0
            ? (clampedFrame.midX - visibleFrame.minX) / visibleFrame.width
            : 0.5
        let bottomYRatio = visibleFrame.height > 0
            ? (clampedFrame.minY - visibleFrame.minY) / visibleFrame.height
            : 0

        return FloatingIndicatorPlacement(
            centerXRatio: Double(centerXRatio).clampedToUnitInterval(),
            bottomYRatio: Double(bottomYRatio).clampedToUnitInterval()
        )
    }

    static func clampedFrame(_ frame: NSRect, within visibleFrame: NSRect) -> NSRect {
        let maxX = max(visibleFrame.maxX - frame.width, visibleFrame.minX)
        let maxY = max(visibleFrame.maxY - frame.height, visibleFrame.minY)
        let x = min(max(frame.minX, visibleFrame.minX), maxX)
        let y = min(max(frame.minY, visibleFrame.minY), maxY)
        return NSRect(x: x, y: y, width: frame.width, height: frame.height)
    }
}

@MainActor
final class FloatingIndicatorController {
    var onAction: (() -> Void)?
    var onPlacementChanged: ((FloatingIndicatorPlacement?) -> Void)?

    private var panel: NSPanel?
    private var hostingView: NSHostingView<FloatingIndicatorView>?
    private var pointerTrackingTimer: Timer?
    private var hoverExitTask: Task<Void, Never>?
    private var baseState: FloatingIndicatorState = .idle
    private var isHovered = false
    private var anchoredScreenID: CGDirectDisplayID?
    private var customPlacement: FloatingIndicatorPlacement?
    private var hideWhenIdle = false
    private var lastLoggedStateValue: String?
    private var dragStartPanelFrame: NSRect?
    private var dragStartMouseLocation: NSPoint?
    private var isDragging = false
    private var isStarted = false
    private let bottomMargin: CGFloat = 28
    private let animationDuration: TimeInterval = 0.11

    deinit {
        pointerTrackingTimer?.invalidate()
        hoverExitTask?.cancel()
        lastLoggedStateValue = nil
    }

    func start() {
        isStarted = true
        ensurePanel()
        startPointerTracking()
        render()
        AppLogger.shared.log(.info, "floating indicator started")
    }

    func stop() {
        isStarted = false
        pointerTrackingTimer?.invalidate()
        pointerTrackingTimer = nil
        hoverExitTask?.cancel()
        hoverExitTask = nil
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        AppLogger.shared.log(.info, "floating indicator stopped")
    }

    func configure(hideWhenIdle: Bool, placement: FloatingIndicatorPlacement?) {
        let didChangeVisibility = self.hideWhenIdle != hideWhenIdle
        let didChangePlacement = customPlacement != placement
        self.hideWhenIdle = hideWhenIdle
        customPlacement = placement
        guard didChangeVisibility || didChangePlacement else { return }
        guard isStarted else { return }
        render()
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
        guard isStarted else { return }
        render()
    }

    private var effectiveState: FloatingIndicatorState {
        if case .idle = baseState, isHovered {
            return .hover
        }
        return baseState
    }

    private var shouldShowPanel: Bool {
        if hideWhenIdle, case .idle = effectiveState {
            return false
        }
        return true
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
                },
                onDragChanged: { [weak self] in
                    self?.handleDragChanged()
                },
                onDragEnded: { [weak self] in
                    self?.handleDragEnded()
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
        guard shouldShowPanel else { return }
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
        let targetFrame = frame(for: size)

        hostingView.rootView = FloatingIndicatorView(
            state: state,
            onHoverChanged: { [weak self] isHovered in
                self?.setHovered(isHovered)
            },
            onAction: { [weak self] in
                self?.onAction?()
            },
            onDragChanged: { [weak self] in
                self?.handleDragChanged()
            },
            onDragEnded: { [weak self] in
                self?.handleDragEnded()
            }
        )

        panel.ignoresMouseEvents = !panelShouldCaptureMouseEvents
        if !isDragging {
            positionPanel(targetFrame: targetFrame, animated: shouldShowPanel && !panel.frame.equalTo(targetFrame))
        }
        panel.alphaValue = 1
        if shouldShowPanel {
            panel.orderFrontRegardless()
        } else {
            isHovered = false
            panel.orderOut(nil)
        }
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
        guard !isDragging else { return }
        guard effectiveState.tracksPointerScreen else { return }
        guard let screen = currentMouseScreen() else { return }

        if anchoredScreenID != screen.displayID {
            anchoredScreenID = screen.displayID
            positionPanel(targetFrame: frame(for: size(for: effectiveState)), animated: true)
        }
    }

    private func frame(for size: NSSize) -> NSRect {
        let screen = resolvedScreen() ?? currentMouseScreen() ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return .zero }

        anchoredScreenID = screen.displayID
        return FloatingIndicatorLayout.frame(
            for: size,
            in: screen.visibleFrame,
            placement: customPlacement,
            bottomMargin: bottomMargin
        )
    }

    private func positionPanel(targetFrame: NSRect, animated: Bool) {
        guard let panel else { return }
        guard targetFrame != .zero else { return }
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

    private func handleDragChanged() {
        guard canDragCurrentState else { return }
        guard let panel else { return }
        let screen = resolvedScreen() ?? currentMouseScreen() ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        if !isDragging {
            dragStartPanelFrame = panel.frame
            dragStartMouseLocation = NSEvent.mouseLocation
            isDragging = true
        }

        guard let dragStartPanelFrame, let dragStartMouseLocation else { return }
        let mouseLocation = NSEvent.mouseLocation
        let deltaX = mouseLocation.x - dragStartMouseLocation.x
        let deltaY = mouseLocation.y - dragStartMouseLocation.y
        let targetFrame = FloatingIndicatorLayout.clampedFrame(
            NSRect(
                x: dragStartPanelFrame.minX + deltaX,
                y: dragStartPanelFrame.minY + deltaY,
                width: dragStartPanelFrame.width,
                height: dragStartPanelFrame.height
            ),
            within: screen.visibleFrame
        )
        anchoredScreenID = screen.displayID
        positionPanel(targetFrame: targetFrame, animated: false)
    }

    private func handleDragEnded() {
        defer {
            dragStartPanelFrame = nil
            dragStartMouseLocation = nil
            isDragging = false
            render()
        }

        guard canDragCurrentState else { return }
        guard let panel else { return }
        let screen = resolvedScreen() ?? currentMouseScreen() ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        let placement = FloatingIndicatorLayout.placement(for: panel.frame, in: screen.visibleFrame)
        customPlacement = placement
        onPlacementChanged?(placement)
    }

    private var canDragCurrentState: Bool {
        switch effectiveState {
        case .idle, .hover:
            return true
        case .listening, .processing, .error:
            return false
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
        case .listening(_, .editHotkey):
            return NSSize(width: 150, height: 40)
        case .listening:
            return NSSize(width: 124, height: 40)
        case let .processing(message):
            guard let message else {
                return NSSize(width: 128, height: 40)
            }
            let width = min(max(CGFloat(message.count) * 6.5 + 86, 292), 392)
            return NSSize(width: width, height: 40)
        case let .error(message):
            let width = min(max(CGFloat(message.count) * 6.2, 170), 240) + 32
            return NSSize(width: width, height: 52)
        }
    }
}

private extension Double {
    func clampedToUnitInterval() -> Double {
        min(max(self, 0), 1)
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
