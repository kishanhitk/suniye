import AppKit
import SwiftUI

/// The Meetings group on the General page.
struct MeetingSettingsGroup: View {
    @Bindable var meetings: MeetingCoordinator
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
            ControlSettingRow(title: "Meeting files", info: "Audio is deleted when the transcript is ready.") {
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
            MeetingTemplateEditor(templates: meetings.templates)
        }
        .task(id: editingTemplates) {
            templates = await meetings.templates.templates()
        }
        .sheet(isPresented: $editingNeverAsk) {
            NeverAskSheet(meetings: meetings)
        }
        .task(id: meetings.meetings.count) {
            diskBytes = await meetings.store.diskUsage()
        }
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
