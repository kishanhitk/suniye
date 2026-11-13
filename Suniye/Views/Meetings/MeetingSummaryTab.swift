import SwiftUI

/// The Summary tab: the summary, or the state that stands in for it.
struct MeetingSummaryTab: View {
    let meetings: MeetingCoordinator
    let appState: AppState
    let actions: MeetingActions
    let record: MeetingRecord
    let summary: String?

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                state
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var state: some View {
        if meetings.finishing.contains(record.id) || record.status == .finishing {
            progress("Finishing the transcript...")
        } else {
            switch record.status {
            case .done:
                if let summary {
                    MeetingSummaryBody(markdown: summary)
                }
                MeetingRegenerateMenu(title: "Regenerate", meetings: meetings, actions: actions, record: record)
            case .summarizing:
                summarizing
            case .summaryFailed:
                stateCard(
                    icon: "exclamationmark.triangle",
                    title: "Couldn’t write the summary",
                    detail: [record.summaryFailure, "Your transcript and notes are saved."].compactMap { $0 }.joined(separator: " ")
                ) {
                    Button("Try Again") {
                        Task { await meetings.regenerate(record.id) }
                    }
                }
            case .noSpeech:
                stateCard(
                    icon: "mic.slash",
                    title: "Too little speech to summarize",
                    detail: "The transcript has fewer than \(MeetingSummaryWriter.minimumWords) words."
                ) {
                    Button("Delete Meeting…") { actions.confirmDelete(record) }
                }
            case .interrupted:
                stateCard(
                    icon: "exclamationmark.triangle",
                    title: "A transcript did not finish",
                    detail: "The audio is saved."
                ) {
                    Button("Finish Transcript") { meetings.finishTranscript(record.id) }
                }
            case .recording, .paused, .finishing:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var summarizing: some View {
        switch MeetingSummaryAvailability(
            apple: appState.appleMagicFormatAvailability,
            localModel: appState.localGemmaMagicFormatAvailability
        ) {
        case .ready:
            progress("Writing the summary...")
        case .needsDownload:
            stateCard(
                icon: "sparkles",
                title: "Summaries need the local model",
                detail: "\(LocalGemmaDefaults.expectedSizeText). Your transcript is saved."
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
                    Button("Download") { appState.startLocalGemmaDownload() }
                        .disabled(!appState.canStartLocalGemmaDownload)
                }
            }
        case .unavailable:
            stateCard(
                icon: "sparkles",
                title: "Summaries aren’t available on this Mac",
                detail: "They need Apple Intelligence or the local model."
            ) {
                EmptyView()
            }
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

    private func stateCard<Action: View>(
        icon: String,
        title: String,
        detail: String,
        @ViewBuilder action: () -> Action
    ) -> some View {
        VStack(spacing: 12) {
            EmptyStateCard(icon: icon, title: title, detail: detail)
            action()
        }
        .frame(maxWidth: .infinity)
    }
}

/// "Regenerate" with the same template; its menu picks another template.
struct MeetingRegenerateMenu: View {
    let title: String
    let meetings: MeetingCoordinator
    let actions: MeetingActions
    let record: MeetingRecord
    @State private var templates: [MeetingTemplate] = []

    var body: some View {
        Menu {
            ForEach(templates) { template in
                Button {
                    Task { await meetings.regenerate(record.id, templateID: template.id) }
                } label: {
                    if template.id == record.templateID {
                        Label(template.name, systemImage: "checkmark")
                    } else {
                        Text(template.name)
                    }
                }
            }
            Divider()
            Button("Edit Templates…") { actions.editingTemplates = true }
        } label: {
            Text(title)
        } primaryAction: {
            Task { await meetings.regenerate(record.id) }
        }
        .fixedSize()
        .disabled(record.status == .summarizing || meetings.finishing.contains(record.id))
        .task(id: actions.editingTemplates) {
            templates = await meetings.templates.templates()
        }
    }
}

/// A summary's Markdown as blocks: "## " headings, "- " list lines, and
/// plain lines as paragraphs.
struct MeetingSummaryBody: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                switch block {
                case let .heading(text):
                    Text(text)
                        .font(AppTypography.sectionHeading)
                        .padding(.top, index == 0 ? 0 : 10)
                case let .item(text):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .foregroundStyle(MainWindowPalette.secondaryText)
                        Text(text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case let .paragraph(text):
                    Text(text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(AppTypography.body)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var blocks: [MeetingSummaryBlock] {
        MeetingSummaryBlock.parse(markdown)
    }
}
