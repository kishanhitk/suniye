import SwiftUI

/// The Summary tab: the summary, or the state that stands in for it.
struct MeetingSummaryTab: View {
    let meetings: MeetingCoordinator
    let appState: AppState
    let actions: MeetingActions
    let record: MeetingRecord
    let summary: String?
    var isEditable = false
    var edited: (_ markdown: String, _ ended: Bool) -> Void = { _, _ in }

    var body: some View {
        if record.status == .done, let summary {
            MeetingSummaryEditor(markdown: summary, isEditable: isEditable, edited: edited)
        } else {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 16) {
                    state
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private var state: some View {
        switch record.status {
        case .finishing:
            MeetingTranscriptProgressView(progress: meetings.transcriptPasses[record.id]?.progress, isWaiting: meetings.transcriptPasses[record.id]?.waiting ?? false)
        case .done:
            EmptyView()
        case .summarizing:
            summarizing
        case .summaryFailed:
            EmptyStateCard(
                icon: "exclamationmark.triangle",
                title: MeetingStatus.summaryFailedTitle,
                detail: [record.summaryFailure, "Your transcript and notes are saved."].compactMap { $0 }.joined(separator: " ")
            ) {
                Button("Try Again") {
                    Task { await meetings.regenerate(record.id) }
                }
                .buttonStyle(.borderedProminent)
            }
        case .noSpeech:
            EmptyStateCard(
                icon: "mic.slash",
                title: MeetingStatus.noSpeechTitle,
                detail: "The transcript has fewer than \(MeetingSummaryWriter.minimumWords) words."
            ) {
                Button("Delete Meeting…") { actions.confirmDelete(record) }
            }
        case .interrupted:
            EmptyStateCard(
                icon: "exclamationmark.triangle",
                title: MeetingStatus.interruptedTitle,
                detail: [record.transcriptFailure, "The audio is saved."].compactMap { $0 }.joined(separator: " ")
            ) {
                Button("Finish Transcript") { meetings.finishTranscript(record.id) }
                    .buttonStyle(.borderedProminent)
            }
        case .notTranscribed:
            EmptyStateCard(
                icon: "exclamationmark.triangle",
                title: MeetingStatus.notTranscribedTitle,
                detail: MeetingDurationText.savedAudio(of: record)
            ) {
                Button("Finish Transcript") { meetings.finishTranscript(record.id) }
                    .buttonStyle(.borderedProminent)
            }
        case .recording, .paused:
            EmptyView()
        }
    }

    @ViewBuilder
    private var summarizing: some View {
        switch MeetingSummaryAvailability(
            apple: appState.appleMagicFormatAvailability,
            localModel: appState.localGemmaMagicFormatAvailability
        ) {
        case .ready:
            progress("Writing the summary…")
        case .needsDownload:
            EmptyStateCard(
                icon: "sparkles",
                title: "Summaries need a model",
                detail: "Download the summary model. Your transcript is saved."
            ) {
                switch appState.localGemmaInstallState {
                case .downloading, .verifying:
                    VStack(spacing: 8) {
                        if let progress = appState.localGemmaInstallProgress {
                            ProgressView(value: progress)
                                .progressViewStyle(.linear)
                                .frame(width: 260)
                        }
                        Text(appState.localGemmaInstallStatusText)
                            .font(AppTypography.caption)
                            .foregroundStyle(MainWindowPalette.secondaryText)
                        Button("Cancel") { appState.cancelLocalGemmaDownload() }
                    }
                case .notInstalled, .failed, .installed, .unavailable:
                    Button("Download · \(LocalGemmaDefaults.expectedSizeText)") { appState.startLocalGemmaDownload() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!appState.canStartLocalGemmaDownload)
                }
            }
        case .unavailable:
            EmptyStateCard(
                icon: "sparkles",
                title: "Summaries aren’t available on this Mac",
                detail: "They need Apple Intelligence or the local model."
            )
        }
    }

    private func progress(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(AppTypography.body)
                .foregroundStyle(MainWindowPalette.secondaryText)
        }
    }
}

/// The regenerate icon. Its menu writes the summary again with the template
/// that the user picks; the current template has a checkmark.
struct MeetingRegenerateMenu: View {
    let meetings: MeetingCoordinator
    let actions: MeetingActions
    let record: MeetingRecord
    @State private var templates: [MeetingTemplate] = []

    var body: some View {
        Menu {
            Section("Regenerate With") {
                ForEach(templates) { template in
                    let isCurrent = template.id == record.templateID
                    Button {
                        // Another template also becomes the default; the
                        // current one leaves the default as it is.
                        regenerate(templateID: isCurrent ? nil : template.id, templateName: template.name)
                    } label: {
                        if isCurrent {
                            Label(template.name, systemImage: "checkmark")
                        } else {
                            Text(template.name)
                        }
                    }
                }
            }
            Divider()
            Button("Edit Templates…") { actions.editingTemplates = true }
        } label: {
            MeetingIcon(systemName: "arrow.clockwise")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(!record.status.canRegenerate)
        .help("Regenerate Summary")
        .accessibilityLabel("Regenerate Summary")
        .task(id: actions.editingTemplates) {
            templates = await meetings.templates.templates()
        }
    }

    /// A summary that the user edited is replaced only after a question.
    private func regenerate(templateID: String?, templateName: String) {
        Task {
            if await !meetings.regenerateUnlessEdited(record.id, templateID: templateID) {
                actions.replacingSummary = MeetingActions.SummaryReplacement(meetingID: record.id, templateID: templateID, templateName: templateName)
            }
        }
    }
}
