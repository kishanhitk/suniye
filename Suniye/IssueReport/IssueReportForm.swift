import Foundation
import Observation

/// What a report says about the app, apart from what the user typed.
struct IssueReportContext {
    let app: IssueReportPayload.AppMetadata
    let state: IssueReportPayload.StateMetadata
    let permissions: IssueReportPayload.PermissionMetadata
    let model: IssueReportPayload.ModelMetadata
    let settings: IssueReportPayload.SettingsMetadata
}

/// The "Report a Problem" form: what the user typed, its checks, and sending it.
@MainActor
@Observable
final class IssueReportForm {
    static let minimumTitleLength = 3
    static let minimumDescriptionLength = 10

    var type: IssueReportType = .other
    var title = ""
    var description = ""
    var contactEmail = ""
    var includesDiagnostics = true
    var status: IssueReportSubmissionStatus = .idle
    var diagnosticsMessage: String?
    /// The window closed while a report was on its way; the next opening starts
    /// with an empty form once that report has ended.
    private var resetsWhenReopened = false

    @ObservationIgnored private let uploadService: IssueReportUploadServiceProtocol
    @ObservationIgnored private let diagnosticBundleService: DiagnosticBundleServiceProtocol
    @ObservationIgnored private let context: @MainActor () -> IssueReportContext
    @ObservationIgnored private let nowProvider: () -> Date
    @ObservationIgnored private let fileOpener: (URL) -> Bool
    @ObservationIgnored private let temporaryFileCleanupScheduler: (URL) -> Void
    @ObservationIgnored private let diagnosticsDestinationPicker: @MainActor (String) -> URL?

    init(
        uploadService: IssueReportUploadServiceProtocol,
        diagnosticBundleService: DiagnosticBundleServiceProtocol,
        context: @escaping @MainActor () -> IssueReportContext,
        nowProvider: @escaping () -> Date,
        fileOpener: @escaping (URL) -> Bool,
        temporaryFileCleanupScheduler: @escaping (URL) -> Void,
        diagnosticsDestinationPicker: @escaping @MainActor (String) -> URL?
    ) {
        self.uploadService = uploadService
        self.diagnosticBundleService = diagnosticBundleService
        self.context = context
        self.nowProvider = nowProvider
        self.fileOpener = fileOpener
        self.temporaryFileCleanupScheduler = temporaryFileCleanupScheduler
        self.diagnosticsDestinationPicker = diagnosticsDestinationPicker
    }

    var titleRequirementMessage: String? {
        Self.requirementMessage(for: title, minimumLength: Self.minimumTitleLength, field: "title")
    }

    var descriptionRequirementMessage: String? {
        Self.requirementMessage(for: description, minimumLength: Self.minimumDescriptionLength, field: "description")
    }

    var contactEmailValidationError: String? {
        let email = trimmedContactEmail
        guard !email.isEmpty else {
            return nil
        }
        guard email.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil else {
            return "Enter a valid email address or leave it blank."
        }
        return nil
    }

    var submitRequirementMessage: String? {
        titleRequirementMessage ?? descriptionRequirementMessage ?? contactEmailValidationError
    }

    var canSubmit: Bool {
        !status.isBusy && submitRequirementMessage == nil
    }

    func windowWillOpen() {
        diagnosticsMessage = nil
        guard resetsWhenReopened else {
            return
        }
        switch status {
        case .sent, .failed:
            reset()
        case .idle:
            resetsWhenReopened = false
        case .preparing, .sending:
            break
        }
    }

    func windowDidClose() {
        switch status {
        case .sent:
            reset()
        case .failed where resetsWhenReopened:
            reset()
        case .preparing, .sending:
            resetsWhenReopened = true
        case .idle, .failed:
            resetsWhenReopened = false
        }
    }

    func reset() {
        type = .other
        title = ""
        description = ""
        contactEmail = ""
        includesDiagnostics = true
        status = .idle
        diagnosticsMessage = nil
        resetsWhenReopened = false
    }

    func submit() async {
        guard !status.isBusy else {
            return
        }
        if let validationError {
            status = .failed(validationError)
            return
        }

        let payload = makePayload(includeDiagnostics: includesDiagnostics)
        var diagnosticsURL: URL?
        do {
            diagnosticsMessage = nil
            if includesDiagnostics {
                status = .preparing
                diagnosticsURL = try await makeDiagnosticBundle(payload: payload)
            }
            status = .sending
            let response = try await uploadService.submit(payload: payload, diagnosticsURL: diagnosticsURL)
            status = .sent
            AppLogger.shared.log(.info, "issue report sent id=\(response.issueIdentifier) report_id=\(response.reportId)")
        } catch {
            status = .failed(Self.message(for: error))
            AppLogger.shared.log(.error, "issue report failed: \(error.localizedDescription)")
        }

        if let diagnosticsURL {
            try? FileManager.default.removeItem(at: diagnosticsURL)
        }
    }

    func reviewDiagnostics() async {
        do {
            status = .preparing
            diagnosticsMessage = nil
            let payload = makePayload(
                titleIfEmpty: "Diagnostic preview",
                descriptionIfEmpty: "Diagnostic preview for manual support.",
                includeDiagnostics: true
            )
            let diagnosticsURL = try await makeDiagnosticBundle(payload: payload)
            if fileOpener(diagnosticsURL) {
                temporaryFileCleanupScheduler(diagnosticsURL)
                status = .idle
                diagnosticsMessage = "Diagnostics opened for review."
            } else {
                try? FileManager.default.removeItem(at: diagnosticsURL)
                status = .failed("Could not open diagnostics.")
            }
        } catch {
            status = .failed(Self.message(for: error))
        }
    }

    func exportDiagnostics() async {
        do {
            status = .preparing
            diagnosticsMessage = nil
            let payload = makePayload(
                titleIfEmpty: "Diagnostic export",
                descriptionIfEmpty: "Diagnostic export for manual support.",
                includeDiagnostics: true
            )
            let diagnosticsURL = try await makeDiagnosticBundle(payload: payload)
            defer {
                try? FileManager.default.removeItem(at: diagnosticsURL)
            }

            guard let destinationURL = diagnosticsDestinationPicker(diagnosticsURL.lastPathComponent) else {
                status = .idle
                return
            }

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: diagnosticsURL, to: destinationURL)
            status = .idle
            diagnosticsMessage = "Diagnostics exported."
        } catch {
            status = .failed(Self.message(for: error))
        }
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedDescription: String { description.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedContactEmail: String { contactEmail.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var validationError: String? {
        if trimmedTitle.count < Self.minimumTitleLength {
            return "Add a short title for the issue."
        }
        if trimmedDescription.count < Self.minimumDescriptionLength {
            return "Describe what happened in a little more detail."
        }
        return contactEmailValidationError
    }

    private func makePayload(
        titleIfEmpty: String? = nil,
        descriptionIfEmpty: String? = nil,
        includeDiagnostics: Bool
    ) -> IssueReportPayload {
        let context = context()
        let email = trimmedContactEmail
        return IssueReportPayload(
            schemaVersion: 1,
            reportId: IssueReportPayload.makeReportId(),
            issueType: type,
            title: trimmedTitle.isEmpty ? titleIfEmpty ?? "" : trimmedTitle,
            description: trimmedDescription.isEmpty ? descriptionIfEmpty ?? "" : trimmedDescription,
            contactEmail: email.isEmpty ? nil : email,
            includeDiagnostics: includeDiagnostics,
            app: context.app,
            state: context.state,
            permissions: context.permissions,
            model: context.model,
            settings: context.settings
        )
    }

    private func makeDiagnosticBundle(payload: IssueReportPayload) async throws -> URL {
        let rotatedLogFileURL = AppLogger.shared.rotatedLogFileURL
        return try await diagnosticBundleService.makeBundle(
            request: DiagnosticBundleRequest(
                payload: payload,
                createdAt: nowProvider(),
                logFileURL: AppLogger.shared.logFileURL,
                rotatedLogFileURL: FileManager.default.fileExists(atPath: rotatedLogFileURL.path) ? rotatedLogFileURL : nil
            )
        )
    }

    private static func requirementMessage(for text: String, minimumLength: Int, field: String) -> String? {
        let count = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        guard count < minimumLength else {
            return nil
        }
        let remaining = minimumLength - count
        return remaining == 1
            ? "Add 1 more character to the \(field)."
            : "Add \(remaining) more characters to the \(field)."
    }

    private static func message(for error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription, !localized.isEmpty {
            return localized
        }
        return error.localizedDescription
    }
}
