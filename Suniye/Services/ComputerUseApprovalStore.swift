import Foundation

struct ComputerUseApprovalRecord: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let applicationBundleIdentifier: String
    let risk: ComputerUseActionRisk
    let scope: ComputerUseApprovalScope
    let expiresAt: Date?
}

protocol ComputerUseApprovalStoring: AnyObject {
    func rememberedScope(
        applicationBundleIdentifier: String,
        risk: ComputerUseActionRisk,
        sessionID: UUID,
        now: Date
    ) -> ComputerUseApprovalScope?

    func save(
        scope: ComputerUseApprovalScope,
        applicationBundleIdentifier: String,
        risk: ComputerUseActionRisk,
        sessionID: UUID,
        expiresAt: Date?
    )

    func listAlwaysApprovals(now: Date) -> [ComputerUseApprovalRecord]

    func revoke(
        applicationBundleIdentifier: String?,
        risk: ComputerUseActionRisk?
    )

    func endSession(_ sessionID: UUID)
    func revokeAll()
}

final class ComputerUseApprovalStore: ComputerUseApprovalStoring {
    private struct SessionApprovalKey: Hashable {
        let applicationBundleIdentifier: String
        let risk: ComputerUseActionRisk
        let sessionID: UUID
    }

    private let userDefaults: UserDefaults
    private let storageKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let lock = NSLock()
    private var sessionApprovals: Set<SessionApprovalKey> = []

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "dev.suniye.computer-use.approvals"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
    }

    func rememberedScope(
        applicationBundleIdentifier: String,
        risk: ComputerUseActionRisk,
        sessionID: UUID,
        now: Date
    ) -> ComputerUseApprovalScope? {
        let bundleIdentifier = Self.normalize(applicationBundleIdentifier)
        guard !bundleIdentifier.isEmpty else {
            return nil
        }

        return withLock {
            let sessionKey = SessionApprovalKey(
                applicationBundleIdentifier: bundleIdentifier,
                risk: risk,
                sessionID: sessionID
            )
            if sessionApprovals.contains(sessionKey) {
                return .session
            }

            let records = validAlwaysApprovals(now: now)
            return records.contains {
                $0.applicationBundleIdentifier == bundleIdentifier && $0.risk == risk
            } ? .always : nil
        }
    }

    func save(
        scope: ComputerUseApprovalScope,
        applicationBundleIdentifier: String,
        risk: ComputerUseActionRisk,
        sessionID: UUID,
        expiresAt: Date?
    ) {
        let bundleIdentifier = Self.normalize(applicationBundleIdentifier)
        guard !bundleIdentifier.isEmpty else {
            return
        }

        withLock {
            switch scope {
            case .once:
                return
            case .session:
                sessionApprovals.insert(
                    SessionApprovalKey(
                        applicationBundleIdentifier: bundleIdentifier,
                        risk: risk,
                        sessionID: sessionID
                    )
                )
            case .always:
                var records = validAlwaysApprovals(now: Date())
                sessionApprovals = sessionApprovals.filter {
                    $0.applicationBundleIdentifier != bundleIdentifier || $0.risk != risk
                }
                records.removeAll {
                    $0.applicationBundleIdentifier == bundleIdentifier && $0.risk == risk
                }
                records.append(
                    ComputerUseApprovalRecord(
                        id: UUID(),
                        applicationBundleIdentifier: bundleIdentifier,
                        risk: risk,
                        scope: .always,
                        expiresAt: expiresAt
                    )
                )
                persistAlwaysApprovals(records)
            }
        }
    }

    func listAlwaysApprovals(now: Date = Date()) -> [ComputerUseApprovalRecord] {
        withLock {
            validAlwaysApprovals(now: now)
        }
    }

    func revoke(
        applicationBundleIdentifier: String?,
        risk: ComputerUseActionRisk?
    ) {
        let normalizedBundleIdentifier = applicationBundleIdentifier.map(Self.normalize)
        withLock {
            sessionApprovals = sessionApprovals.filter { key in
                !matches(
                    applicationBundleIdentifier: normalizedBundleIdentifier,
                    risk: risk,
                    key: key
                )
            }
            let records = loadAlwaysApprovals().filter { record in
                !matches(
                    applicationBundleIdentifier: normalizedBundleIdentifier,
                    risk: risk,
                    record: record
                )
            }
            persistAlwaysApprovals(records)
        }
    }

    func endSession(_ sessionID: UUID) {
        withLock {
            sessionApprovals = sessionApprovals.filter { $0.sessionID != sessionID }
        }
    }

    func revokeAll() {
        withLock {
            sessionApprovals.removeAll()
            userDefaults.removeObject(forKey: storageKey)
        }
    }

    private func validAlwaysApprovals(now: Date) -> [ComputerUseApprovalRecord] {
        let records = loadAlwaysApprovals()
        let valid = records.filter { record in
            guard let expiresAt = record.expiresAt else {
                return true
            }
            return expiresAt > now
        }
        if valid.count != records.count {
            persistAlwaysApprovals(valid)
        }
        return valid
    }

    private func loadAlwaysApprovals() -> [ComputerUseApprovalRecord] {
        guard let data = userDefaults.data(forKey: storageKey) else {
            return []
        }
        return (try? decoder.decode([ComputerUseApprovalRecord].self, from: data)) ?? []
    }

    private func persistAlwaysApprovals(_ records: [ComputerUseApprovalRecord]) {
        guard !records.isEmpty else {
            userDefaults.removeObject(forKey: storageKey)
            return
        }
        guard let data = try? encoder.encode(records) else {
            return
        }
        userDefaults.set(data, forKey: storageKey)
    }

    private func matches(
        applicationBundleIdentifier: String?,
        risk: ComputerUseActionRisk?,
        key: SessionApprovalKey
    ) -> Bool {
        (applicationBundleIdentifier == nil || applicationBundleIdentifier == key.applicationBundleIdentifier)
            && (risk == nil || risk == key.risk)
    }

    private func matches(
        applicationBundleIdentifier: String?,
        risk: ComputerUseActionRisk?,
        record: ComputerUseApprovalRecord
    ) -> Bool {
        (applicationBundleIdentifier == nil || applicationBundleIdentifier == record.applicationBundleIdentifier)
            && (risk == nil || risk == record.risk)
    }

    private static func normalize(_ identifier: String) -> String {
        identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func withLock<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}
