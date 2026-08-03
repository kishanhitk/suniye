import Foundation

enum ComputerUsePolicyDecision: Equatable, Sendable {
    case allowed(approvalScopes: Set<ComputerUseApprovalScope>)
    case denied(reason: String)
    case forbidden(reason: String)
}

struct ComputerUsePolicyConfiguration: Codable, Equatable, Sendable {
    let deniedBundleIdentifiers: Set<String>
    let forbiddenBundleIdentifiers: Set<String>
    let persistentApprovalRisks: Set<ComputerUseActionRisk>

    init(
        deniedBundleIdentifiers: Set<String> = [],
        forbiddenBundleIdentifiers: Set<String> = [],
        persistentApprovalRisks: Set<ComputerUseActionRisk> = []
    ) {
        self.deniedBundleIdentifiers = Self.normalized(deniedBundleIdentifiers)
        self.forbiddenBundleIdentifiers = Self.normalized(forbiddenBundleIdentifiers)
        self.persistentApprovalRisks = persistentApprovalRisks
    }

    private static func normalized(_ identifiers: Set<String>) -> Set<String> {
        Set(identifiers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
            .filter { !$0.isEmpty }
    }
}

protocol ComputerUsePolicyChecking {
    func evaluate(
        application: ComputerUseApplication,
        action: ComputerUseAction
    ) -> ComputerUsePolicyDecision
}

struct ComputerUsePolicyService: ComputerUsePolicyChecking {
    let configuration: ComputerUsePolicyConfiguration

    init(configuration: ComputerUsePolicyConfiguration = ComputerUsePolicyConfiguration()) {
        self.configuration = configuration
    }

    func evaluate(
        application: ComputerUseApplication,
        action: ComputerUseAction
    ) -> ComputerUsePolicyDecision {
        let bundleIdentifier = application.bundleIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !bundleIdentifier.isEmpty else {
            return .forbidden(reason: "The target application has no bundle identifier.")
        }
        if configuration.forbiddenBundleIdentifiers.contains(bundleIdentifier) {
            return .forbidden(
                reason: "Computer Use is not allowed to use \(application.displayName) for safety reasons."
            )
        }
        if configuration.deniedBundleIdentifiers.contains(bundleIdentifier) {
            return .denied(
                reason: "Computer Use is blocked from using \(application.displayName) by policy."
            )
        }

        var scopes: Set<ComputerUseApprovalScope> = [.once]
        if action.risk != .textEntry,
           configuration.persistentApprovalRisks.contains(action.risk) {
            scopes.formUnion([.session, .always])
        }
        return .allowed(approvalScopes: scopes)
    }
}

enum ComputerUsePolicyError: LocalizedError, Equatable, Sendable {
    case applicationDenied(String)
    case applicationForbidden(String)

    var errorDescription: String? {
        switch self {
        case let .applicationDenied(reason), let .applicationForbidden(reason):
            return reason
        }
    }
}

final class ComputerUseApprovalPolicyService {
    private let policy: ComputerUsePolicyChecking
    private let store: ComputerUseApprovalStoring
    private let auditRecorder: ComputerUseAuditRecording
    private let dateProvider: () -> Date

    init(
        policy: ComputerUsePolicyChecking = ComputerUsePolicyService(),
        store: ComputerUseApprovalStoring = ComputerUseApprovalStore(),
        auditRecorder: ComputerUseAuditRecording = AppLoggerComputerUseAuditRecorder(),
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.policy = policy
        self.store = store
        self.auditRecorder = auditRecorder
        self.dateProvider = dateProvider
    }

    func authorize(_ request: ComputerUseApprovalRequest) throws -> ComputerUseApprovalGrant {
        let prepared = try preparedRequest(request)
        let scope = rememberedScope(for: prepared) ?? .once
        store.save(
            scope: scope,
            applicationBundleIdentifier: prepared.target.application.bundleIdentifier,
            risk: prepared.risk,
            sessionID: prepared.sessionID,
            expiresAt: nil
        )
        let grant = ComputerUseApprovalGrant(
            requestID: prepared.id,
            scope: scope,
            applicationID: prepared.target.application.id,
            windowID: prepared.target.window.id,
            observationGeneration: prepared.observationGeneration,
            action: prepared.action,
            sessionID: prepared.sessionID
        )
        record(
            kind: .approvalResolved,
            outcome: .accepted,
            request: prepared,
            scope: scope
        )
        return grant
    }

    private func rememberedScope(
        for prepared: ComputerUseApprovalRequest
    ) -> ComputerUseApprovalScope? {
        guard let scope = store.rememberedScope(
            applicationBundleIdentifier: prepared.target.application.bundleIdentifier,
            risk: prepared.risk,
            sessionID: prepared.sessionID,
            now: dateProvider()
        ) else {
            return nil
        }
        guard prepared.allowedScopes.contains(scope) else {
            store.revoke(
                applicationBundleIdentifier: prepared.target.application.bundleIdentifier,
                risk: prepared.risk
            )
            return nil
        }
        return scope
    }

    private func preparedRequest(
        _ request: ComputerUseApprovalRequest
    ) throws -> ComputerUseApprovalRequest {
        switch policy.evaluate(application: request.target.application, action: request.action) {
        case let .allowed(scopes):
            record(
                kind: .approvalRequested,
                outcome: .allowed,
                request: request,
                scope: nil
            )
            return ComputerUseApprovalRequest(
                id: request.id,
                action: request.action,
                target: request.target,
                risk: request.risk,
                sessionID: request.sessionID,
                observationGeneration: request.observationGeneration,
                allowedScopes: scopes
            )
        case let .denied(reason):
            record(
                kind: .policyBlocked,
                outcome: .denied,
                request: request,
                scope: nil
            )
            throw ComputerUsePolicyError.applicationDenied(reason)
        case let .forbidden(reason):
            record(
                kind: .policyBlocked,
                outcome: .forbidden,
                request: request,
                scope: nil
            )
            throw ComputerUsePolicyError.applicationForbidden(reason)
        }
    }

    private func record(
        kind: ComputerUseAuditKind,
        outcome: ComputerUseAuditOutcome,
        request: ComputerUseApprovalRequest,
        scope: ComputerUseApprovalScope?
    ) {
        auditRecorder.record(
            ComputerUseAuditRecord(
                id: UUID(),
                timestamp: dateProvider(),
                kind: kind,
                outcome: outcome,
                requestID: request.id,
                sessionID: request.sessionID,
                applicationBundleIdentifier: request.target.application.bundleIdentifier,
                risk: request.risk,
                actionSummary: request.action.summary,
                approvalScope: scope
            )
        )
    }
}
