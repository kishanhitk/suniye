import SwiftUI

struct IssueReportView: View {
    @Bindable var appState: AppState
    var onClose: () -> Void = {}

    var body: some View {
        Group {
            switch appState.issueReportStatus {
            case .sent:
                successView
            case .idle, .preparing, .sending, .failed:
                formView
            }
        }
        .background(MainWindowPalette.windowBackground)
    }

    private var formView: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    issueTypePicker
                    titleField
                    descriptionField
                    contactField
                    diagnosticsSection
                    statusView
                }
                .padding(24)
            }

            footer
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Report a Problem")
                .font(AppTypography.pageTitle)
                .foregroundStyle(Color.primary)
            Text("Tell us what went wrong. You can include sanitized diagnostics if they would help us find the rough edge faster.")
                .font(AppTypography.subheadline)
                .foregroundStyle(MainWindowPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 18)
    }

    private var issueTypePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Issue Type")
                .font(AppTypography.bodyMedium)

            Picker("Issue Type", selection: $appState.issueReportType) {
                ForEach(IssueReportType.allCases) { type in
                    Text(type.title).tag(type)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 260, alignment: .leading)
            .disabled(appState.issueReportStatus.isBusy)
        }
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Title")
                .font(AppTypography.bodyMedium)
            TextField("Briefly summarize the issue", text: $appState.issueReportTitle)
                .textFieldStyle(.roundedBorder)
                .disabled(appState.issueReportStatus.isBusy)

            if let message = appState.issueReportTitleRequirementMessage {
                validationCaption(
                    message,
                    isEmpty: appState.issueReportTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
    }

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What happened?")
                .font(AppTypography.bodyMedium)
            TextEditor(text: $appState.issueReportDescription)
                .font(AppTypography.body)
                .frame(minHeight: 130)
                .scrollContentBackground(.hidden)
                .background(MainWindowPalette.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(MainWindowPalette.cardStroke, lineWidth: 1)
                )
                .disabled(appState.issueReportStatus.isBusy)

            if let message = appState.issueReportDescriptionRequirementMessage {
                validationCaption(
                    message,
                    isEmpty: appState.issueReportDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
    }

    private var contactField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Email")
                .font(AppTypography.bodyMedium)
            TextField("Optional", text: $appState.issueReportContactEmail)
                .textFieldStyle(.roundedBorder)
                .disabled(appState.issueReportStatus.isBusy)

            if let error = appState.issueReportContactEmailValidationError {
                Text(error)
                    .font(AppTypography.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var diagnosticsSection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $appState.issueReportIncludesDiagnostics) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Include diagnostic logs")
                            .font(AppTypography.bodyMedium)
                        Text("Includes sanitized app logs and metadata. Audio, transcripts, clipboard contents, API keys, model files, and full system logs are never included.")
                            .font(AppTypography.subheadline)
                            .foregroundStyle(MainWindowPalette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
                .disabled(appState.issueReportStatus.isBusy)

                CardDivider()

                HStack(spacing: 8) {
                    Button("Review Diagnostics") {
                        Task { await appState.reviewIssueReportDiagnostics() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(appState.issueReportStatus.isBusy)

                    Button("Export Diagnostics") {
                        Task { await appState.exportIssueReportDiagnostics() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(appState.issueReportStatus.isBusy)
                }

                if let message = appState.issueReportDiagnosticsMessage {
                    Text(message)
                        .font(AppTypography.caption)
                        .foregroundStyle(MainWindowPalette.secondaryText)
                }
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch appState.issueReportStatus {
        case .idle:
            EmptyView()
        case .preparing:
            Label("Preparing diagnostics...", systemImage: "archivebox")
                .font(AppTypography.subheadline)
                .foregroundStyle(MainWindowPalette.secondaryText)
        case .sending:
            Label("Sending report...", systemImage: "paperplane")
                .font(AppTypography.subheadline)
                .foregroundStyle(MainWindowPalette.secondaryText)
        case .sent:
            EmptyView()
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(AppTypography.subheadline)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Reset") {
                appState.resetIssueReportDraft()
            }
            .buttonStyle(.bordered)
            .disabled(appState.issueReportStatus.isBusy)

            Spacer()

            Button("Send Report") {
                Task { await appState.submitIssueReport() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!appState.canSubmitIssueReport)
            .help(appState.issueReportSubmitRequirementMessage ?? "Send the issue report")
            .accessibilityHint(appState.issueReportSubmitRequirementMessage ?? "Sends the issue report and selected diagnostics.")
        }
        .padding(24)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(MainWindowPalette.divider)
                .frame(height: 1)
        }
    }

    private func validationCaption(_ message: String, isEmpty: Bool) -> some View {
        Text(message)
            .font(AppTypography.caption)
            .foregroundStyle(isEmpty ? MainWindowPalette.secondaryText : Color.red)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var successView: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 48)

            VStack(spacing: 18) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("Thanks, we caught it.")
                        .font(AppTypography.pageTitle)
                        .multilineTextAlignment(.center)

                    Text("The bug has been reported. You left us a clear trail, and we will take it from here.")
                        .font(AppTypography.body)
                        .foregroundStyle(MainWindowPalette.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button("Close") {
                    appState.resetIssueReportDraft()
                    onClose()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .frame(maxWidth: 380)

            Spacer(minLength: 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
