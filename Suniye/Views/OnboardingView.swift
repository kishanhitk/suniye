import AppKit
import SwiftUI

/// First run, in calm screens on one window:
/// 1. Welcome            — the brand, one line of promise, one button
/// 2. Try your first dictation — the words land in a real field
/// 3. Dictate anywhere   — the Accessibility ask, after value is shown
/// 4. There's more       — names the features worth finding later
///
/// Every screen shares the same three tiers: brand on top, the task in the
/// middle, the one action at the bottom.
struct OnboardingView: View {
    @Bindable var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var step: OnboardingStep {
        appState.activeOnboardingStep ?? .welcome
    }

    var body: some View {
        ZStack {
            if step == .welcome {
                OnboardingLandscape()
                    .transition(.opacity)
            }

            VStack(spacing: 0) {
                brand
                    .padding(.top, step == .welcome ? 56 : 44)

                Group {
                    switch step {
                    case .welcome:
                        welcomeMessage
                    case .speak:
                        speakContent
                    case .typeAnywhere:
                        typeAnywhereContent
                    case .more:
                        moreContent
                    }
                }
                .frame(maxWidth: 460)
                .padding(.top, step == .welcome ? 96 : 52)
                .id(step)
                .transition(stepTransition)

                Spacer(minLength: 24)

                actions
                    .padding(.bottom, 26)
            }
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MainWindowPalette.windowBackground)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .easeInOut(duration: 0.45), value: step)
        .onAppear {
            appState.refreshPermissionStatus()
        }
        .onChange(of: appState.activeOnboardingStep) { _, _ in
            appState.refreshPermissionStatus()
        }
    }

    private var stepTransition: AnyTransition {
        guard !reduceMotion else {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 12)),
            removal: .opacity.combined(with: .offset(y: -8))
        )
    }

    // MARK: - Brand

    private var brand: some View {
        VStack(spacing: step == .welcome ? 10 : 8) {
            SuniyeMark(
                size: step == .welcome ? 64 : 44,
                isAnimated: step == .welcome
            )
            Text(AppIdentity.current.displayName)
                .font(.system(size: step == .welcome ? 15 : 13, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.8))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppIdentity.current.displayName)
    }

    // MARK: - Welcome

    private var welcomeMessage: some View {
        VStack(spacing: 14) {
            Text("Speak freely.")
                .font(.system(size: 44, weight: .medium))
                .tracking(-0.8)
            Text("Built for speed and privacy.\nRuns entirely on your Mac.")
                .font(.system(size: 15))
                .lineSpacing(3)
                .foregroundStyle(MainWindowPalette.secondaryText)
        }
        .multilineTextAlignment(.center)
        .modifier(RiseIn(delay: 0.9))
    }

    private var analyticsLine: some View {
        HStack(spacing: 3) {
            Text(appState.shareAnalyticsEnabled ? "Anonymous stats ·" : "Anonymous stats are off")
            if appState.shareAnalyticsEnabled {
                Button("Turn off") {
                    appState.shareAnalyticsEnabled = false
                }
                .buttonStyle(.plain)
                .underline()
                .accessibilityLabel("Turn off anonymous usage stats")
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(MainWindowPalette.tertiaryText)
    }

    // MARK: - Try your first dictation

    private var speakContent: some View {
        VStack(spacing: 6) {
            Text("Try your first dictation")
                .font(.system(size: 28, weight: .semibold))
                .tracking(-0.5)
                .padding(.bottom, 4)
            HStack(spacing: 5) {
                Text("Hold")
                HotkeyCap(configuration: appState.hotkeyConfiguration)
                Text("and say:")
            }
            .font(.system(size: 15))
            .foregroundStyle(MainWindowPalette.secondaryText)
            Text("\u{201C}Send the report by Friday morning.\u{201D}")
                .font(.system(size: 15))
                .foregroundStyle(MainWindowPalette.tertiaryText)

            practiceField
                .padding(.top, 16)

            if let result = appState.onboardingPracticeResult, result.severity == .error, !isDictationInFlight {
                Text(result.message)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .padding(.top, 6)
                    .transition(.opacity)
            }
        }
        .multilineTextAlignment(.center)
        .animation(.easeOut(duration: 0.2), value: appState.onboardingPracticeResult)
    }

    @ViewBuilder
    private var practiceField: some View {
        if appState.hasMicPermissionBeenDenied {
            OnboardingCard {
                Text("Microphone access was denied.")
                    .font(.system(size: 14))
                    .foregroundStyle(MainWindowPalette.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if !appState.asrModelReady {
            OnboardingCard {
                modelStatus
            }
        } else {
            PracticeTextField(
                text: $appState.onboardingPracticeText,
                placeholder: practicePlaceholder,
                isActive: appState.isOnboardingPracticeRecording || !appState.onboardingPracticeText.isEmpty
            )
        }
    }

    private var practicePlaceholder: String {
        if appState.isOnboardingPracticeRecording {
            return "Listening…"
        }
        if appState.isOnboardingPracticeProcessing {
            return "Transcribing…"
        }
        return "Your words will appear here."
    }

    @ViewBuilder
    private var modelStatus: some View {
        VStack(alignment: .leading, spacing: 9) {
            switch appState.phase {
            case .downloadingModel:
                HStack {
                    Text("Downloading speech model")
                    Spacer()
                    Text(verbatim: "\(Int(appState.downloadProgress * 100))%")
                        .monospacedDigit()
                }
                ProgressView(value: appState.downloadProgress)
                    .progressViewStyle(.linear)
            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Getting ready…")
                }
                .frame(maxWidth: .infinity)
            default:
                Text(appState.onboardingDiskSpaceMessage ?? "The speech model is not ready.")
                    .frame(maxWidth: .infinity)
            }
        }
        .font(.system(size: 14))
        .foregroundStyle(MainWindowPalette.secondaryText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Dictate anywhere

    private var typeAnywhereContent: some View {
        let granted = appState.hasAccessibilityPermission
        return VStack(spacing: 6) {
            Text("Dictate anywhere")
                .font(.system(size: 28, weight: .semibold))
                .tracking(-0.5)
                .padding(.bottom, 4)

            if granted {
                HStack(spacing: 5) {
                    Text("Hold")
                    HotkeyCap(configuration: appState.hotkeyConfiguration)
                    Text("in any app to dictate.")
                }
                .font(.system(size: 15))
                .foregroundStyle(MainWindowPalette.secondaryText)
                .transition(.opacity)
            }

            OnboardingCard(height: 58) {
                HStack(spacing: 12) {
                    SuniyeMark(size: 28)
                    Text(granted ? "Ready to dictate" : "Type into any app")
                        .font(.system(size: 14, weight: .medium))
                    Spacer()
                    if granted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.green)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                            .accessibilityLabel("Accessibility allowed")
                    } else {
                        Text("Not allowed")
                            .font(.system(size: 12))
                            .foregroundStyle(MainWindowPalette.tertiaryText)
                    }
                }
                .padding(.horizontal, 4)
            }
            .padding(.top, 14)

            if !granted {
                accessibilityNote
                    .padding(.top, 8)
            }
        }
        .multilineTextAlignment(.center)
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8), value: granted)
    }

    @ViewBuilder
    private var accessibilityNote: some View {
        if appState.accessibilityGrantLikelyStale {
            Text(appState.staleAccessibilityGrantInstruction)
                .font(.system(size: 12))
                .foregroundStyle(.orange)
        } else if appState.accessibilityAssistTimedOut {
            Text("Still waiting for the grant. Open System Settings if the helper got lost.")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
        } else {
            Text("Nothing is ever read from your screen.")
                .font(.system(size: 12))
                .foregroundStyle(MainWindowPalette.tertiaryText)
        }
    }

    // MARK: - There's more

    private var moreContent: some View {
        VStack(spacing: 6) {
            Text("There\u{2019}s more when you need it")
                .font(.system(size: 28, weight: .semibold))
                .tracking(-0.5)
                .padding(.bottom, 14)

            VStack(spacing: 0) {
                MoreRow(
                    symbol: "sparkles",
                    title: "Magic Format",
                    detail: "Corrects and formats your text before it\u{2019}s pasted."
                )
                Divider().padding(.leading, 58)
                MoreRow(
                    symbol: "waveform",
                    title: "Speech Model",
                    detail: "Choose the speech model that suits you."
                )
                Divider().padding(.leading, 58)
                MoreRow(
                    symbol: "text.cursor",
                    title: "Hold to edit selection",
                    detail: "Select text and hold the shortcut to edit it with your voice."
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(MainWindowPalette.cardBackground)
                    .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(MainWindowPalette.cardStroke, lineWidth: 1)
            )
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Actions

    /// One capsule and one quiet line under it, in fixed slots, so the main
    /// button sits in the same place on every screen.
    private var actions: some View {
        // Fixed-size slots that exist even when empty: a frame on a branch that
        // builds nothing collapses to zero, which moved the button between screens.
        VStack(spacing: 10) {
            Color.clear
                .frame(height: 46)
                .overlay { primaryAction }
            Color.clear
                .frame(height: 16)
                .overlay { secondaryAction }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: actionsKey)
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch step {
        case .welcome:
            capsule("Try your first dictation") {
                Task { await appState.beginOnboardingSetup() }
            }
            .modifier(RiseIn(delay: 1.05))
        case .speak:
            if appState.hasMicPermissionBeenDenied {
                capsule("Open Settings") {
                    appState.openMicrophonePrivacySettings()
                }
            } else if appState.onboardingPracticeSucceeded {
                capsule("Continue") {
                    appState.advanceOnboardingFromSpeak()
                }
                .disabled(isDictationInFlight)
                .transition(.opacity.combined(with: .offset(y: 6)))
            }
        case .typeAnywhere:
            if appState.hasAccessibilityPermission {
                capsule("Continue") {
                    appState.advanceOnboardingFromTypeAnywhere()
                }
            } else {
                capsule("Allow Access") {
                    appState.beginAccessibilityOnboarding(askSurface: .onboarding)
                }
            }
        case .more:
            capsule("Finish") {
                appState.finishOnboarding()
            }
        }
    }

    @ViewBuilder
    private var secondaryAction: some View {
        switch step {
        case .welcome:
            if let message = appState.onboardingDiskSpaceMessage {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            } else {
                analyticsLine
            }
        case .speak:
            if appState.hasMicPermissionBeenDenied {
                OnboardingLink("Skip for now") {
                    appState.advanceOnboardingFromSpeak()
                }
            } else if appState.onboardingPracticeSucceeded {
                EmptyView()
            } else if appState.phase == .downloadingModel, appState.canCancelASRModelDownload {
                OnboardingLink("Cancel download") {
                    appState.cancelASRModelDownload()
                }
            } else if appState.phase == .needsModel || appState.phase == .error {
                OnboardingLink("Retry download") {
                    appState.startModelDownload()
                }
            } else if appState.onboardingPracticeAttempts >= 1 {
                OnboardingLink("Skip for now") {
                    appState.advanceOnboardingFromSpeak()
                }
                .disabled(isDictationInFlight)
            }
        case .typeAnywhere:
            if !appState.hasAccessibilityPermission,
               appState.accessibilityGrantLikelyStale || appState.accessibilityAssistTimedOut {
                OnboardingLink("Open System Settings") {
                    appState.openAccessibilityPrivacySettings()
                }
            }
        case .more:
            EmptyView()
        }
    }

    private func capsule(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .padding(.horizontal, 16)
        }
        .modifier(OnboardingPrimaryButton())
        .keyboardShortcut(.defaultAction)
        .transition(.opacity)
    }

    /// Changes whenever the bottom action set changes, so swaps cross-fade.
    private var actionsKey: String {
        [
            "\(step)",
            "\(appState.onboardingPracticeSucceeded)",
            "\(appState.hasMicPermissionBeenDenied)",
            "\(appState.hasAccessibilityPermission)",
            "\(appState.phase)",
        ].joined(separator: "|")
    }

    private var isDictationInFlight: Bool {
        appState.phase == .recording || appState.phase == .transcribing
    }
}

// MARK: - Components

/// The one primary action per screen, as the system draws it: Liquid Glass on
/// macOS 26, the standard prominent capsule before that.
private struct OnboardingPrimaryButton: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .buttonStyle(.glassProminent)
                .controlSize(.extraLarge)
        } else {
            content
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.extraLarge)
        }
    }
}

/// One feature named on the closing screen: what it is, and what it does for you.
private struct MoreRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(MainWindowPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }
}

/// A small text action under the capsule.
private struct OnboardingLink: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(MainWindowPalette.secondaryText)
            .padding(.vertical, 2)
    }
}

/// A white card the size of the practice field, shared by the field's states
/// so swapping between them never moves the layout.
private struct OnboardingCard<Content: View>: View {
    var height: CGFloat = 110
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(MainWindowPalette.cardBackground)
                    .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(MainWindowPalette.cardStroke, lineWidth: 1)
            )
    }
}

/// The first dictation lands here as real, editable text.
private struct PracticeTextField: View {
    @Binding var text: String
    let placeholder: String
    let isActive: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            // A text view only once words have landed: an empty one would take
            // first responder and show the system's input badge for no reason.
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 16))
                    .foregroundStyle(MainWindowPalette.tertiaryText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(.opacity)
            } else {
                TextEditor(text: $text)
                    .font(.system(size: 16))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 10)
                    .transition(.opacity)
            }
        }
        .multilineTextAlignment(.leading)
        .frame(height: 110)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(MainWindowPalette.cardBackground)
                .shadow(color: isActive ? Color.accentColor.opacity(0.18) : .black.opacity(0.06), radius: 10, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isActive ? Color.accentColor : MainWindowPalette.cardStroke, lineWidth: isActive ? 1.5 : 1)
        )
        .animation(.easeOut(duration: 0.2), value: isActive)
        .animation(.easeOut(duration: 0.15), value: placeholder)
        .accessibilityLabel("Your first dictation")
    }
}

/// The dictation key, drawn as a keycap inside the sentence.
private struct HotkeyCap: View {
    let configuration: HotkeyConfiguration

    var body: some View {
        HStack(spacing: 3) {
            if configuration.kind == .globe {
                Image(systemName: "globe")
                    .font(.system(size: 11, weight: .medium))
                Text("fn")
            } else {
                Text(configuration.displayString)
            }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Color.primary.opacity(0.75))
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(MainWindowPalette.cardBackground)
                .shadow(color: .black.opacity(0.14), radius: 0, y: 1.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
        )
        .accessibilityLabel(configuration.displayString)
    }
}

/// Fades content up once, after the icon has drawn itself in.
private struct RiseIn: ViewModifier {
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 6)
            .onAppear {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.7).delay(delay)) {
                    isVisible = true
                }
            }
    }
}
