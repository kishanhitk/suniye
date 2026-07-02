import Carbon
import AppKit
import SwiftUI

struct DashboardPage: View {
    @Bindable var appState: AppState
    let onNavigate: (MainWindowSection) -> Void

    var body: some View {
        DetailScrollContainer {
            DetailPageTitle(title: "Dashboard")

            if !appState.attentionItems.isEmpty {
                VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
                    ForEach(appState.attentionItems) { item in
                        AttentionTile(item: item) {
                            onNavigate(item.recommendedSection)
                        } onFixAction: { action in
                            appState.handleAttentionFixAction(action)
                        }
                    }
                }
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                DashboardMetricCard(icon: "waveform", iconTint: .blue, value: "\(appState.sessionCount)", label: "Sessions")
                DashboardMetricCard(icon: "calendar", iconTint: .orange, value: "\(appState.todaySessionCount)", label: "Today")
                DashboardMetricCard(icon: "quote.opening", iconTint: .purple, value: appState.wordsTranscribed.abbreviatedString, label: "Words")
                DashboardMetricCard(icon: "clock", iconTint: .green, value: appState.totalDictationSeconds.compactDurationString, label: "Time")
            }

            VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
                SectionHeading(title: "Recent")

                if appState.recentResultsPreview.isEmpty {
                    SurfaceCard {
                        Text("No transcription sessions yet.")
                            .font(AppTypography.body)
                            .foregroundStyle(MainWindowPalette.secondaryText)
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(appState.recentResultsPreview) { result in
                            TranscriptHistoryRow(
                                result: result,
                                onCopy: { appState.copyRecentResult(result) },
                                onDelete: { appState.deleteRecentResult(result) }
                            )
                        }
                    }
                }
            }
        }
    }
}

struct HistoryPage: View {
    @Bindable var appState: AppState

    var body: some View {
        DetailScrollContainer {
            DetailPageTitle(title: "History")

            if appState.recentResults.isEmpty {
                EmptyStateCard(
                    icon: "clock.arrow.circlepath",
                    title: "No History Yet",
                    detail: "Completed dictation sessions will appear here with relative time, duration, copy, and delete actions."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(appState.recentResults) { result in
                        TranscriptHistoryRow(
                            result: result,
                            onCopy: { appState.copyRecentResult(result) },
                            onDelete: { appState.deleteRecentResult(result) }
                        )
                    }
                }
            }
        }
    }
}

struct ModelPage: View {
    @Bindable var appState: AppState
    @State private var isHoveringCurrentModelActions = false
    @State private var hoveredLibraryModelID: ASRModelID?
    private let currentModelColumns = [
        GridItem(.flexible(minimum: 150), spacing: 18, alignment: .leading),
        GridItem(.flexible(minimum: 150), spacing: 18, alignment: .leading)
    ]
    private let libraryModelColumns = [
        GridItem(.flexible(minimum: 120), spacing: 18, alignment: .leading),
        GridItem(.flexible(minimum: 120), spacing: 18, alignment: .leading)
    ]

    var body: some View {
        DetailScrollContainer {
            VStack(alignment: .leading, spacing: 4) {
                DetailPageTitle(title: "ASR Model")
                Text("Choose the offline recognizer Suniye keeps on your Mac.")
                    .font(AppTypography.body)
                    .foregroundStyle(MainWindowPalette.secondaryText)
            }

            if let banner = appState.asrModelBanner {
                InlineStatusBanner(
                    icon: banner.tone.icon,
                    tint: banner.tone.color,
                    title: banner.title,
                    detail: banner.detail,
                    progress: banner.progress
                )
            }

            VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
                SectionHeading(title: "Current Model")
                currentModelCard
            }

            VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
                SectionHeading(title: "Available Models")

                ForEach(appState.availableASRModelEntries) { entry in
                    modelLibraryRow(for: entry)
                }
            }
        }
    }

    private var currentModelCard: some View {
        let entry = appState.currentASRModelEntry

        return SurfaceCard(padding: 18) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Text(entry.displayName)
                                .font(AppTypography.pageTitle)

                            StatusPill(
                                title: appState.modelStatusValue,
                                tint: appState.modelStatusColor
                            )
                        }

                        Text(entry.description)
                            .font(AppTypography.body)
                            .foregroundStyle(MainWindowPalette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        FlowLayout(spacing: 6) {
                            ForEach(entry.badges, id: \.self) { badge in
                                ModelTagBadge(title: badge.rawValue)
                            }
                        }
                    }

                    Spacer(minLength: 24)

                    VStack(alignment: .trailing, spacing: 12) {
                        if appState.modelPrimaryActionTitle != "Current" {
                            Button(appState.modelPrimaryActionTitle) {
                                appState.performPrimaryASRAction(for: entry.id)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!appState.asrModelCanPerformPrimaryAction(for: entry.id))
                        }

                        if appState.asrModelSecondaryActionsEnabled(for: entry.id) {
                            hoverRevealActions(
                                for: entry.id,
                                isVisible: isHoveringCurrentModelActions
                            )
                        }
                    }
                }

                CardDivider()
                    .padding(.vertical, 2)

                LazyVGrid(columns: currentModelColumns, alignment: .leading, spacing: 14) {
                    rowMeta(title: "Speed", value: entry.speedLabel)
                    rowMeta(title: "Quality", value: entry.qualityLabel)
                    rowMeta(title: "Languages", value: entry.languageSummary)
                    rowMeta(title: "Size", value: entry.estimatedSizeText)
                    rowMeta(title: "On disk", value: appState.asrModelInstalledSizeText(for: entry.id))
                }

            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: AppMetrics.cardCornerRadius, style: .continuous)
                .stroke(appState.modelStatusColor.opacity(0.28), lineWidth: 1)
        )
        .onHover { hovering in
            isHoveringCurrentModelActions = hovering
        }
    }

    private func modelLibraryRow(for entry: ASRModelCatalogEntry) -> some View {
        SurfaceCard(padding: 16) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Text(entry.displayName)
                                .font(AppTypography.bodyMedium)

                            StatusPill(
                                title: appState.asrModelStatusText(for: entry.id),
                                tint: appState.asrModelStatusColor(for: entry.id)
                            )
                        }

                        Text(entry.description)
                            .font(AppTypography.body)
                            .foregroundStyle(MainWindowPalette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        FlowLayout(spacing: 6) {
                            ForEach(entry.badges, id: \.self) { badge in
                                ModelTagBadge(title: badge.rawValue)
                            }
                        }
                    }

                    Spacer(minLength: 20)

                    VStack(alignment: .trailing, spacing: 12) {
                        Button(appState.asrModelPrimaryActionTitle(for: entry.id)) {
                            appState.performPrimaryASRAction(for: entry.id)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!appState.asrModelCanPerformPrimaryAction(for: entry.id))

                        if appState.asrModelSecondaryActionsEnabled(for: entry.id) {
                            hoverRevealActions(
                                for: entry.id,
                                isVisible: hoveredLibraryModelID == entry.id
                            )
                        }
                    }
                }

                LazyVGrid(columns: libraryModelColumns, alignment: .leading, spacing: 12) {
                    rowMeta(title: "Size", value: entry.estimatedSizeText)
                    rowMeta(title: "Speed", value: entry.speedLabel)
                    rowMeta(title: "Quality", value: entry.qualityLabel)
                    rowMeta(title: "Languages", value: entry.languageSummary)
                }

                if let progressLabel = appState.asrModelProgressLabel(for: entry.id) {
                    CardDivider()
                        .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 8) {
                        if appState.activeASRModelOperationID == entry.id, appState.phase == .downloadingModel {
                            ProgressView(value: appState.downloadProgress)
                                .progressViewStyle(.linear)
                        } else if appState.activeASRModelOperationID == entry.id, appState.phase == .loading {
                            ProgressView()
                                .controlSize(.small)
                        }

                        Text(progressLabel)
                            .font(AppTypography.caption)
                            .foregroundStyle(MainWindowPalette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: AppMetrics.cardCornerRadius, style: .continuous)
                .stroke(appState.asrModelStatusColor(for: entry.id).opacity(appState.activeASRModelOperationID == entry.id ? 0.4 : 0), lineWidth: 1)
        )
        .onHover { hovering in
            if hovering {
                hoveredLibraryModelID = entry.id
            } else if hoveredLibraryModelID == entry.id {
                hoveredLibraryModelID = nil
            }
        }
    }

    private func hoverRevealActions(for modelID: ASRModelID, isVisible: Bool) -> some View {
        HStack(spacing: 6) {
            ActionIconButton(
                systemName: "folder",
                accessibilityLabel: "Open model folder",
                action: {
                appState.openModelFolder(for: modelID)
                }
            )

            ActionIconButton(
                systemName: "trash",
                accessibilityLabel: "Delete model",
                tint: MainWindowPalette.destructive,
                action: {
                appState.deleteASRModel(modelID)
                }
            )
        }
        .frame(height: AppMetrics.iconButtonSize)
        .opacity(isVisible ? 1 : 0.001)
        .offset(y: isVisible ? 0 : -2)
        .animation(.easeOut(duration: 0.16), value: isVisible)
    }

    private func rowMeta(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppTypography.caption)
                .foregroundStyle(MainWindowPalette.tertiaryText)
            Text(value)
                .font(AppTypography.subheadlineSemibold)
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GeneralPage: View {
    @Bindable var appState: AppState

    var body: some View {
        DetailScrollContainer {
            if !appState.hasMicPermission || !appState.hasAccessibilityPermission {
                VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
                    SectionHeading(title: "Permissions")

                    SurfaceCard {
                        VStack(spacing: 0) {
                            if !appState.hasMicPermission {
                                PermissionActionRow(
                                    title: "Microphone",
                                    detail: "Required to capture dictation audio.",
                                    isGranted: false,
                                    primaryTitle: "Request Access",
                                    primaryAction: {
                                        appState.requestMicrophonePermission()
                                    },
                                    secondaryTitle: "Open Settings",
                                    secondaryAction: {
                                        appState.openMicrophonePrivacySettings()
                                    }
                                )
                            }

                            if !appState.hasMicPermission && !appState.hasAccessibilityPermission {
                                CardDivider()
                                    .padding(.vertical, AppMetrics.toggleDetailVerticalPadding)
                            }

                            if !appState.hasAccessibilityPermission {
                                PermissionActionRow(
                                    title: "Accessibility",
                                    detail: "Required to paste transcribed text into other apps.",
                                    isGranted: false,
                                    primaryTitle: "Request Access",
                                    primaryAction: {
                                        appState.beginAccessibilityOnboarding()
                                    },
                                    secondaryTitle: "Open Settings",
                                    secondaryAction: {
                                        appState.openAccessibilityPrivacySettings()
                                    }
                                )
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
                SectionHeading(title: "Microphone")

                SurfaceCard {
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            Text("Input Device")
                                .font(AppTypography.body)
                            Spacer(minLength: 12)
                            NativePopupPicker(
                                items: inputDeviceChoices,
                                selection: inputDeviceSelection,
                                title: \.title
                            )
                            .frame(maxWidth: 300)
                        }

                        CardDivider()
                            .padding(.vertical, AppMetrics.toggleDetailVerticalPadding)

                        VStack(alignment: .leading, spacing: 8) {
                            Label(
                                appState.effectiveInputDeviceStatusText,
                                systemImage: appState.audioRouteSnapshot == nil
                                    ? "exclamationmark.triangle.fill"
                                    : "mic.fill"
                            )
                            .font(AppTypography.subheadline)
                            .foregroundStyle(
                                appState.audioRouteSnapshot == nil
                                    ? Color.orange
                                    : MainWindowPalette.secondaryText
                            )

                            if let warning = appState.audioRouteWarningText {
                                Text(warning)
                                    .font(AppTypography.subheadline)
                                    .foregroundStyle(MainWindowPalette.secondaryText)
                            }

                            if (appState.audioRouteSnapshot?.inputTransport.isBluetooth == true
                                || appState.audioRouteSnapshot == nil),
                               let recommended = appState.recommendedInputDevice {
                                Button("Use \(recommended.name)") {
                                    appState.useRecommendedInputDevice()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        CardDivider()
                            .padding(.vertical, AppMetrics.toggleDetailVerticalPadding)

                        SettingsToggleRow(
                            title: "Echo Cancellation",
                            detail: "Uses Apple's Voice Processing when the current input and output route supports it. It is bypassed for Bluetooth routes.",
                            isOn: $appState.echoCancellationEnabled
                        )

                        CardDivider()
                            .padding(.vertical, AppMetrics.toggleDetailVerticalPadding)

                        SettingsToggleRow(
                            title: "Sound Feedback",
                            detail: "Play short local sounds when dictation succeeds or fails.",
                            isOn: $appState.soundFeedbackEnabled
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
                SectionHeading(title: "Hotkey")

                SurfaceCard {
                    VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
                        HStack(spacing: 12) {
                            Text("Hold to Dictate")
                                .font(AppTypography.body)
                            Spacer(minLength: 12)
                            HotkeyRecorderButton(
                                configuration: Binding(
                                    get: { appState.hotkeyConfiguration },
                                    set: { newValue in
                                        if let newValue {
                                            appState.hotkeyConfiguration = newValue
                                        }
                                    }
                                )
                            )
                        }
                        CardDivider()
                        Text("Works from any app. Hold the shortcut to record, release to transcribe.")
                            .font(AppTypography.subheadline)
                            .foregroundStyle(MainWindowPalette.secondaryText)
                        CardDivider()
                        HStack(spacing: 12) {
                            Text("Hold to Edit Selection")
                                .font(AppTypography.body)
                            Spacer(minLength: 12)
                            HotkeyRecorderButton(
                                configuration: $appState.editModeHotkeyConfiguration,
                                idleIcon: "pencil.line",
                                allowsClear: true,
                                clearHelp: "Remove the Edit Mode shortcut"
                            )
                        }
                        CardDivider()
                        Text("Select text in any app, hold the shortcut, and speak an instruction like \"make this formal\". With nothing selected, the spoken instruction generates text at the cursor. Requires Magic Format.")
                            .font(AppTypography.subheadline)
                            .foregroundStyle(MainWindowPalette.secondaryText)
                    }
                }
            }

            VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
                SectionHeading(title: "Indicator")

                SurfaceCard {
                    VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
                        SettingsToggleRow(
                            title: "Live Transcription Preview",
                            detail: "Show the transcript in the floating indicator while you dictate. Decoding stays fully local.",
                            isOn: $appState.liveTranscriptionPreviewEnabled
                        )

                        CardDivider()

                        SettingsToggleRow(
                            title: "Hide While Idle",
                            detail: "Hide the floating indicator when Suniye is ready but not actively dictating. When hidden, floating click-to-start is unavailable until the indicator appears again for recording, processing, or errors.",
                            isOn: $appState.hideFloatingIndicatorWhenIdle
                        )

                        CardDivider()

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Indicator Position")
                                    .font(AppTypography.body)
                                Text("Drag the floating pill to place it somewhere that stays out of the way.")
                                    .font(AppTypography.subheadline)
                                    .foregroundStyle(MainWindowPalette.secondaryText)
                            }

                            Spacer(minLength: 12)

                            Button("Reset Position") {
                                appState.resetFloatingIndicatorPlacement()
                            }
                            .buttonStyle(.bordered)
                            .disabled(appState.floatingIndicatorPlacement == nil)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
                SectionHeading(title: "After Paste")

                SurfaceCard {
                    SettingsToggleRow(
                        title: "Auto-press Enter after paste",
                        detail: "Automatically press Enter/Return after pasting transcribed text. You can also still say \"send\" or \"enter\" at the end of a dictation to trigger this per-message.",
                        isOn: $appState.autoSubmitEnabled
                    )
                }
            }

            VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
                SectionHeading(title: "Startup")

                SurfaceCard {
                    VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
                        SettingsToggleRow(
                            title: "Launch at Login",
                            detail: appState.launchAtLoginDetailText,
                            isOn: Binding(
                                get: { appState.launchAtLoginEnabledForUI },
                                set: { appState.setLaunchAtLoginEnabled($0) }
                            )
                        )

                        if let error = appState.launchAtLoginError {
                            Text(error)
                                .font(AppTypography.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: AppMetrics.cardSectionSpacing) {
                SectionHeading(title: "About")

                SurfaceCard {
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Text("Suniye")
                                .font(AppTypography.bodyMedium)
                            Spacer(minLength: 0)
                            Text(appState.appVersionText)
                                .font(AppTypography.codeBodyMedium)
                                .foregroundStyle(MainWindowPalette.secondaryText)
                        }

                        CardDivider()

                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Update Channel")
                                    .font(AppTypography.body)
                                Text(appState.updateChannel.detail)
                                    .font(AppTypography.subheadline)
                                    .foregroundStyle(MainWindowPalette.secondaryText)
                            }

                            Spacer(minLength: 12)

                            Picker(
                                "Update Channel",
                                selection: Binding(
                                    get: { appState.updateChannel },
                                    set: { appState.setUpdateChannel($0) }
                                )
                            ) {
                                ForEach(UpdateChannel.allCases) { channel in
                                    Text(channel.title)
                                        .tag(channel)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 160)
                        }

                        CardDivider()

                        SettingsToggleRow(
                            title: "Automatically Check for Updates",
                            detail: "Suniye checks in the background and asks before installing.",
                            isOn: Binding(
                                get: { appState.automaticallyChecksForUpdates },
                                set: { appState.setAutomaticallyChecksForUpdates($0) }
                            )
                        )

                        CardDivider()

                        HStack(spacing: 8) {
                            Button("Report a Problem") {
                                appState.openIssueReportWindow()
                            }
                            .buttonStyle(.bordered)

                            Spacer(minLength: 12)

                            Button("Check for Updates") {
                                appState.checkForUpdates()
                            }
                            .buttonStyle(.bordered)
                            .disabled(!appState.canCheckForUpdates)
                        }
                    }
                }
            }
        }
    }

    private var inputDeviceChoices: [InputDeviceChoice] {
        let devices = appState.availableInputDevices.map {
            let availability = $0.isAvailable ? "" : " - Unavailable"
            let defaultLabel = $0.isDefault ? " - Default" : ""
            return InputDeviceChoice(
                id: $0.id,
                title: "\($0.name) - \($0.transport.title)\(defaultLabel)\(availability)"
            )
        }
        return [InputDeviceChoice(id: nil, title: "System Default")] + devices
    }

    private var inputDeviceSelection: Binding<InputDeviceChoice> {
        Binding(
            get: {
                inputDeviceChoices.first(where: { $0.id == appState.selectedInputDeviceID })
                    ?? InputDeviceChoice(id: appState.selectedInputDeviceID, title: "System Default")
            },
            set: { appState.selectedInputDeviceID = $0.id }
        )
    }
}

private struct InputDeviceChoice: Hashable {
    let id: String?
    let title: String
}

private struct HotkeyRecorderButton: View {
    @Binding var configuration: HotkeyConfiguration?
    var idleIcon = "globe"
    var allowsClear = false
    var clearHelp = "Remove the shortcut"
    @State private var isCapturing = false
    @State private var localMonitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Button {
                toggleCapture()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isCapturing ? "record.circle" : idleIcon)
                        .font(.headline.weight(.medium))
                    Text(isCapturing ? "Press shortcut" : (configuration?.displayString ?? "Not Set"))
                        .font(AppTypography.codeBodyMedium)
                }
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(MainWindowPalette.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isCapturing ? Color.accentColor.opacity(0.5) : MainWindowPalette.cardStroke, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if allowsClear && configuration != nil && !isCapturing {
                Button {
                    configuration = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(MainWindowPalette.secondaryText)
                }
                .buttonStyle(.plain)
                .help(clearHelp)
            }
        }
        .onDisappear {
            stopCapturing()
        }
    }

    private func toggleCapture() {
        if isCapturing {
            stopCapturing()
        } else {
            startCapturing()
        }
    }

    private func startCapturing() {
        isCapturing = true
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stopCapturing()
                return nil
            }

            // Collision policy is owned by AppState's didSet observers: a colliding
            // capture is written through the binding, rejected there (with the value
            // reverted and a user-visible message), and this view re-renders the
            // reverted configuration.
            if let captured = HotkeyConfiguration.from(event: event) {
                configuration = captured
                stopCapturing()
                return nil
            }

            return event
        }
    }

    private func stopCapturing() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        isCapturing = false
    }
}
