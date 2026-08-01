import AppKit
import SwiftUI

/// The 3-screen onboarding flow. Screen order is the product thesis:
/// 1. Welcome       — value + starts the model download in the background
/// 2. Speak         — mic grant + first successful dictation (the aha), before any scary ask
/// 3. Type Anywhere — the Accessibility ask, made after value is demonstrated
struct OnboardingView: View {
    @Bindable var appState: AppState
    private let appIdentity = AppIdentity.current

    private var step: OnboardingStep {
        appState.activeOnboardingStep ?? .welcome
    }

    var body: some View {
        VStack(spacing: 0) {
            onboardingProgressDots
                .padding(.top, 28)

            Spacer()

            onboardingBrandHeader

            stepContent
                .frame(maxWidth: 420)
                .padding(.top, 20)
                .id(step)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

            Spacer()
            Spacer()

            navigationButtons
                .frame(maxWidth: 420)
                .padding(.bottom, 36)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MainWindowPalette.windowBackground)
        .animation(.easeInOut(duration: 0.3), value: step)
        .onAppear {
            appState.refreshPermissionStatus()
        }
        .onChange(of: appState.activeOnboardingStep) { _, _ in
            appState.refreshPermissionStatus()
        }
    }

    // MARK: - Progress

    private var onboardingProgressDots: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.self) { s in
                Circle()
                    .fill(s.rawValue <= step.rawValue ? Color.accentColor : MainWindowPalette.cardStroke)
                    .frame(width: 6, height: 6)

                if s != OnboardingStep.allCases.last {
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(s.rawValue < step.rawValue ? Color.accentColor.opacity(0.5) : MainWindowPalette.cardStroke)
                        .frame(width: 24, height: 1)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count): \(step.title)")
    }

    private var onboardingBrandHeader: some View {
        let iconSize: CGFloat = step == .welcome ? 64 : 48

        return VStack(spacing: step == .welcome ? 10 : 6) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: iconSize, height: iconSize)

            Text(appIdentity.displayName)
                .font(AppTypography.bodyMedium)
                .foregroundStyle(MainWindowPalette.secondaryText)
        }
        .accessibilityHidden(true)
        .animation(.easeInOut(duration: 0.3), value: step)
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        VStack(spacing: 18) {
            switch step {
            case .welcome:
                welcomeContent
            case .speak:
                speakContent
            case .typeAnywhere:
                typeAnywhereContent
            }
        }
    }

    // MARK: - Welcome

    private var welcomeContent: some View {
        VStack(spacing: 16) {
            WelcomeView()

            if let message = appState.onboardingDiskSpaceMessage {
                Text(message)
                    .font(AppTypography.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var analyticsDisclosure: some View {
        HStack(spacing: 4) {
            Text(appState.shareAnalyticsEnabled
                 ? "Anonymous usage stats help improve \(appIdentity.displayName)."
                 : "Anonymous usage stats are off.")
                .font(AppTypography.caption)
                .foregroundStyle(MainWindowPalette.tertiaryText)

            if appState.shareAnalyticsEnabled {
                Button("Turn off") {
                    appState.shareAnalyticsEnabled = false
                }
                .buttonStyle(.plain)
                .font(AppTypography.caption)
                .foregroundStyle(MainWindowPalette.secondaryText)
                .underline()
                .accessibilityLabel("Turn off anonymous usage stats")
            }
        }
    }

    // MARK: - Speak (the aha screen)

    private var speakContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Say something")
                    .font(AppTypography.pageTitle)
                Text(speakSubtitle)
                    .font(AppTypography.body)
                    .foregroundStyle(MainWindowPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !appState.hasMicPermission {
                microphoneCard
            }

            if !appState.asrModelReady {
                modelStatusCard
            }

            practiceTextArea

            if appState.isOnboardingPracticeRecording {
                practiceStatusLabel("Listening...", color: .accentColor)
            } else if appState.isOnboardingPracticeProcessing {
                practiceStatusLabel("Transcribing...", color: .accentColor)
            } else if let result = appState.onboardingPracticeResult {
                practiceStatusLabel(result.message, color: result.severity.color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var speakSubtitle: String {
        if !appState.hasMicPermission {
            return "One permission and you can watch your words appear."
        }
        if !appState.asrModelReady {
            return "The speech model is almost ready — everything stays on your Mac."
        }
        return "Hold \(appState.hotkeyConfiguration.displayString) and try the phrase below."
    }

    private var microphoneCard: some View {
        SurfaceCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "mic")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MainWindowPalette.secondaryText)
                    Text("Microphone")
                        .font(AppTypography.bodyMedium)
                    Spacer(minLength: 12)

                    if appState.hasMicPermissionBeenDenied {
                        Button("Open Settings") {
                            appState.openMicrophonePrivacySettings()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .accessibilityLabel("Open System Settings to enable the microphone")
                    } else {
                        Button("Allow Microphone") {
                            appState.requestMicrophonePermission(askSurface: .onboarding)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .accessibilityLabel("Allow microphone access")
                    }
                }

                Text(appState.hasMicPermissionBeenDenied
                     ? "Microphone access was denied. Turn it on in System Settings, then come back — this screen updates by itself."
                     : "\(appIdentity.displayName) listens only while you hold the hotkey. Audio never leaves your Mac.")
                    .font(AppTypography.caption)
                    .foregroundStyle(MainWindowPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var modelStatusCard: some View {
        SurfaceCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                if appState.phase == .downloadingModel {
                    HStack {
                        Text("Preparing the speech model")
                            .font(AppTypography.body)
                        Spacer()
                        Text(verbatim: "\(Int(appState.downloadProgress * 100))%")
                            .font(AppTypography.codeCaption)
                            .foregroundStyle(MainWindowPalette.secondaryText)
                    }

                    ProgressView(value: appState.downloadProgress)
                        .progressViewStyle(.linear)

                    HStack(spacing: 8) {
                        (mixedMonoNumberText(ByteCountFormatter.string(
                            fromByteCount: Int64(Double(appState.modelExpectedByteCount) * appState.downloadProgress),
                            countStyle: .file
                        ))
                        + Text(" of ")
                            .font(AppTypography.caption)
                        + mixedMonoNumberText(appState.modelExpectedSizeText))

                        Spacer(minLength: 12)

                        mixedMonoNumberText(appState.modelDownloadETAStatusText)

                        Button("Cancel") {
                            appState.cancelASRModelDownload()
                        }
                        .buttonStyle(.plain)
                        .font(AppTypography.caption)
                        .foregroundStyle(MainWindowPalette.secondaryText)
                        .underline()
                        .disabled(!appState.canCancelASRModelDownload)
                        .accessibilityLabel("Cancel the model download")
                    }
                    .foregroundStyle(MainWindowPalette.secondaryText)
                } else if appState.phase == .loading {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Setting up the speech model...")
                            .font(AppTypography.body)
                            .foregroundStyle(MainWindowPalette.secondaryText)
                    }
                } else if appState.phase == .error {
                    if let error = appState.lastError, !error.isEmpty {
                        Text(error)
                            .font(AppTypography.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button("Retry Download") {
                        appState.startModelDownload()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    HStack {
                        Text("Speech model")
                            .font(AppTypography.body)
                        Spacer()
                        Button("Download") {
                            appState.startModelDownload()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    Text("A one-time download so transcription runs offline on your Mac.")
                        .font(AppTypography.caption)
                        .foregroundStyle(MainWindowPalette.secondaryText)
                }
            }
        }
    }

    private var practicePlaceholder: String {
        if !appState.hasMicPermission || !appState.asrModelReady {
            return "Your words will appear here..."
        }
        return "Hold \(appState.hotkeyConfiguration.displayString) and say: \u{201C}Send the report by Friday morning.\u{201D}"
    }

    private var practiceTextArea: some View {
        let isActive = appState.isOnboardingPracticeRecording

        return ScrollView {
            Text(appState.onboardingPracticeText.isEmpty
                 ? practicePlaceholder
                 : appState.onboardingPracticeText)
                .font(AppTypography.body)
                .foregroundStyle(appState.onboardingPracticeText.isEmpty
                    ? MainWindowPalette.tertiaryText
                    : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .frame(height: 140)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(MainWindowPalette.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isActive ? Color.accentColor : MainWindowPalette.cardStroke,
                        lineWidth: isActive ? 1.5 : 1)
        )
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }

    private func practiceStatusLabel(_ text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(text)
                .font(AppTypography.caption)
                .foregroundStyle(color)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Type Anywhere (Accessibility, post-aha)

    private var typeAnywhereContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Put your words in any app")
                    .font(AppTypography.pageTitle)
                Text(appState.hasAccessibilityPermission
                     ? "Accessibility is on — dictation lands wherever your cursor is."
                     : "Accessibility permission lets \(appIdentity.displayName) type what you say directly into Mail, Slack — anywhere your cursor is.")
                    .font(AppTypography.body)
                    .foregroundStyle(MainWindowPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SurfaceCard(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "hand.raised")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(MainWindowPalette.secondaryText)
                        Text("Accessibility")
                            .font(AppTypography.bodyMedium)
                        Spacer(minLength: 12)

                        if appState.hasAccessibilityPermission {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.system(size: 15))
                                .accessibilityLabel("Accessibility granted")
                        } else {
                            HStack(spacing: 8) {
                                Button("Open Settings") {
                                    appState.openAccessibilityPrivacySettings()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .accessibilityLabel("Open System Settings to enable Accessibility")

                                Button("Enable") {
                                    appState.beginAccessibilityOnboarding(askSurface: .onboarding)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .accessibilityLabel("Enable Accessibility")
                            }
                        }
                    }

                    if appState.hasAccessibilityPermission {
                        HStack(spacing: 10) {
                            Text("Try a real one: open Notes, click into a note, and hold \(appState.hotkeyConfiguration.displayString).")
                                .font(AppTypography.caption)
                                .foregroundStyle(MainWindowPalette.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer(minLength: 8)

                            Button("Open Notes") {
                                appState.openNotesForInsertionDemo()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    } else if appState.accessibilityGrantLikelyStale {
                        Text("macOS reset this permission after an update. In the Accessibility list, toggle \(appIdentity.displayName) off and back on.")
                            .font(AppTypography.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if appState.accessibilityAssistTimedOut {
                        Text("Still waiting for the grant — use Open Settings if the helper got lost.")
                            .font(AppTypography.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Drag \(appIdentity.displayName) into the Accessibility list — takes five seconds. Nothing is ever read from your screen.")
                            .font(AppTypography.caption)
                            .foregroundStyle(MainWindowPalette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Navigation

    @ViewBuilder
    private var navigationButtons: some View {
        switch step {
        case .welcome:
            VStack(spacing: 10) {
                Button {
                    appState.beginOnboardingSetup()
                } label: {
                    Text("Get Started")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                analyticsDisclosure
            }

        case .speak:
            HStack {
                if !appState.onboardingPracticeSucceeded, showsSpeakEscapeHatch {
                    Button("Skip for now") {
                        appState.advanceOnboardingFromSpeak()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isDictationInFlight)
                    .accessibilityHint("Continue without a practice dictation")
                }

                Spacer()

                Button("Continue") {
                    appState.advanceOnboardingFromSpeak()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!appState.onboardingPracticeSucceeded || isDictationInFlight)
                .keyboardShortcut(.defaultAction)
            }

        case .typeAnywhere:
            HStack {
                if !appState.hasAccessibilityPermission {
                    Button("Later — I'll paste with ⌘V") {
                        appState.finishOnboarding()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Finish without Accessibility; dictations go to the clipboard")
                }

                Spacer()

                Button("Finish") {
                    appState.finishOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!appState.hasAccessibilityPermission)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var isDictationInFlight: Bool {
        appState.phase == .recording || appState.phase == .transcribing
    }

    /// The Speak screen must never trap anyone: the escape hatch appears after a
    /// failed attempt, or when the mic was denied (no practice is possible).
    private var showsSpeakEscapeHatch: Bool {
        appState.onboardingPracticeAttempts >= 1 || appState.hasMicPermissionBeenDenied
    }

    private func mixedMonoNumberText(_ value: String) -> Text {
        let monoCharacterSet = CharacterSet.decimalDigits.union(CharacterSet(charactersIn: "%.,:/+-"))
        var segments: [(String, Bool)] = []
        var current = ""
        var currentIsMono = false

        for character in value {
            let isMono = character.unicodeScalars.allSatisfy { monoCharacterSet.contains($0) }

            if current.isEmpty {
                current = String(character)
                currentIsMono = isMono
                continue
            }

            if isMono == currentIsMono {
                current.append(character)
            } else {
                segments.append((current, currentIsMono))
                current = String(character)
                currentIsMono = isMono
            }
        }

        if !current.isEmpty {
            segments.append((current, currentIsMono))
        }

        return segments.reduce(Text("")) { partial, segment in
            partial + Text(verbatim: segment.0)
                .font(segment.1 ? AppTypography.codeCaption : AppTypography.caption)
        }
    }
}

private extension OnboardingPracticeResult.Severity {
    var color: Color {
        switch self {
        case .success:
            .green
        case .error:
            .red
        }
    }
}
