import AppKit
import SwiftUI

/// The website's mountain painting, reduced to three flat ranges in one muted
/// blue. The ranges pan at different speeds for depth, two cloud wisps drift,
/// and a small flock crosses now and then. Everything holds still under
/// Reduce Motion, and the birds stay away.
struct OnboardingLandscape: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasLanded = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                LandscapeScene.draw(in: &context, size: size, time: time, showsBirds: !reduceMotion)
            }
        }
        .opacity(hasLanded ? 1 : 0)
        .offset(y: hasLanded ? 0 : 12)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 1.8)) {
                hasLanded = true
            }
        }
    }
}

/// Pure drawing for the landscape: shapes come from a 500 × 170 design grid
/// whose width is one seamless pan period.
enum LandscapeScene {
    static let ink = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.62, green: 0.72, blue: 0.88, alpha: 1)
            : NSColor(red: 0.227, green: 0.353, blue: 0.549, alpha: 1)
    })

    /// Height of the ranges as a share of the canvas.
    static let groundShare: CGFloat = 0.40
    private static let gridWidth: CGFloat = 500
    private static let gridHeight: CGFloat = 170

    private static let farRidge: [CGPoint] = [
        (0, 100), (30, 94), (60, 88), (90, 92), (120, 80), (150, 70), (172, 62), (190, 56),
        (206, 63), (224, 50), (246, 32), (264, 46), (282, 42), (300, 58), (326, 68),
        (354, 60), (376, 67), (406, 79), (440, 88), (470, 95), (500, 100),
    ].map { CGPoint(x: $0.0, y: $0.1) }

    static func draw(in context: inout GraphicsContext, size: CGSize, time: TimeInterval, showsBirds: Bool) {
        let groundHeight = size.height * groundShare
        let ground = CGRect(x: 0, y: size.height - groundHeight, width: size.width, height: groundHeight)

        drawClouds(in: &context, size: size, time: time)
        if showsBirds {
            drawBirds(in: &context, size: size, time: time)
        }
        drawLayer(in: &context, rect: ground, time: time, period: 160, opacity: 0.07, path: farRange)
        drawLayer(in: &context, rect: ground, time: time, period: 160, opacity: 0.10, stroke: true, path: farSnow)
        drawLayer(in: &context, rect: ground, time: time, period: 100, opacity: 0.09, path: midHills)
        drawLayer(in: &context, rect: ground, time: time, period: 64, opacity: 0.12, path: meadow)
    }

    // MARK: Ranges

    private static func drawLayer(
        in context: inout GraphicsContext,
        rect: CGRect,
        time: TimeInterval,
        period: TimeInterval,
        opacity: Double,
        stroke: Bool = false,
        path: (CGRect) -> Path
    ) {
        let progress = (time / period).truncatingRemainder(dividingBy: 1)
        let shift = -CGFloat(progress) * rect.width
        for copy in 0..<2 {
            let tile = rect.offsetBy(dx: shift + CGFloat(copy) * rect.width, dy: 0)
            let shape = path(tile)
            if stroke {
                context.stroke(shape, with: .color(ink.opacity(opacity)), style: StrokeStyle(lineWidth: 1, lineJoin: .round))
            } else {
                context.fill(shape, with: .color(ink.opacity(opacity)))
            }
        }
    }

    private static func point(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + x / gridWidth * rect.width, y: rect.minY + y / gridHeight * rect.height)
    }

    private static func farRange(_ rect: CGRect) -> Path {
        var path = Path()
        path.move(to: point(0, gridHeight, in: rect))
        for vertex in farRidge {
            path.addLine(to: point(vertex.x, vertex.y, in: rect))
        }
        path.addLine(to: point(gridWidth, gridHeight, in: rect))
        path.closeSubpath()
        return path
    }

    private static func farSnow(_ rect: CGRect) -> Path {
        var path = Path()
        path.move(to: point(224, 50, in: rect))
        path.addLine(to: point(246, 32, in: rect))
        path.addLine(to: point(264, 46, in: rect))
        path.move(to: point(172, 62, in: rect))
        path.addLine(to: point(190, 56, in: rect))
        path.addLine(to: point(206, 63, in: rect))
        return path
    }

    private static func midHills(_ rect: CGRect) -> Path {
        var path = Path()
        path.move(to: point(0, gridHeight, in: rect))
        path.addLine(to: point(0, 124, in: rect))
        path.addCurve(to: point(180, 119, in: rect), control1: point(60, 108, in: rect), control2: point(120, 110, in: rect))
        path.addCurve(to: point(360, 110, in: rect), control1: point(240, 128, in: rect), control2: point(300, 104, in: rect))
        path.addCurve(to: point(500, 124, in: rect), control1: point(420, 116, in: rect), control2: point(460, 124, in: rect))
        path.addLine(to: point(gridWidth, gridHeight, in: rect))
        path.closeSubpath()
        return path
    }

    private static func meadow(_ rect: CGRect) -> Path {
        var path = Path()
        path.move(to: point(0, gridHeight, in: rect))
        path.addLine(to: point(0, 142, in: rect))
        path.addCurve(to: point(252, 144, in: rect), control1: point(84, 130, in: rect), control2: point(166, 136, in: rect))
        path.addCurve(to: point(500, 142, in: rect), control1: point(338, 152, in: rect), control2: point(420, 138, in: rect))
        path.addLine(to: point(gridWidth, gridHeight, in: rect))
        path.closeSubpath()
        return path
    }

    // MARK: Sky

    private struct Cloud {
        let top: CGFloat
        let width: CGFloat
        let period: TimeInterval
        let offset: TimeInterval
        let opacity: Double
    }

    private static let clouds = [
        Cloud(top: 0.27, width: 190, period: 80, offset: 20, opacity: 0.10),
        Cloud(top: 0.45, width: 126, period: 110, offset: 70, opacity: 0.08),
    ]

    private static func drawClouds(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        for cloud in clouds {
            let progress = ((time + cloud.offset) / cloud.period).truncatingRemainder(dividingBy: 1)
            let travel = size.width + cloud.width * 2
            let x = -cloud.width + CGFloat(progress) * travel
            let origin = CGPoint(x: x, y: size.height * cloud.top)
            let w = cloud.width
            var path = Path()
            path.move(to: CGPoint(x: origin.x, y: origin.y + w * 0.10))
            path.addCurve(
                to: CGPoint(x: origin.x + w * 0.65, y: origin.y + w * 0.06),
                control1: CGPoint(x: origin.x + w * 0.2, y: origin.y + w * 0.03),
                control2: CGPoint(x: origin.x + w * 0.43, y: origin.y + w * 0.01)
            )
            path.addCurve(
                to: CGPoint(x: origin.x + w, y: origin.y + w * 0.03),
                control1: CGPoint(x: origin.x + w * 0.78, y: origin.y + w * 0.09),
                control2: CGPoint(x: origin.x + w * 0.88, y: origin.y + w * 0.07)
            )
            context.stroke(path, with: .color(ink.opacity(cloud.opacity)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        }
    }

    private struct Bird {
        let top: CGFloat
        let width: CGFloat
        let opacity: Double
        let period: TimeInterval
        let offset: TimeInterval
        let flapPhase: Double
    }

    /// A loose flock of four, plus one straggler on its own slower path.
    private static let birds = [
        Bird(top: 0.35, width: 25, opacity: 0.38, period: 30, offset: 9.0, flapPhase: 0),
        Bird(top: 0.33, width: 19, opacity: 0.32, period: 30, offset: 8.2, flapPhase: 0.8),
        Bird(top: 0.37, width: 16, opacity: 0.28, period: 30, offset: 7.6, flapPhase: 1.7),
        Bird(top: 0.32, width: 12, opacity: 0.22, period: 30, offset: 6.9, flapPhase: 2.4),
        Bird(top: 0.39, width: 17, opacity: 0.26, period: 46, offset: 30, flapPhase: 1.1),
    ]

    private static func drawBirds(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        for bird in birds {
            let progress = ((time + bird.offset) / bird.period).truncatingRemainder(dividingBy: 1)
            guard let flight = glide(progress) else {
                continue
            }
            let x = flight.x * size.width
            let y = size.height * bird.top + flight.lift * size.height
            let flap = 0.775 + 0.225 * cos(time * 2 * .pi / 3.2 + bird.flapPhase)
            let w = bird.width
            let h = w * 0.43 * CGFloat(flap)
            var path = Path()
            path.move(to: CGPoint(x: x, y: y + h))
            path.addQuadCurve(to: CGPoint(x: x + w * 0.5, y: y + h * 0.8), control: CGPoint(x: x + w * 0.21, y: y))
            path.addQuadCurve(to: CGPoint(x: x + w, y: y + h), control: CGPoint(x: x + w * 0.79, y: y))
            context.stroke(
                path,
                with: .color(ink.opacity(bird.opacity * flight.opacity)),
                style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
            )
        }
    }

    /// One crossing: enter from the left, rise slightly, leave on the right,
    /// then the sky stays empty for the rest of the cycle.
    private static func glide(_ progress: Double) -> (x: CGFloat, lift: CGFloat, opacity: Double)? {
        guard progress < 0.72 else {
            return nil
        }
        let opacity: Double
        switch progress {
        case ..<0.05: opacity = progress / 0.05
        case 0.64...: opacity = (0.72 - progress) / 0.08
        default: opacity = 1
        }
        if progress < 0.5 {
            let t = CGFloat(progress / 0.5)
            return (-0.06 + t * 0.56, -0.03 * t, opacity)
        }
        let t = CGFloat((progress - 0.5) / 0.22)
        return (0.5 + t * 0.56, -0.03 - 0.02 * t, opacity)
    }
}
