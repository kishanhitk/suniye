import AppKit
import SwiftUI

/// The two-screen onboarding flow, rendered as a page on the same glass as the
/// rest of the window. Screen order is the product thesis:
/// 1. Dictate            — microphone, model download, first dictation
/// 2. Dictate in any app — the Accessibility ask, made after value is demonstrated
struct OnboardingView: View {
    @Bindable var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let appIdentity = AppIdentity.current

    private var step: OnboardingStep {
        appState.activeOnboardingStep ?? .speak
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppMetrics.detailSpacing) {
            progressDots

            stepContent
                .id(step)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        )
                )

            Spacer(minLength: AppMetrics.detailSpacing)

            footer
        }
        .frame(maxWidth: AppMetrics.onboardingColumnWidth, alignment: .leading)
        .padding(.horizontal, AppMetrics.detailPaddingHorizontal)
        .padding(.top, AppMetrics.detailPaddingTop)
        .padding(.bottom, AppMetrics.detailPaddingBottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            BehindWindowBlur(material: .underWindowBackground)
                .overlay(MainWindowPalette.windowBackground.opacity(AppMetrics.detailPaneOpacity))
                .ignoresSafeArea()
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: step)
        .animation(SettingsMotion.curve(reduceMotion: reduceMotion), value: appState.asrModelBanner?.title)
        .animation(SettingsMotion.curve(reduceMotion: reduceMotion), value: appState.hasMicPermission)
        .animation(SettingsMotion.curve(reduceMotion: reduceMotion), value: appState.hasAccessibilityPermission)
        .onExitCommand {
            appState.dismissAccessibilityAssist()
        }
        .onAppear {
            appState.refreshPermissionStatus()
        }
        .onChange(of: appState.activeOnboardingStep) { _, _ in
            appState.refreshPermissionStatus()
        }
    }

    // MARK: - Chrome

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.self) { s in
                Circle()
                    .fill(s.rawValue <= step.rawValue ? Color.accentColor : MainWindowPalette.selectedFill)
                    .frame(width: 6, height: 6)

                if s != OnboardingStep.allCases.last {
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(s.rawValue < step.rawValue ? Color.accentColor.opacity(0.5) : MainWindowPalette.selectedFill)
                        .frame(width: 24, height: 1)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count): \(step.title)")
    }

    private func header(title: String, subtitle: String, showsIcon: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if showsIcon {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: AppMetrics.onboardingIconSize, height: AppMetrics.onboardingIconSize)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                DetailPageTitle(title: title)
                Text(subtitle)
                    .font(AppTypography.body)
                    .foregroundStyle(MainWindowPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .speak:
            speakContent
        case .typeAnywhere:
            typeAnywhereContent
        }
    }

    // MARK: - Dictate (the aha screen)

    private var speakContent: some View {
        VStack(alignment: .leading, spacing: AppMetrics.detailSpacing) {
            header(title: OnboardingStep.speak.title, subtitle: speakSubtitle, showsIcon: true)

            if let banner = modelBanner {
                InlineStatusBanner(
                    icon: banner.icon,
                    tint: banner.tint,
                    title: banner.title,
                    detail: banner.detail,
                    progress: banner.progress,
                    actionTitle: banner.actionTitle,
                    action: banner.action
                )
                .transition(SettingsMotion.banner(reduceMotion: reduceMotion))
            }

            SettingsGroup(heading: "Permissions") {
                PermissionRow(appState: appState, presentation: appState.microphonePresentation, askSurface: .onboarding)
            }

            if canPractice {
                practice
                    .transition(SettingsMotion.notice)
            }
        }
    }

    private var speakSubtitle: String {
        if canPractice {
            return "Hold \(appState.hotkeyConfiguration.displayString) and speak. Recognition happens on this Mac. Audio is never uploaded."
        }
        if !appState.hasMicPermission, appState.phase == .downloadingModel {
            return "Allow the microphone while the speech model downloads. Recognition happens on this Mac. Audio is never uploaded."
        }
        return "Recognition happens on this Mac. Audio is never uploaded."
    }

    private var canPractice: Bool {
        appState.hasMicPermission && appState.asrModelReady
    }

    private struct ModelBanner {
        let icon: String
        let tint: Color
        let title: String
        let detail: String
        var progress: Double?
        var actionTitle: String?
        var action: (() -> Void)?
    }

    /// The same banner the Speech Model page shows, plus the two states that
    /// page never has to explain: a disk-space refusal and a model that has not
    /// been downloaded yet.
    private var modelBanner: ModelBanner? {
        if let message = appState.onboardingDiskSpaceMessage {
            return ModelBanner(
                icon: ASRModelBannerState.Tone.error.icon,
                tint: ASRModelBannerState.Tone.error.color,
                title: "Not enough disk space",
                detail: message,
                actionTitle: "Retry",
                action: { appState.retryOnboardingModelDownload() }
            )
        }
        if let banner = appState.asrModelBanner {
            let isDownloading = appState.phase == .downloadingModel
            return ModelBanner(
                icon: banner.tone.icon,
                tint: banner.tone.color,
                title: modelBannerTitle(for: banner, isDownloading: isDownloading),
                detail: isDownloading
                    ? "\(appState.currentASRModelEntry.displayName) · \(appState.modelExpectedSizeText) · \(Int(appState.downloadProgress * 100))%"
                    : banner.detail,
                progress: banner.progress,
                actionTitle: bannerActionTitle(for: banner),
                action: bannerAction(for: banner)
            )
        }
        if !appState.asrModelReady, appState.phase == .needsModel {
            return ModelBanner(
                icon: "arrow.down.circle.fill",
                tint: .accentColor,
                title: "Speech model not downloaded",
                detail: "\(appState.currentASRModelEntry.displayName) (\(appState.modelExpectedSizeText)) recognizes your dictation on this Mac.",
                actionTitle: "Download",
                action: { appState.retryOnboardingModelDownload() }
            )
        }
        return nil
    }

    /// The shared banner titles are Title Case; this screen's own states are
    /// sentence case, so the passthrough states are renamed to match.
    private func modelBannerTitle(for banner: ASRModelBannerState, isDownloading: Bool) -> String {
        if isDownloading {
            return "Downloading speech model"
        }
        switch banner.tone {
        case .info:
            return "Loading speech model"
        case .error:
            return "Speech model failed"
        }
    }

    private func bannerActionTitle(for banner: ASRModelBannerState) -> String? {
        if appState.canCancelASRModelDownload {
            return "Cancel"
        }
        return banner.tone == .error ? "Retry" : nil
    }

    private func bannerAction(for banner: ASRModelBannerState) -> (() -> Void)? {
        if appState.canCancelASRModelDownload {
            return { appState.cancelASRModelDownload() }
        }
        return banner.tone == .error ? { appState.retryOnboardingModelDownload() } : nil
    }

    private var practice: some View {
        let isListening = appState.isOnboardingPracticeRecording

        return VStack(alignment: .leading, spacing: 10) {
            Text("\u{201C}Send the report by Friday morning.\u{201D}")
                .font(AppTypography.body)
                .foregroundStyle(MainWindowPalette.secondaryText)

            VStack(alignment: .leading, spacing: 8) {
                Text("What you said")
                    .font(AppTypography.bodyMedium)
                ScrollView {
                    Text(appState.onboardingPracticeText.isEmpty
                         ? "Your dictation appears here."
                         : appState.onboardingPracticeText)
                        .font(AppTypography.body)
                        .foregroundStyle(appState.onboardingPracticeText.isEmpty
                            ? MainWindowPalette.tertiaryText
                            : Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 72)
                .subtleScrollers()
            }
            .padding(AppMetrics.cardPadding)
            .flatSurface(
                in: RoundedRectangle(cornerRadius: AppMetrics.cardCornerRadius, style: .continuous),
                fill: MainWindowPalette.editorBackground,
                stroke: isListening ? Color.accentColor : MainWindowPalette.cardStroke
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel("What you said")
            .animation(.easeInOut(duration: 0.2), value: isListening)

            practiceStatus
        }
    }

    @ViewBuilder
    private var practiceStatus: some View {
        if appState.isOnboardingPracticeRecording {
            statusLine("Listening…", icon: "waveform", tint: .accentColor)
        } else if appState.isOnboardingPracticeProcessing {
            statusLine("Transcribing…", icon: "ellipsis.circle", tint: .accentColor)
        } else if let result = appState.onboardingPracticeResult {
            switch result.severity {
            case .success:
                statusLine("Done. Next: let \(appIdentity.displayName) type into your apps.", icon: "checkmark.circle.fill", tint: .green)
            case .error:
                statusLine(result.message, icon: "exclamationmark.circle", tint: .orange)
            }
        }
    }

    private func statusLine(_ text: String, icon: String, tint: Color) -> some View {
        Label {
            Text(text)
                .font(AppTypography.subheadline)
                .foregroundStyle(Color.primary)
        } icon: {
            Image(systemName: icon)
                .font(AppTypography.subheadline)
                .foregroundStyle(tint)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Dictate in any app (Accessibility, post-aha)

    private var typeAnywhereContent: some View {
        VStack(alignment: .leading, spacing: AppMetrics.detailSpacing) {
            header(
                title: OnboardingStep.typeAnywhere.title,
                subtitle: appState.hasAccessibilityPermission
                    ? "Hold \(appState.hotkeyConfiguration.displayString) in any app to dictate."
                    : "Let \(appIdentity.displayName) type what you say into the app you are using.",
                showsIcon: false
            )

            SettingsGroup(heading: "Permissions") {
                PermissionRow(appState: appState, presentation: appState.accessibilityPresentation, askSurface: .onboarding)

                if appState.hasAccessibilityPermission, appState.canOpenNotesForInsertionDemo {
                    RowSeparator()
                    notesDemoRow
                        .transition(SettingsMotion.notice)
                }
            }
        }
    }

    private var notesDemoRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                SettingRowLabel(title: "Try it in Notes", info: "A real dictation, typed into a real app.")
                Spacer(minLength: 12)
                if appState.onboardingInsertionDemoCompleted {
                    Label("Typed into Notes", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(MainWindowPalette.secondaryText)
                } else {
                    Button("Open Notes") {
                        appState.openNotesForInsertionDemo()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .font(AppTypography.rowTitle)

            Text(appState.onboardingInsertionDemoCompleted
                 ? "That is the whole product. Finish to keep dictating."
                 : "Click into a note and hold \(appState.hotkeyConfiguration.displayString).")
                .font(AppTypography.subheadline)
                .foregroundStyle(MainWindowPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 4)
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        switch step {
        case .speak:
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Spacer(minLength: 12)
                    Button("Skip for now") {
                        appState.advanceOnboardingFromSpeak()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isDictationInFlight)
                    .accessibilityHint("Continue without a practice dictation")

                    Button("Continue") {
                        appState.advanceOnboardingFromSpeak()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!appState.onboardingPracticeSucceeded || isDictationInFlight)
                    .keyboardShortcut(.defaultAction)
                }

                analyticsConsent
            }

        case .typeAnywhere:
            HStack(spacing: 10) {
                Spacer(minLength: 12)
                if !appState.hasAccessibilityPermission {
                    Button("Later — use ⌘V") {
                        appState.finishOnboarding(deferringAccessibility: true)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Finish setup and copy dictations to the clipboard until access is allowed")
                }

                Button("Finish") {
                    appState.finishOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!appState.hasAccessibilityPermission)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var analyticsConsent: some View {
        Toggle(isOn: $appState.shareAnalyticsEnabled) {
            Text("Share anonymous usage stats to help improve \(appIdentity.displayName).")
                .font(AppTypography.caption)
                .foregroundStyle(MainWindowPalette.tertiaryText)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
    }

    private var isDictationInFlight: Bool {
        appState.phase == .recording || appState.phase == .transcribing
    }
}
