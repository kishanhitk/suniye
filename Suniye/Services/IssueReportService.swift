import AppKit
import Foundation

enum IssueReportType: String, CaseIterable, Codable, Identifiable, Sendable {
    case dictation
    case hotkey
    case transcription
    case textInsertion
    case magicFormat
    case modelDownload
    case permissions
    case update
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dictation: return "Dictation"
        case .hotkey: return "Hotkey"
        case .transcription: return "Transcription"
        case .textInsertion: return "Text Insertion"
        case .magicFormat: return "Magic Format"
        case .modelDownload: return "Model Download"
        case .permissions: return "Permissions"
        case .update: return "Updates"
        case .other: return "Other"
        }
    }
}

enum IssueReportSubmissionStatus: Equatable, Sendable {
    case idle
    case preparing
    case sending
    case sent
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .preparing, .sending:
            return true
        case .idle, .sent, .failed:
            return false
        }
    }
}

struct IssueReportPayload: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let reportId: String
    let issueType: IssueReportType
    let title: String
    let description: String
    let contactEmail: String?
    let includeDiagnostics: Bool
    let app: AppMetadata
    let state: StateMetadata
    let permissions: PermissionMetadata
    let model: ModelMetadata
    let settings: SettingsMetadata

    struct AppMetadata: Codable, Equatable, Sendable {
        let version: String
        let build: String?
        let macOSVersion: String
        let architecture: String
    }

    struct StateMetadata: Codable, Equatable, Sendable {
        let phase: String
        let lastError: String?
        let updateStatus: String?
    }

    struct PermissionMetadata: Codable, Equatable, Sendable {
        let microphone: Bool
        let accessibility: Bool
    }

    struct ModelMetadata: Codable, Equatable, Sendable {
        let selectedModelId: String
        let selectedModelName: String
        let selectedModelInstalled: Bool
        let installedModelIds: [String]
    }

    struct SettingsMetadata: Codable, Equatable, Sendable {
        let autoSubmitEnabled: Bool
        let echoCancellationEnabled: Bool
        let soundFeedbackEnabled: Bool
        let hideFloatingIndicatorWhenIdle: Bool
        let llmEnabled: Bool
        let llmHasAPIKey: Bool
    }
}

struct DiagnosticBundleRequest: Equatable, Sendable {
    let payload: IssueReportPayload
    let createdAt: Date
    let logFileURL: URL
    let rotatedLogFileURL: URL?
}

protocol DiagnosticBundleServiceProtocol {
    func makeBundle(request: DiagnosticBundleRequest) async throws -> URL
}

protocol IssueReportUploadServiceProtocol {
    func submit(payload: IssueReportPayload, diagnosticsURL: URL?) async throws -> IssueReportSubmissionResponse
}

struct IssueReportSubmissionResponse: Decodable, Equatable, Sendable {
    let reportId: String
    let issueId: String
    let issueIdentifier: String
    let issueUrl: URL?
}

enum IssueReportError: LocalizedError, Equatable, Sendable {
    case missingEndpoint
    case invalidResponse
    case serverMessage(String)
    case httpStatus(Int)
    case fileIO(String)
    case zipFailed(String)
    case invalidInput(String)

    var errorDescription: String? {
        switch self {
        case .missingEndpoint:
            return "Issue reporting endpoint is not configured."
        case .invalidResponse:
            return "Issue reporting server returned an invalid response."
        case let .serverMessage(message):
            return message
        case let .httpStatus(status):
            return "Issue reporting server returned HTTP \(status)."
        case let .fileIO(message):
            return message
        case let .zipFailed(message):
            return "Could not create diagnostics archive: \(message)"
        case let .invalidInput(message):
            return message
        }
    }
}

struct DiagnosticRedactor: Sendable {
    private let homeDirectory: String

    init(homeDirectory: String = NSHomeDirectory()) {
        self.homeDirectory = homeDirectory
    }

    func redact(_ input: String) -> String {
        var output = input
        if !homeDirectory.isEmpty {
            output = output.replacingOccurrences(of: homeDirectory, with: "~")
        }

        let rules: [(String, String)] = [
            (#"(?i)\bBearer\s+[A-Za-z0-9._~+/\-]+=*"#, "Bearer [REDACTED]"),
            (#"(?i)([?&](?:api[_-]?key|token|key|secret|access_token)=)[^\s&]+"#, "$1[REDACTED]"),
            (#"(?i)\b(api[_-]?key|token|secret|authorization|x-api-key)(\s*[:=]\s*)[^\s,;]+"#, "$1$2[REDACTED]"),
            (#"(?i)\b(sk-[A-Za-z0-9_\-]{12,}|gh[opsu]_[A-Za-z0-9_]{12,}|or-[A-Za-z0-9_\-]{12,})\b"#, "[REDACTED_TOKEN]"),
            (#"(?i)(\"(?:transcript|clipboard|audio|device[_-]?(?:uid|name))\"\s*:\s*)(\"(?:\\.|[^\"])*\"|[^,}\n]+)"#, "$1\"[REDACTED]\""),
            (#"(?i)\b(transcript|clipboard|audio)(\s*[:=]\s*)[^\n]+"#, "$1$2[REDACTED]"),
            (#"(?i)\b(device[_-]?(?:uid|name))(\s*[:=]\s*)[^\n]+"#, "$1$2[REDACTED]"),
            (#"(?i)[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#, "[REDACTED_EMAIL]"),
        ]

        for (pattern, replacement) in rules {
            output = output.replacingMatches(pattern: pattern, with: replacement)
        }
        return output
    }
}

final class DiagnosticBundleService: DiagnosticBundleServiceProtocol {
    private let fileManager: FileManager
    private let redactor: DiagnosticRedactor
    private let encoder: JSONEncoder

    init(fileManager: FileManager = .default, redactor: DiagnosticRedactor = DiagnosticRedactor()) {
        self.fileManager = fileManager
        self.redactor = redactor
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
    }

    func makeBundle(request: DiagnosticBundleRequest) async throws -> URL {
        try await Task.detached(priority: .utility) { [fileManager, redactor, encoder] in
            let safeReportId = Self.safeFilenameComponent(request.payload.reportId)
            let stagingDirectory = fileManager.temporaryDirectory
                .appendingPathComponent("suniye-diagnostics-\(safeReportId)-\(UUID().uuidString)", isDirectory: true)
            let archiveURL = fileManager.temporaryDirectory
                .appendingPathComponent("suniye-diagnostics-\(safeReportId)-\(UUID().uuidString).zip")

            try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
            defer {
                try? fileManager.removeItem(at: stagingDirectory)
            }

            let manifest = DiagnosticManifest(
                reportId: request.payload.reportId,
                createdAt: request.createdAt,
                payload: request.payload,
                includedFiles: [
                    "manifest.json",
                    "redaction-report.json",
                    "app.log",
                    request.rotatedLogFileURL == nil ? nil : "app.log.1",
                ].compactMap { $0 },
                privacyNotice: "Diagnostics exclude audio, transcripts, clipboard contents, API keys, model files, and full system logs."
            )

            try Self.writeJSON(manifest, to: stagingDirectory.appendingPathComponent("manifest.json"), encoder: encoder)
            try Self.writeJSON(
                RedactionReport(),
                to: stagingDirectory.appendingPathComponent("redaction-report.json"),
                encoder: encoder
            )
            try Self.writeRedactedLog(
                from: request.logFileURL,
                to: stagingDirectory.appendingPathComponent("app.log"),
                redactor: redactor,
                fileManager: fileManager
            )
            if let rotatedLogFileURL = request.rotatedLogFileURL,
               fileManager.fileExists(atPath: rotatedLogFileURL.path) {
                try Self.writeRedactedLog(
                    from: rotatedLogFileURL,
                    to: stagingDirectory.appendingPathComponent("app.log.1"),
                    redactor: redactor,
                    fileManager: fileManager
                )
            }

            try Self.zipDirectory(stagingDirectory, to: archiveURL)
            return archiveURL
        }.value
    }

    private static func writeJSON<T: Encodable>(_ value: T, to url: URL, encoder: JSONEncoder) throws {
        do {
            let data = try encoder.encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            throw IssueReportError.fileIO(error.localizedDescription)
        }
    }

    private static func writeRedactedLog(
        from sourceURL: URL,
        to destinationURL: URL,
        redactor: DiagnosticRedactor,
        fileManager: FileManager
    ) throws {
        let text: String
        if fileManager.fileExists(atPath: sourceURL.path) {
            text = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""
        } else {
            text = ""
        }
        do {
            try redactor.redact(text).write(to: destinationURL, atomically: true, encoding: .utf8)
        } catch {
            throw IssueReportError.fileIO(error.localizedDescription)
        }
    }

    private static func zipDirectory(_ sourceDirectory: URL, to destinationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-qry", destinationURL.path, "."]
        process.currentDirectoryURL = sourceDirectory

        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw IssueReportError.zipFailed(error.localizedDescription)
        }

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorText = String(data: errorData, encoding: .utf8) ?? "zip exited with status \(process.terminationStatus)"
            throw IssueReportError.zipFailed(errorText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func safeFilenameComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let safe = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return safe.isEmpty ? "report" : safe
    }
}

final class IssueReportUploadService: IssueReportUploadServiceProtocol {
    private let session: URLSession
    private let endpointURL: URL?
    private let decoder = JSONDecoder()

    init(
        session: URLSession = .shared,
        bundle: Bundle = .main,
        endpointURL: URL? = nil
    ) {
        self.session = session
        self.endpointURL = endpointURL ?? Self.endpointURL(from: bundle)
    }

    func submit(payload: IssueReportPayload, diagnosticsURL: URL?) async throws -> IssueReportSubmissionResponse {
        guard let endpointURL else {
            throw IssueReportError.missingEndpoint
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        let body = try await Self.makeMultipartBody(
            payload: payload,
            diagnosticsURL: diagnosticsURL,
            boundary: boundary
        )

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Suniye/IssueReporter", forHTTPHeaderField: "User-Agent")
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw IssueReportError.serverMessage("Could not reach issue reporting server.")
        }

        guard let http = response as? HTTPURLResponse else {
            throw IssueReportError.invalidResponse
        }

        let envelope = try? decoder.decode(IssueReportEnvelope.self, from: data)
        if !(200 ..< 300).contains(http.statusCode) {
            if let message = envelope?.error?.message {
                throw IssueReportError.serverMessage(message)
            }
            throw IssueReportError.httpStatus(http.statusCode)
        }

        guard let envelope, envelope.success == true,
              let reportId = envelope.reportId,
              let issueId = envelope.issueId,
              let issueIdentifier = envelope.issueIdentifier
        else {
            throw IssueReportError.invalidResponse
        }

        return IssueReportSubmissionResponse(
            reportId: reportId,
            issueId: issueId,
            issueIdentifier: issueIdentifier,
            issueUrl: envelope.issueUrl
        )
    }

    private static func makeMultipartBody(
        payload: IssueReportPayload,
        diagnosticsURL: URL?,
        boundary: String
    ) async throws -> Data {
        try await Task.detached(priority: .utility) {
            var body = Data()
            let payloadData: Data
            do {
                payloadData = try JSONEncoder().encode(payload)
            } catch {
                throw IssueReportError.invalidInput(error.localizedDescription)
            }

            body.appendMultipartField(
                name: "payload",
                valueData: payloadData,
                contentType: "application/json",
                boundary: boundary
            )

            if let diagnosticsURL {
                do {
                    let diagnosticsData = try Data(contentsOf: diagnosticsURL)
                    body.appendMultipartFile(
                        name: "diagnostics",
                        filename: diagnosticsURL.lastPathComponent,
                        data: diagnosticsData,
                        contentType: "application/zip",
                        boundary: boundary
                    )
                } catch {
                    throw IssueReportError.fileIO(error.localizedDescription)
                }
            }

            body.appendString("--\(boundary)--\r\n")
            return body
        }.value
    }
    private static func endpointURL(from bundle: Bundle) -> URL? {
        guard
            let raw = bundle.object(forInfoDictionaryKey: "SuniyeIssueReportEndpointURL") as? String,
            !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        return URL(string: raw)
    }
}

private struct DiagnosticManifest: Encodable, Equatable {
    let reportId: String
    let createdAt: Date
    let payload: IssueReportPayload
    let includedFiles: [String]
    let privacyNotice: String
}

private struct RedactionReport: Encodable, Equatable {
    let redacted: Bool = true
    let rules: [String] = [
        "home paths",
        "email addresses",
        "authorization headers",
        "API keys and token assignments",
        "known API token formats",
        "transcript, clipboard, and audio payload lines",
    ]
}

private struct IssueReportEnvelope: Decodable {
    let success: Bool
    let reportId: String?
    let issueId: String?
    let issueIdentifier: String?
    let issueUrl: URL?
    let error: IssueReportServerError?
}

private struct IssueReportServerError: Decodable {
    let code: String
    let message: String
}

private extension Data {
    mutating func appendMultipartField(name: String, valueData: Data, contentType: String, boundary: String) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n")
        appendString("Content-Type: \(contentType)\r\n\r\n")
        append(valueData)
        appendString("\r\n")
    }

    mutating func appendMultipartFile(name: String, filename: String, data: Data, contentType: String, boundary: String) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        appendString("Content-Type: \(contentType)\r\n\r\n")
        append(data)
        appendString("\r\n")
    }

    mutating func appendString(_ string: String) {
        append(Data(string.utf8))
    }
}

private extension String {
    func replacingMatches(pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return self
        }
        let range = NSRange(startIndex ..< endIndex, in: self)
        return regex.stringByReplacingMatches(in: self, range: range, withTemplate: replacement)
    }
}

extension ProcessInfo {
    var suniyeOperatingSystemVersionString: String {
        let version = operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    static var suniyeArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}

extension IssueReportPayload {
    static func makeReportId() -> String {
        "suniye-\(UUID().uuidString.lowercased())"
    }
}
