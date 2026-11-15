import AppKit
import SwiftUI

/// The Meetings group on the General page.
struct MeetingSettingsGroup: View {
    let appState: AppState
    @State private var editingTemplates = false
    @State private var editingNeverAsk = false
    @State private var diskBytes: Int64?
    @State private var templates: [MeetingTemplate] = []

    var body: some View {
        SettingsGroup(heading: "Meetings") {
            ControlSettingRow(
                title: "When a call starts",
                info: "Suniye notices when a call app starts a call."
            ) {
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

            RowSeparator()
            DisclosureSettingRow(title: "Never ask for", value: neverAskValue) {
                editingNeverAsk = true
            }

            RowSeparator()
            MeetingTranscriptModelRow(appState: appState)

            RowSeparator()
            ControlSettingRow(title: "Default template") {
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
                .fixedSize()
            }

            RowSeparator()
            DisclosureSettingRow(title: "Summary templates", value: "") {
                editingTemplates = true
            }

            RowSeparator()
            ControlSettingRow(
                title: "Keep meeting audio",
                info: "Audio lets you play back and transcribe a meeting again. Transcripts and notes stay until you delete them. A change applies the next time Suniye opens or finishes a transcript."
            ) {
                Picker(
                    "Keep meeting audio",
                    selection: Binding(
                        get: { meetings.settings.audioRetention },
                        set: { retention in meetings.updateSettings { $0.audioRetention = retention } }
                    )
                ) {
                    Text("Until the transcript is ready").tag(MeetingAudioRetention.untilTranscript)
                    Text("7 days").tag(MeetingAudioRetention.sevenDays)
                    Text("30 days").tag(MeetingAudioRetention.thirtyDays)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }

            RowSeparator()
            ControlSettingRow(title: "Meeting files", info: Self.audioRule(meetings.settings.audioRetention)) {
                HStack(spacing: 10) {
                    Text(diskBytes.map(Self.size) ?? "")
                        .foregroundStyle(MainWindowPalette.secondaryText)
                    Button("Show in Finder") {
                        try? FileManager.default.createDirectory(at: meetings.store.rootDirectory, withIntermediateDirectories: true)
                        NSWorkspace.shared.activateFileViewerSelecting([meetings.store.rootDirectory])
                    }
                }
            }
        }
        .sheet(isPresented: $editingTemplates) {
            MeetingTemplateEditor(meetings: meetings)
        }
        .task(id: editingTemplates) {
            templates = await meetings.templates.templates()
        }
        .sheet(isPresented: $editingNeverAsk) {
            NeverAskSheet(meetings: meetings)
        }
        .task(id: [meetings.meetings.count, meetings.audioOnMac.count]) {
            diskBytes = await meetings.store.diskUsage()
        }
    }

    private var meetings: MeetingCoordinator {
        appState.meetings
    }

    private static func audioRule(_ retention: MeetingAudioRetention) -> String {
        guard let days = retention.days else { return "Audio is deleted when the transcript is ready." }
        return "Audio is deleted \(days) days after the meeting."
    }

    /// "0 bytes", not ByteCountFormatter's "Zero KB".
    private static func size(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: bytes)
    }

    private var neverAskValue: String {
        let names = meetings.settings.neverAskBundleIDs.map(Self.appName)
        return names.isEmpty ? "None" : names.joined(separator: ", ")
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
                        Text(MeetingSettingsGroup.appName(bundleID))
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
        ControlSettingRow(title: "Transcript model", info: "Writes the transcript after the recording stops. Dictation keeps its own model.") {
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

    /// A fixed width: a pop-up sizes itself to its widest item, and the
    /// items of models that are not on the Mac carry their download size.
    private var picker: some View {
        Picker(
            "Transcript model",
            selection: Binding(get: { selection }, set: { appState.useForMeetingTranscripts($0) })
        ) {
            Text("Same as dictation").tag(ASRModelID?.none)
            Divider()
            ForEach(appState.asrModelCatalog) { entry in
                Text(label(entry))
                    .tag(ASRModelID?.some(entry.id))
                    .disabled(!appState.isASRModelOnMac(entry.id) && !appState.asrModelCanPerformPrimaryAction(for: entry.id))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 210)
    }

    private func download(_ model: ASRModelID) -> some View {
        HStack(spacing: 8) {
            ProgressView(value: appState.downloadProgress)
                .progressViewStyle(.linear)
                .frame(width: 80)
            Text("\(ASRModelCatalog.entry(for: model).displayName) · \(Int(appState.downloadProgress * 100))%")
                .font(AppTypography.caption)
                .foregroundStyle(MainWindowPalette.secondaryText)
                .monospacedDigit()
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
