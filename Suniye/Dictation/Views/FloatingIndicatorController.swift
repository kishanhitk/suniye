import AppKit
import Observation
import SwiftUI

enum FloatingIndicatorLayout {
    /// How close the widest content may come to a screen edge before the pill
    /// grows away from that edge instead of from its center.
    static let edgeMargin: CGFloat = 8

    /// The anchor for a placement on a screen: the saved spot, or the bottom
    /// center above `bottomMargin` when the user never moved the pill.
    static func anchor(
        in visibleFrame: NSRect,
        placement: FloatingIndicatorPlacement?,
        bottomMargin: CGFloat
    ) -> FloatingIndicatorAnchor {
        guard let placement else {
            return anchor(at: CGPoint(x: visibleFrame.midX, y: visibleFrame.minY + bottomMargin), in: visibleFrame)
        }
        let point = CGPoint(
            x: visibleFrame.minX + visibleFrame.width * placement.centerXRatio.clampedToUnitInterval(),
            y: visibleFrame.minY + visibleFrame.height * placement.bottomYRatio.clampedToUnitInterval()
        )
        return anchor(at: point, in: visibleFrame)
    }

    /// The anchor whose idle bar has its bottom center at `point`, kept on the
    /// screen, and growing away from any edge the widest content would cross.
    static func anchor(at point: CGPoint, in visibleFrame: NSRect) -> FloatingIndicatorAnchor {
        let idle = FloatingIndicatorMetrics.idlePillSize
        let x = min(max(point.x, visibleFrame.minX + idle.width / 2), visibleFrame.maxX - idle.width / 2)
        let y = min(max(point.y, visibleFrame.minY), visibleFrame.maxY - idle.height)
        let reach = FloatingIndicatorMetrics.widestContent / 2 + edgeMargin
        let horizontal: FloatingIndicatorAnchor.Horizontal
        if x - reach < visibleFrame.minX {
            horizontal = .leading
        } else if x + reach > visibleFrame.maxX {
            horizontal = .trailing
        } else {
            horizontal = .center
        }
        let vertical: FloatingIndicatorAnchor.Vertical = y + FloatingIndicatorMetrics.tallestContent + edgeMargin > visibleFrame.maxY
            ? .top
            : .bottom
        return FloatingIndicatorAnchor(point: CGPoint(x: x, y: y), horizontal: horizontal, vertical: vertical)
    }

    /// The saved placement for an idle bar whose bottom center is `point`.
    static func placement(for point: CGPoint, in visibleFrame: NSRect) -> FloatingIndicatorPlacement {
        let centerXRatio = visibleFrame.width > 0 ? (point.x - visibleFrame.minX) / visibleFrame.width : 0.5
        let bottomYRatio = visibleFrame.height > 0 ? (point.y - visibleFrame.minY) / visibleFrame.height : 0
        return FloatingIndicatorPlacement(
            centerXRatio: Double(centerXRatio).clampedToUnitInterval(),
            bottomYRatio: Double(bottomYRatio).clampedToUnitInterval()
        )
    }
}

@MainActor
final class FloatingIndicatorController {
    var onAction: (() -> Void)?
    var onMeetingAction: ((MeetingPillAction) -> Void)?
    var onPlacementChanged: ((FloatingIndicatorPlacement?) -> Void)?

    private var panel: NSPanel?
    private let model = FloatingIndicatorModel()
    private var pointerTrackingTimer: Timer?
    private var hoverExitTask: Task<Void, Never>?
    private var baseState: FloatingIndicatorState = .idle
    private var isHovered = false
    private var anchoredScreenID: CGDirectDisplayID?
    private var customPlacement: FloatingIndicatorPlacement?
    private var hideWhenIdle = false
    private var lastLoggedStateValue: String?
    private var anchor: FloatingIndicatorAnchor?
    private var dragStartAnchor: FloatingIndicatorAnchor?
    private var dragStartMouseLocation: NSPoint?
    private var isDragging = false
    private var isStarted = false
    private var reduceMotionObserver: NSObjectProtocol?
    private let bottomMargin: CGFloat = 28
    /// Only a move to another screen animates the window. Apple's "move"
    /// response is 0.4 s.
    private let crossScreenMoveDuration: TimeInterval = 0.4

    deinit {
        pointerTrackingTimer?.invalidate()
        hoverExitTask?.cancel()
        if let reduceMotionObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(reduceMotionObserver)
        }
    }

    func start() {
        isStarted = true
        ensurePanel()
        followReduceMotion()
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
        if let reduceMotionObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(reduceMotionObserver)
            self.reduceMotionObserver = nil
        }
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        AppLogger.shared.log(.info, "floating indicator stopped")
    }

    func configure(hideWhenIdle: Bool, showsMeetingTime: Bool, placement: FloatingIndicatorPlacement?) {
        let didChange = self.hideWhenIdle != hideWhenIdle
            || model.showsMeetingTime != showsMeetingTime
            || customPlacement != placement
        self.hideWhenIdle = hideWhenIdle
        model.showsMeetingTime = showsMeetingTime
        customPlacement = placement
        guard didChange, isStarted else { return }
        render()
    }

    /// The meeting that records now, or nil. While one records the pill shows
    /// it, even when the pill would hide while idle.
    func updateMeeting(_ session: MeetingSession?) {
        model.meeting = session
        guard isStarted else { return }
        render()
    }

    func update(_ state: FloatingIndicatorState) {
        if state.isListening, !baseState.isListening {
            // A new recording starts from silence, not from the last one's voice.
            model.voice.loudness = AudioLevelMeter.silentLoudness
        }
        baseState = state
        if state.isAtRest {
            anchoredScreenID = currentMouseScreen()?.displayID
        } else if anchoredScreenID == nil {
            anchoredScreenID = currentMouseScreen()?.displayID
        }
        if !state.isAtRest {
            hoverExitTask?.cancel()
            hoverExitTask = nil
            isHovered = false
        }
        guard isStarted else { return }
        render()
    }

    /// The microphone's loudness while listening, in dBFS. The dots read it
    /// once a frame; it changes no observed state.
    func updateLoudness(_ loudness: Float) {
        model.voice.loudness = loudness
    }

    private var effectiveState: FloatingIndicatorState {
        if case .idle = baseState, isHovered {
            return .hover
        }
        return baseState
    }

    /// The idle bar is the only shape whose place does not depend on the
    /// anchor's edges, so the edges may change in place only while it shows.
    private var showsOnlyTheIdleBar: Bool {
        effectiveState == .idle && model.meeting == nil
    }

    private var showsPill: Bool {
        !(hideWhenIdle && effectiveState == .idle && model.meeting == nil)
    }

    private func ensurePanel() {
        guard panel == nil else { return }

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: FloatingIndicatorMetrics.panelSize),
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
        // `ignoresMouseEvents` stays unset on purpose: then the window server
        // routes each click by what the panel draws, so the pill and its
        // accessories take clicks and every transparent point of the fixed
        // panel passes them to the app below. Setting it, even to false once,
        // makes the whole panel rectangle take clicks or none.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.animationBehavior = .none

        let host = NSHostingView(
            rootView: FloatingIndicatorView(
                model: model,
                onHoverChanged: { [weak self] isHovered in
                    self?.setHovered(isHovered)
                },
                onAction: { [weak self] in
                    self?.onAction?()
                },
                onMeetingAction: { [weak self] action in
                    self?.onMeetingAction?(action)
                },
                onDragChanged: { [weak self] in
                    self?.handleDragChanged()
                },
                onDragEnded: { [weak self] in
                    self?.handleDragEnded()
                }
            )
        )
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: FloatingIndicatorMetrics.panelSize)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.orderOut(nil)

        self.panel = panel
    }

    private func followReduceMotion() {
        model.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard reduceMotionObserver == nil else { return }
        reduceMotionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            }
        }
    }

    private func setHovered(_ hovered: Bool) {
        guard baseState.isAtRest, showsPill else { return }
        if hovered {
            hoverExitTask?.cancel()
            hoverExitTask = nil
            guard !isHovered else { return }
            isHovered = true
            render()
            return
        }

        guard isHovered, hoverExitTask == nil else { return }
        // A short grace keeps the hint up while the pointer crosses the gap
        // between the pill and the hint.
        hoverExitTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard let self, !Task.isCancelled else { return }
            self.hoverExitTask = nil
            self.isHovered = false
            self.render()
        }
    }

    private func render() {
        ensurePanel()
        guard let panel else { return }
        let state = effectiveState
        model.state = state
        model.hidesWhenIdle = hideWhenIdle
        if !isDragging {
            place(animated: false)
        }
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
                self?.followPointerScreen()
            }
        }
    }

    /// At rest the pill moves to the screen with the pointer.
    private func followPointerScreen() {
        guard !isDragging, effectiveState.isAtRest, let screen = currentMouseScreen() else { return }
        if anchoredScreenID != screen.displayID {
            anchoredScreenID = screen.displayID
            place(animated: true)
        }
    }

    /// Puts the panel where the anchor for the current screen and placement
    /// wants it. The panel only ever moves; it never changes size. A state
    /// change at the same place keeps the edges unless the idle bar shows; a
    /// move to another place takes the edges that fit there.
    private func place(animated: Bool) {
        let screen = resolvedScreen() ?? currentMouseScreen() ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        anchoredScreenID = screen.displayID
        var target = FloatingIndicatorLayout.anchor(in: screen.visibleFrame, placement: customPlacement, bottomMargin: bottomMargin)
        if let anchor, anchor.point == target.point, !showsOnlyTheIdleBar {
            target.horizontal = anchor.horizontal
            target.vertical = anchor.vertical
        }
        apply(target, animated: animated)
    }

    private func apply(_ target: FloatingIndicatorAnchor, animated: Bool) {
        guard let panel else { return }
        anchor = target
        if model.horizontal != target.horizontal {
            model.horizontal = target.horizontal
        }
        if model.vertical != target.vertical {
            model.vertical = target.vertical
        }
        let frame = target.panelFrame
        guard panel.frame != frame else { return }
        // A full-width jump across displays is exactly the vestibular motion
        // Reduce Motion exists to stop.
        if animated, panel.isVisible, !model.reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = crossScreenMoveDuration
                // Decelerating rather than ease-in-ease-out: AppKit's window
                // animator cannot host a real spring, so this approximates the
                // critically damped move the HIG asks for.
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1)
                panel.animator().setFrameOrigin(frame.origin)
            }
        } else {
            panel.setFrameOrigin(frame.origin)
        }
    }

    private func handleDragChanged() {
        guard effectiveState.isAtRest, let anchor else { return }
        if !isDragging {
            dragStartAnchor = anchor
            dragStartMouseLocation = NSEvent.mouseLocation
            isDragging = true
        }

        guard let dragStartAnchor, let dragStartMouseLocation else { return }
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? resolvedScreen() ?? NSScreen.main
        guard let screen else { return }
        let point = CGPoint(
            x: dragStartAnchor.point.x + mouseLocation.x - dragStartMouseLocation.x,
            y: dragStartAnchor.point.y + mouseLocation.y - dragStartMouseLocation.y
        )
        // The pill under the pointer is not the idle bar, so the drag keeps
        // the edges it started with and only translates the panel.
        var target = FloatingIndicatorLayout.anchor(at: point, in: screen.visibleFrame)
        target.horizontal = dragStartAnchor.horizontal
        target.vertical = dragStartAnchor.vertical
        anchoredScreenID = screen.displayID
        apply(target, animated: false)
    }

    /// Ends a drag however the gesture ended: released, cancelled, or cut
    /// off by a state change. Safe to call more than once.
    private func handleDragEnded() {
        guard isDragging else { return }
        isDragging = false
        dragStartAnchor = nil
        dragStartMouseLocation = nil
        if let anchor, let screen = resolvedScreen() {
            // Dropping is the user's own move, so the pill takes the edges
            // that fit its new place now, even while a meeting pill shows.
            let placement = FloatingIndicatorLayout.placement(for: anchor.point, in: screen.visibleFrame)
            customPlacement = placement
            apply(FloatingIndicatorLayout.anchor(in: screen.visibleFrame, placement: placement, bottomMargin: bottomMargin), animated: false)
            onPlacementChanged?(placement)
        }
        render()
    }

    private func resolvedScreen() -> NSScreen? {
        guard let anchoredScreenID else { return nil }
        return NSScreen.screens.first(where: { $0.displayID == anchoredScreenID })
    }

    private func currentMouseScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main ?? NSScreen.screens.first
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
