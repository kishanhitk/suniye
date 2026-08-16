import SwiftUI

/// Choosing a recogniser is a rare, expert action, so the page states the four
/// facts about the one that is running and puts the other nine behind a single
/// row. Same shape as Magic Format: settings are lines, and the line's value is
/// the answer to the question the line asks.
struct SpeechModelPage: View {
    @Bindable var appState: AppState

    @State private var showsModelChooser = false

    private var entry: ASRModelCatalogEntry {
        appState.currentASRModelEntry
    }

    var body: some View {
        DetailScrollContainer {
            header

            // Progress and failures stay at the top of the page — never behind
            // the row that opens the chooser.
            if let banner = appState.asrModelBanner {
                InlineStatusBanner(
                    icon: banner.tone.icon,
                    tint: banner.tone.color,
                    title: banner.title,
                    detail: banner.detail,
                    progress: banner.progress
                )
            }

            settings
        }
        .sheet(isPresented: $showsModelChooser) {
            SpeechModelSheet(appState: appState)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            DetailPageTitle(title: "Speech Model")
            // The claim this page exists to make.
            Text("Recognition happens on this Mac. Audio is never uploaded.")
                .font(AppTypography.body)
                .foregroundStyle(MainWindowPalette.secondaryText)
        }
    }

    private var settings: some View {
        VStack(spacing: 0) {
            DisclosureSettingRow(
                title: "Model",
                value: entry.displayName
            ) {
                showsModelChooser = true
            }

            RowSeparator()
            ValueSettingRow(title: "Languages", value: entry.languageSummary)

            RowSeparator()
            ValueSettingRow(title: "Speed", value: entry.speedLabel)

            RowSeparator()
            ValueSettingRow(title: "On disk", value: diskText)

            if appState.modelPrimaryActionTitle != "Current" {
                RowSeparator()
                ControlSettingRow(title: "Status") {
                    HStack(spacing: 12) {
                        Text(appState.modelStatusValue)
                            .font(AppTypography.rowTitle)
                            .foregroundStyle(appState.modelStatusColor)

                        Button(appState.modelPrimaryActionTitle) {
                            appState.performPrimaryASRAction(for: entry.id)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(!appState.asrModelCanPerformPrimaryAction(for: entry.id))
                    }
                }
            }

            if appState.asrModelSecondaryActionsEnabled(for: entry.id) {
                RowSeparator()
                DisclosureSettingRow(title: "Reveal in Finder", value: "") {
                    appState.openModelFolder(for: entry.id)
                }
            }
        }
    }

    /// System models are owned by macOS, so there is no footprint to report.
    private var diskText: String {
        entry.isSystemManaged ? "Built into macOS" : appState.asrModelInstalledSizeText(for: entry.id)
    }
}

/// Model chooser. Selecting a row does not switch the recogniser — the button
/// does, and it says whether that means a download. Deleting acts on the row,
/// not on the choice.
struct SpeechModelSheet: View {
    @Bindable var appState: AppState

    @Environment(\.dismiss) private var dismiss
    @State private var selection: ASRModelID?
    @State private var pendingDeleteModelID: ASRModelID?

    /// The model in use leads the list, so the selected radio is on screen the
    /// moment the sheet opens rather than somewhere down a scroll.
    private var models: [ASRModelCatalogEntry] {
        let current = appState.currentASRModelEntry
        return [current] + appState.availableASRModelEntries.filter { $0.id != current.id }
    }

    private var pending: ASRModelID {
        selection ?? appState.currentASRModelEntry.id
    }

    private var isPendingDownloaded: Bool {
        let entry = ASRModelCatalog.entry(for: pending)
        return entry.isSystemManaged || appState.isASRModelDownloaded(pending)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Speech model")
                    .font(AppTypography.cardTitle)
                Text("All of these run on this Mac. Bigger models cover more languages; smaller ones use less memory.")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(MainWindowPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(models.enumerated()), id: \.element.id) { index, entry in
                        modelRow(entry)
                        if index < models.count - 1 {
                            RowSeparator()
                        }
                    }
                }
            }
            .frame(maxHeight: 380)

            HStack(spacing: 10) {
                Spacer(minLength: 12)

                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)

                Button(isPendingDownloaded ? "Use this model" : "Download and use") {
                    appState.performPrimaryASRAction(for: pending)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!appState.asrModelCanPerformPrimaryAction(for: pending))
            }
        }
        .padding(20)
        .frame(width: 600)
        .subtleScrollers()
        .background(MainWindowPalette.windowBackground)
        .confirmationDialog(
            "Delete this model?",
            isPresented: Binding(
                get: { pendingDeleteModelID != nil },
                set: { if !$0 { pendingDeleteModelID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let pendingDeleteModelID {
                    appState.deleteASRModel(pendingDeleteModelID)
                }
                pendingDeleteModelID = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteModelID = nil
            }
        } message: {
            Text("You will have to download it again to use it.")
        }
    }

    private func modelRow(_ entry: ASRModelCatalogEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            StylePageRadioIndicator(isSelected: pending == entry.id, isEnabled: true)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.displayName)
                    .font(AppTypography.rowTitle)
                    .foregroundStyle(Color.primary)

                Text(entry.description)
                    .font(AppTypography.subheadline)
                    .foregroundStyle(MainWindowPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(metaLine(for: entry))
                    .font(AppTypography.caption)
                    .foregroundStyle(MainWindowPalette.tertiaryText)

                if let progressLabel = appState.asrModelProgressLabel(for: entry.id) {
                    VStack(alignment: .leading, spacing: 5) {
                        // Keyed on the slot, not the global phase: switching
                        // to another model mid-download moves phase to .loading
                        // and would otherwise blank this bar.
                        if appState.activeASRModelDownloadID == entry.id {
                            ProgressView(value: appState.downloadProgress)
                                .progressViewStyle(.linear)
                        } else if appState.activeASRModelLoadID == entry.id {
                            ProgressView()
                                .controlSize(.small)
                        }

                        Text(progressLabel)
                            .font(AppTypography.caption)
                            .foregroundStyle(MainWindowPalette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 3)
                }
            }

            Spacer(minLength: 12)

            // Never on the model in use: deleting it silently falls back to
            // whatever else is installed, which is not what a chooser should do
            // on one click.
            if entry.id != appState.currentASRModelEntry.id,
               appState.asrModelSecondaryActionsEnabled(for: entry.id) {
                Button("Delete") {
                    pendingDeleteModelID = entry.id
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .foregroundStyle(MainWindowPalette.destructive)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 2)
        .contentShape(Rectangle())
        .onTapGesture { selection = entry.id }
    }

    /// Size reads as "on disk" once it is downloaded and "to download" before,
    /// so the row never implies the model is taking space it is not.
    private func metaLine(for entry: ASRModelCatalogEntry) -> String {
        var parts = [entry.languageSummary, entry.speedLabel, entry.qualityLabel]

        if entry.isSystemManaged {
            parts.append("Built into macOS")
        } else if appState.isASRModelDownloaded(entry.id) {
            parts.append("\(appState.asrModelInstalledSizeText(for: entry.id)) on disk")
        } else {
            parts.append("\(entry.sizeDisplayText) to download")
        }

        return parts.joined(separator: " \u{00B7} ")
    }
}
