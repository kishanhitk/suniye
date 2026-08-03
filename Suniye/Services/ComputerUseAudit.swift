import Foundation

enum ComputerUseAuditKind: String, Codable, Equatable, Sendable {
    case approvalRequested
    case approvalResolved
    case policyBlocked
}

enum ComputerUseAuditOutcome: String, Codable, Equatable, Sendable {
    case allowed
    case accepted
    case denied
    case forbidden
}

struct ComputerUseAuditRecord: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let timestamp: Date
    let kind: ComputerUseAuditKind
    let outcome: ComputerUseAuditOutcome
    let requestID: UUID
    let sessionID: UUID
    let applicationBundleIdentifier: String
    let risk: ComputerUseActionRisk
    let actionSummary: String
    let approvalScope: ComputerUseApprovalScope?
}

protocol ComputerUseAuditRecording: AnyObject {
    func record(_ record: ComputerUseAuditRecord)
}

final class AppLoggerComputerUseAuditRecorder: ComputerUseAuditRecording {
    func record(_ record: ComputerUseAuditRecord) {
        let scope = record.approvalScope?.rawValue ?? "none"
        AppLogger.shared.log(
            .info,
            "computer_use_audit kind=\(record.kind.rawValue) outcome=\(record.outcome.rawValue) "
                + "request=\(record.requestID.uuidString) session=\(record.sessionID.uuidString) "
                + "app=\(record.applicationBundleIdentifier) risk=\(record.risk.rawValue) "
                + "action=\(record.actionSummary) scope=\(scope)"
        )
    }
}

final class MemoryComputerUseAuditRecorder: ComputerUseAuditRecording {
    private let lock = NSLock()
    private var storedRecords: [ComputerUseAuditRecord] = []

    var records: [ComputerUseAuditRecord] {
        lock.lock()
        defer { lock.unlock() }
        return storedRecords
    }

    func record(_ record: ComputerUseAuditRecord) {
        lock.lock()
        storedRecords.append(record)
        lock.unlock()
    }
}
