import SwiftUI

struct OnboardingView: View {
    @Bindable var appState: AppState
    @State private var step: Step = .welcome

    enum Step {
        case welcome
        case download
    }

    var body: some View {
        VStack(spacing: 0) {
            if step == .welcome {
                WelcomeView {
                    withAnimation {
                        step = .download
                    }
                }
            } else {
                ModelDownloadView(appState: appState)
            }
        }
    }
}
