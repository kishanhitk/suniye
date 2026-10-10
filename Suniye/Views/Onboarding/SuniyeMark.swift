import SwiftUI

/// The app icon drawn as vector, so its waveform can move: on Welcome it draws
/// itself in and then breathes; everywhere else it holds still, so it never
/// competes with the screen's own task.
struct SuniyeMark: View {
    let size: CGFloat
    var isAnimated = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawProgress: CGFloat = 1

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(Color(red: 0.957, green: 0.957, blue: 0.965))
                .shadow(color: .black.opacity(0.10), radius: size * 0.08, y: size * 0.03)
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                }

            TimelineView(.animation(paused: !breathes)) { timeline in
                MarkWaveform(motion: breathes ? .breathing(at: timeline.date) : .rest)
                    .trim(from: 0, to: drawProgress)
                    .stroke(
                        Color(white: 0.17),
                        style: StrokeStyle(lineWidth: size * 0.055, lineCap: .round, lineJoin: .round)
                    )
            }
            .padding(size * 0.14)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .onAppear {
            guard isAnimated, !reduceMotion else {
                return
            }
            drawProgress = 0
            withAnimation(.easeInOut(duration: 1.4).delay(0.2)) {
                drawProgress = 1
            }
        }
    }

    private var breathes: Bool {
        isAnimated && !reduceMotion
    }
}

/// The icon's zigzag, traced from the 256-pt app icon. Each inner vertex swings
/// around the centre line on its own phase, so the line moves like a voice
/// rather than pulsing as one shape.
struct MarkWaveform: Shape {
    struct Motion {
        var time: TimeInterval
        var amplitude: Double
        var period: Double

        static let rest = Motion(time: 0, amplitude: 0, period: 1)

        static func breathing(at date: Date) -> Motion {
            Motion(time: date.timeIntervalSinceReferenceDate, amplitude: 0.18, period: 4.2)
        }
    }

    var motion: Motion

    private static let vertices: [CGPoint] = [
        CGPoint(x: 36, y: 127), CGPoint(x: 67, y: 103), CGPoint(x: 100, y: 143),
        CGPoint(x: 128, y: 92), CGPoint(x: 157, y: 152), CGPoint(x: 189, y: 106),
        CGPoint(x: 220, y: 126),
    ]
    private static let phases: [Double] = [0, 0.4, 1.9, 0.9, 2.6, 1.4, 0]

    func path(in rect: CGRect) -> Path {
        // The icon's line spans x 36...220 of a 256 grid; map that span onto the rect.
        let spanX: CGFloat = 184
        let scale = rect.width / spanX
        let centreY: CGFloat = 127
        let angular = 2 * Double.pi / motion.period
        var path = Path()
        for (index, vertex) in Self.vertices.enumerated() {
            let isEnd = index == 0 || index == Self.vertices.count - 1
            let swing = isEnd ? 0 : motion.amplitude * sin(motion.time * angular + Self.phases[index])
            let y = centreY + (vertex.y - centreY) * (1 + swing)
            let point = CGPoint(
                x: rect.minX + (vertex.x - 36) * scale,
                y: rect.midY + (y - centreY) * scale
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}
