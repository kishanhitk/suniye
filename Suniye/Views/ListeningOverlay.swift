import SwiftUI

struct ListeningOverlay: View {
    let isVisible: Bool

    @State private var animate = false

    var body: some View {
        ZStack {
            if isVisible {
                Circle()
                    .stroke(Color.white.opacity(0.6), lineWidth: 4)
                    .frame(width: animate ? 180 : 80, height: animate ? 180 : 80)

                Circle()
                    .stroke(Color.white.opacity(0.35), lineWidth: 2)
                    .frame(width: animate ? 220 : 90, height: animate ? 220 : 90)

                Image(systemName: "mic.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RadialGradient(
                colors: [Color.black.opacity(isVisible ? 0.25 : 0), .clear],
                center: .center,
                startRadius: 4,
                endRadius: 190
            )
        )
        .onChange(of: isVisible) { _, newValue in
            if newValue {
                withAnimation(.easeOut(duration: 0.7).repeatForever(autoreverses: false)) {
                    animate = true
                }
            } else {
                animate = false
            }
        }
    }
}
