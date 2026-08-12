import AppKit
import Observation
import SwiftUI

@MainActor
final class ComputerUseCursorOverlayController {
    static let shared = ComputerUseCursorOverlayController()

    private let cursorSize = CGSize(width: 48, height: 48)
    private let model = ComputerUseCursorViewModel()
    private var panel: ComputerUseCursorPanel?
    private var currentPoint: CGPoint?
    private var currentTarget: ComputerUseCursorTarget?
    private var presentationGeneration: UInt = 0

    func present(_ presentation: ComputerUseCursorPresentation) async throws {
        presentationGeneration &+= 1
        let generation = presentationGeneration

        switch presentation {
        case let .click(point, target, _, clickCount):
            currentTarget = target
            try await move(to: point, generation: generation)
            for clickIndex in 0 ..< clickCount {
                try ensureCurrent(generation)
                model.isPressed = true
                try await Task.sleep(for: .milliseconds(45))
                model.isPressed = false
                if clickIndex + 1 < clickCount {
                    try await Task.sleep(for: .milliseconds(35))
                }
            }
        case let .drag(start, end, target):
            currentTarget = target
            try await move(to: start, generation: generation)
            model.isPressed = true
            do {
                try await move(to: end, generation: generation)
                model.isPressed = false
            } catch {
                model.isPressed = false
                throw error
            }
        case let .scroll(point, target, _, _):
            currentTarget = target
            try await move(to: point, generation: generation)
        }
    }

    func hide() {
        presentationGeneration &+= 1
        model.isPressed = false
        model.isMoving = false
        model.isVisible = false
        currentPoint = nil
        currentTarget = nil
        panel?.alphaValue = 0
        panel?.orderOut(nil)
    }

    private func move(to quartzPoint: CGPoint, generation: UInt) async throws {
        try ensureCurrent(generation)
        let destination = appKitPoint(from: quartzPoint)
        let source = currentPoint ?? NSEvent.mouseLocation
        let distance = hypot(destination.x - source.x, destination.y - source.y)

        ensurePanel(at: source)
        guard let panel else { return }
        model.isVisible = true
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || distance < 2 {
            setPanelCenter(destination)
            currentPoint = destination
            return
        }

        model.isMoving = true
        model.angle = movementAngle(from: source, to: destination)
        let duration = min(0.38, max(0.18, 0.16 + (distance / 2_400)))
        let lift = min(52, max(8, distance * 0.08))
        let startTime = ProcessInfo.processInfo.systemUptime

        while true {
            try ensureCurrent(generation)
            let elapsed = ProcessInfo.processInfo.systemUptime - startTime
            let linearProgress = min(1, elapsed / duration)
            let progress = springProgress(linearProgress)
            let inverse = 1 - progress
            let point = CGPoint(
                x: (source.x * inverse) + (destination.x * progress),
                y: (source.y * inverse) + (destination.y * progress)
                    + (sin(.pi * linearProgress) * lift)
            )
            setPanelCenter(point)
            if linearProgress >= 1 { break }
            try await Task.sleep(for: .milliseconds(16))
        }

        setPanelCenter(destination)
        currentPoint = destination
        model.isMoving = false
        model.angle = 0
    }

    private func ensureCurrent(_ generation: UInt) throws {
        try Task.checkCancellation()
        guard generation == presentationGeneration else {
            throw CancellationError()
        }
    }

    private func ensurePanel(at point: CGPoint) {
        if panel == nil {
            let panel = ComputerUseCursorPanel(
                contentRect: NSRect(origin: .zero, size: cursorSize),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.title = SystemComputerUseCursorPresenter.windowTitle
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .statusBar
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
                .stationary,
                .ignoresCycle,
            ]
            panel.animationBehavior = .none

            let hostingView = NSHostingView(
                rootView: ComputerUseCursorView(model: model)
            )
            hostingView.frame = NSRect(origin: .zero, size: cursorSize)
            hostingView.autoresizingMask = [.width, .height]
            panel.contentView = hostingView
            self.panel = panel
        }
        setPanelCenter(point)
    }

    private func setPanelCenter(_ point: CGPoint) {
        panel?.setFrameOrigin(
            CGPoint(
                x: point.x - (cursorSize.width / 2),
                y: point.y - (cursorSize.height / 2)
            )
        )
    }

    private func appKitPoint(from quartzPoint: CGPoint) -> CGPoint {
        guard let primaryScreen = NSScreen.screens.first else { return quartzPoint }
        return ComputerUseCursorCoordinateSpace.appKitPoint(
            fromQuartz: quartzPoint,
            primaryScreenMaxY: primaryScreen.frame.maxY
        )
    }

    private func springProgress(_ progress: Double) -> CGFloat {
        let omega = 8.0
        let value = 1 - exp(-omega * progress) * (1 + (omega * progress))
        let endValue = 1 - exp(-omega) * (1 + omega)
        return CGFloat(min(1, max(0, value / endValue)))
    }

    private func movementAngle(from source: CGPoint, to destination: CGPoint) -> Double {
        let horizontal = destination.x - source.x
        let vertical = destination.y - source.y
        guard abs(horizontal) + abs(vertical) > 0 else { return 0 }
        return min(8, max(-8, atan2(vertical, horizontal) * 4))
    }

}

private final class ComputerUseCursorPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
@Observable
private final class ComputerUseCursorViewModel {
    var isPressed = false
    var isMoving = false
    var isVisible = false
    var angle = 0.0
}

private struct ComputerUseCursorView: View {
    @Bindable var model: ComputerUseCursorViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            TimelineView(
                .animation(
                    minimumInterval: 1 / 30,
                    paused: reduceMotion || !model.isVisible
                )
            ) { timeline in
                let glow = ComputerUseCursorGlowAnimation.style(
                    at: timeline.date.timeIntervalSinceReferenceDate,
                    reduceMotion: reduceMotion
                )

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.08, green: 0.67, blue: 1).opacity(0.72),
                                Color(red: 0.08, green: 0.67, blue: 1).opacity(0.22),
                                .clear,
                            ],
                            center: .center,
                            startRadius: 2,
                            endRadius: 23
                        )
                    )
                    .blur(radius: model.isPressed ? 2 : 4)
                    .scaleEffect(glow.scale)
                    .opacity(glow.opacity)
            }

            Image(systemName: "cursorarrow")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.72), radius: 1.2, x: 0, y: 1)
        }
        .frame(width: 48, height: 48)
        .rotationEffect(.degrees(model.angle))
        .scaleEffect(
            x: model.isPressed ? 0.82 : (model.isMoving ? 1.08 : 1),
            y: model.isPressed ? 0.82 : (model.isMoving ? 0.94 : 1)
        )
        .animation(.spring(response: 0.18, dampingFraction: 0.82), value: model.isPressed)
        .animation(.spring(response: 0.28, dampingFraction: 1), value: model.isMoving)
        .accessibilityHidden(true)
    }
}

struct ComputerUseCursorGlowStyle: Equatable {
    let scale: CGFloat
    let opacity: Double
}

enum ComputerUseCursorGlowAnimation {
    static let cycleDuration = 2.8

    static func style(at elapsedTime: TimeInterval, reduceMotion: Bool) -> ComputerUseCursorGlowStyle {
        guard !reduceMotion else {
            return ComputerUseCursorGlowStyle(scale: 1, opacity: 0.94)
        }

        let radians = (elapsedTime / cycleDuration) * 2 * Double.pi
        let phase = (sin(radians) + 1) / 2
        return ComputerUseCursorGlowStyle(
            scale: 0.98 + (0.04 * phase),
            opacity: 0.88 + (0.12 * phase)
        )
    }
}
