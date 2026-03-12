import SwiftUI

struct ListeningOverlay: View {
    let isVisible: Bool

    @State private var animate = false

    var body: some View {
        ZStack {
            if isVisible {
                Circle()
                    .stroke(Color.white.opacity(0.6), lineWidth: 3)
                    .frame(width: animate ? 150 : 64, height: animate ? 150 : 64)

                Circle()
                    .stroke(Color.white.opacity(0.35), lineWidth: 1.5)
                    .frame(width: animate ? 188 : 76, height: animate ? 188 : 76)

                Image(systemName: "mic.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RadialGradient(
                colors: [Color.black.opacity(isVisible ? 0.25 : 0), .clear],
                center: .center,
                startRadius: 4,
                endRadius: 160
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
