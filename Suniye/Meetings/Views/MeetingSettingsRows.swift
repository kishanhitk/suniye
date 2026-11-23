import AppKit
import SwiftUI

/// The sections of the Meetings pane in Settings.
struct MeetingSettingsRows: View {
    let appState: AppState
    @State private var editingTemplates = false
    @State private var editingNeverAsk = false
    @State private var diskBytes: Int64?
    @State private var templates: [MeetingTemplate] = []

    /// Four sections: calls, models, templates, files. Each sheet and load sits
    /// on the row that uses it, because a modifier on a group of sections would
    /// apply to every section in it.
    var body: some View {
        SettingsSection {
            ControlSettingRow(.whenACallStarts) {
                Picker(
                    "When a call starts",
                    selection: Binding(
                        get: { meetings.settings.callStartAction },
                        set: { meetings.chooseCallStartAction($0) }
                    )
                ) {
                    Text("Ask").tag(MeetingCallStartAction.ask)
                    Text("Record Automatically").tag(MeetingCallStartAction.recordAutomatically)
                    Text("Do Nothing").tag(MeetingCallStartAction.doNothing)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }

            // The sheet can only remove apps (the call card adds them), so the
            // row opens nothing while the list is empty.
            DisclosureSettingRow(
                .neverAskFor,
                value: neverAskValue,
                isEnabled: !meetings.settings.neverAskBundleIDs.isEmpty
            ) {
                editingNeverAsk = true
            }
            .sheet(isPresented: $editingNeverAsk) {
                NeverAskSheet(meetings: meetings)
            }
        }

        SettingsSection {
            MeetingTranscriptModelRow(appState: appState)
            MeetingSummaryModelRow(appState: appState)
        }

        SettingsSection {
            ControlSettingRow(.defaultTemplate) {
                // Template names are typed by the user, so the menu is capped.
                CappedWidth(maxWidth: 220) {
                    Picker(
                        "Default template",
                        selection: Binding(
                            get: { meetings.settings.templateID },
                            set: { id in meetings.updateSettings { $0.templateID = id } }
                        )
                    ) {
                        ForEach(templates) { template in
                            Text(template.name).tag(template.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }
            .task(id: editingTemplates) {
                templates = await meetings.templates.templates()
            }

            DisclosureSettingRow(.summaryTemplates, value: "") {
                editingTemplates = true
            }
            .sheet(isPresented: $editingTemplates) {
                MeetingTemplateEditor(meetings: meetings)
            }
        }

        SettingsSection {
            ControlSettingRow(.keepMeetingAudio) {
                Picker(
                    "Keep meeting audio",
                    selection: Binding(
                        get: { meetings.settings.audioRetention },
                        set: { retention in meetings.updateSettings { $0.audioRetention = retention } }
                    )
                ) {
                    Text("Until the Transcript Is Ready").tag(MeetingAudioRetention.untilTranscript)
                    Text("7 days").tag(MeetingAudioRetention.sevenDays)
                    Text("30 days").tag(MeetingAudioRetention.thirtyDays)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }

            ControlSettingRow(.meetingFiles, info: SettingsRowID.meetingFiles.currentInfo(in: appState)) {
                HStack(spacing: 10) {
                    Text(numbers: diskBytes.map(Self.size) ?? "")
                        .foregroundStyle(MainWindowPalette.settingsSecondaryText)
                    Button("Show in Finder") {
                        try? FileManager.default.createDirectory(at: meetings.store.rootDirectory, withIntermediateDirectories: true)
                        NSWorkspace.shared.activateFileViewerSelecting([meetings.store.rootDirectory])
                    }
                }
            }
            .task(id: [meetings.meetings.count, meetings.audioOnMac.count]) {
                diskBytes = await meetings.store.diskUsage()
            }
        }
    }

    private var meetings: MeetingCoordinator {
        appState.meetings
    }

    /// "0 bytes", not ByteCountFormatter's "Zero KB".
    private static func size(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: bytes)
    }

    /// Teams and Webex each have two bundle IDs, so names repeat before the
    /// list removes them.
    private var neverAskValue: String {
        AppNameList.summary(meetings.settings.neverAskBundleIDs.map(Self.appName))
    }

    /// The name that the call card used for the app.
    static func appName(_ bundleID: String) -> String {
        MeetingCallApps.app(forProcess: bundleID)?.name ?? bundleID
    }
}

/// The call apps that get no offer card and no automatic recording.
private struct NeverAskSheet: View {
    let meetings: MeetingCoordinator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Never ask for")
                .font(AppTypography.cardTitle)
            if meetings.settings.neverAskBundleIDs.isEmpty {
                Text("None")
                    .foregroundStyle(MainWindowPalette.secondaryText)
            } else {
                ForEach(meetings.settings.neverAskBundleIDs, id: \.self) { bundleID in
                    HStack {
                        Text(MeetingSettingsRows.appName(bundleID))
                        Spacer()
                        Button("Remove") {
                            meetings.updateSettings { $0.neverAskBundleIDs.removeAll { $0 == bundleID } }
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}

/// The speech model that writes meeting transcripts. A model that is not on
/// the Mac shows its download size, and picking it starts the download.
private struct MeetingTranscriptModelRow: View {
    @Bindable var appState: AppState

    private var selection: ASRModelID? {
        appState.meetings.settings.transcriptModel
    }

    var body: some View {
        ControlSettingRow(.transcriptModel) {
            if let downloading = appState.meetingTranscriptModelDownload {
                download(downloading)
            } else {
                HStack(spacing: 10) {
                    if let selection, !appState.isASRModelOnMac(selection) {
                        Button("Download") { appState.useForMeetingTranscripts(selection) }
                            .disabled(!appState.asrModelCanPerformPrimaryAction(for: selection))
                    }
                    picker
                }
            }
        }
        .task(id: appState.meetingTranscriptModelDownload) {
            await appState.refreshSystemManagedASRAssets()
        }
    }

    /// Capped, not fixed: the items of models that are not on the Mac carry
    /// their download size, and a fixed frame centered the menu away from the
    /// trailing edge the other menus end on.
    private var picker: some View {
        Picker(
            "Transcript model",
            selection: Binding(get: { selection }, set: { appState.useForMeetingTranscripts($0) })
        ) {
            Text("Same as Dictation").tag(ASRModelID?.none)
            Divider()
            ForEach(appState.asrModelCatalog) { entry in
                Text(label(entry))
                    .tag(ASRModelID?.some(entry.id))
                    .disabled(!appState.isASRModelOnMac(entry.id) && !appState.asrModelCanPerformPrimaryAction(for: entry.id))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .modifier(CappedWidthModifier(maxWidth: 210))
    }

    private func download(_ model: ASRModelID) -> some View {
        HStack(spacing: 8) {
            ProgressView(value: appState.downloadProgress)
                .progressViewStyle(.linear)
                .frame(width: 80)
            Text(numbers: "\(ASRModelCatalog.entry(for: model).displayName) · \(Int(appState.downloadProgress * 100))%")
                .font(AppTypography.caption)
                .foregroundStyle(MainWindowPalette.secondaryText)
            if appState.canCancelASRModelDownload {
                Button("Cancel") { appState.cancelASRModelDownload() }
            }
        }
    }

    /// The Speech Model page's words for a model that is not on the Mac.
    private func label(_ entry: ASRModelCatalogEntry) -> String {
        guard !appState.isASRModelOnMac(entry.id) else { return entry.displayName }
        let size = entry.isSystemManaged ? "Built into macOS, not yet downloaded" : "\(entry.sizeDisplayText) to download"
        return "\(entry.displayName) · \(size)"
    }
}
