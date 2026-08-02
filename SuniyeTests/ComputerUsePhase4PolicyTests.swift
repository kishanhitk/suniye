import Foundation
import XCTest
@testable import Suniye

final class ComputerUsePhase4PolicyTests: XCTestCase {
    func testPolicyDistinguishesAllowedDeniedAndForbiddenApplications() {
        let observation = makePhase3Observation(generation: 4)
        let policy = ComputerUsePolicyService(
            configuration: ComputerUsePolicyConfiguration(
                deniedBundleIdentifiers: ["com.example.denied"],
                forbiddenBundleIdentifiers: ["com.example.forbidden"],
                persistentApprovalRisks: [.scroll]
            )
        )

        XCTAssertEqual(
            policy.evaluate(
                application: observation.target.application,
                action: .scroll(horizontal: 0, vertical: -10)
            ),
            .allowed(approvalScopes: [.once, .session, .always])
        )
        XCTAssertEqual(
            policy.evaluate(
                application: application(bundleIdentifier: " COM.EXAMPLE.DENIED "),
                action: .click(point: ComputerUsePoint(x: 10, y: 10))
            ),
            .denied(reason: "Computer Use is blocked from using Target App by policy.")
        )
        XCTAssertEqual(
            policy.evaluate(
                application: application(bundleIdentifier: "com.example.forbidden"),
                action: .click(point: ComputerUsePoint(x: 10, y: 10))
            ),
            .forbidden(reason: "Computer Use is not allowed to use Target App for safety reasons.")
        )
    }

    func testPolicyOnlyAllowsPersistentScopesForConfiguredRisks() {
        let application = application(bundleIdentifier: "com.example.target")
        let policy = ComputerUsePolicyService(
            configuration: ComputerUsePolicyConfiguration(persistentApprovalRisks: [.scroll, .textEntry])
        )

        XCTAssertEqual(
            policy.evaluate(
                application: application,
                action: .typeText("secret")
            ),
            .allowed(approvalScopes: [.once])
        )
        XCTAssertEqual(
            policy.evaluate(
                application: application,
                action: .scroll(horizontal: 0, vertical: -1)
            ),
            .allowed(approvalScopes: [.once, .session, .always])
        )
    }

    func testApprovalStoreSeparatesSessionAndAlwaysApprovals() {
        let defaults = isolatedDefaults()
        let store = ComputerUseApprovalStore(
            userDefaults: defaults,
            storageKey: "phase4.approvals"
        )
        let firstSession = UUID()
        let secondSession = UUID()

        store.save(
            scope: .session,
            applicationBundleIdentifier: "COM.EXAMPLE.TARGET",
            risk: .scroll,
            sessionID: firstSession,
            expiresAt: nil
        )
        XCTAssertEqual(
            store.rememberedScope(
                applicationBundleIdentifier: "com.example.target",
                risk: .scroll,
                sessionID: firstSession,
                now: Date()
            ),
            .session
        )
        XCTAssertNil(
            store.rememberedScope(
                applicationBundleIdentifier: "com.example.target",
                risk: .scroll,
                sessionID: secondSession,
                now: Date()
            )
        )

        store.save(
            scope: .always,
            applicationBundleIdentifier: "com.example.target",
            risk: .scroll,
            sessionID: firstSession,
            expiresAt: nil
        )
        let reloadedStore = ComputerUseApprovalStore(
            userDefaults: defaults,
            storageKey: "phase4.approvals"
        )
        XCTAssertEqual(
            reloadedStore.rememberedScope(
                applicationBundleIdentifier: "com.example.target",
                risk: .scroll,
                sessionID: secondSession,
                now: Date()
            ),
            .always
        )

        store.endSession(firstSession)
        XCTAssertEqual(
            store.rememberedScope(
                applicationBundleIdentifier: "com.example.target",
                risk: .scroll,
                sessionID: firstSession,
                now: Date()
            ),
            .always
        )
        XCTAssertEqual(store.listAlwaysApprovals(now: Date()).count, 1)
        store.revoke(applicationBundleIdentifier: "com.example.target", risk: .scroll)
        XCTAssertTrue(store.listAlwaysApprovals(now: Date()).isEmpty)
    }

    func testExpiredAlwaysApprovalIsRemovedAndNeverReturned() {
        let defaults = isolatedDefaults()
        let store = ComputerUseApprovalStore(
            userDefaults: defaults,
            storageKey: "phase4.approvals"
        )
        let now = Date(timeIntervalSince1970: 10_000)
        store.save(
            scope: .always,
            applicationBundleIdentifier: "com.example.target",
            risk: .click,
            sessionID: UUID(),
            expiresAt: now.addingTimeInterval(-1)
        )

        XCTAssertNil(
            store.rememberedScope(
                applicationBundleIdentifier: "com.example.target",
                risk: .click,
                sessionID: UUID(),
                now: now
            )
        )
        XCTAssertTrue(store.listAlwaysApprovals(now: now).isEmpty)
    }

    func testApprovalPolicyReevaluatesPolicyAndCreatesExactGrant() throws {
        let observation = makePhase3Observation(generation: 9)
        let sessionID = UUID()
        let request = ComputerUseApprovalRequest(
            id: UUID(),
            action: .scroll(horizontal: 0, vertical: -10),
            target: observation.target,
            risk: .scroll,
            reason: "Scroll the target.",
            sessionID: sessionID,
            observationGeneration: observation.generation
        )
        let store = ComputerUseApprovalStore(
            userDefaults: isolatedDefaults(),
            storageKey: "phase4.approvals"
        )
        let service = ComputerUseApprovalPolicyService(
            policy: ComputerUsePolicyService(
                configuration: ComputerUsePolicyConfiguration(persistentApprovalRisks: [.scroll])
            ),
            store: store
        )

        let prepared = try service.prepare(request)
        XCTAssertEqual(prepared.allowedScopes, [.once, .session, .always])
        let grant = try service.grant(for: prepared, scope: .session)
        XCTAssertEqual(grant.requestID, request.id)
        XCTAssertEqual(grant.scope, .session)
        XCTAssertEqual(grant.applicationID, observation.target.application.id)
        XCTAssertEqual(grant.windowID, observation.target.window.id)
        XCTAssertEqual(grant.observationGeneration, observation.generation)
        XCTAssertEqual(grant.action, request.action)
        XCTAssertEqual(grant.sessionID, sessionID)
        XCTAssertEqual(try service.rememberedScope(for: request), .session)
    }

    func testApprovalPolicyRecordsOnlyRedactedAuditData() throws {
        let observation = makePhase3Observation(generation: 3)
        let request = ComputerUseApprovalRequest(
            id: UUID(),
            action: .typeText("private-value-that-must-not-be-logged"),
            target: observation.target,
            risk: .textEntry,
            reason: "Enter text.",
            observationGeneration: observation.generation
        )
        let recorder = MemoryComputerUseAuditRecorder()
        let service = ComputerUseApprovalPolicyService(
            store: ComputerUseApprovalStore(
                userDefaults: isolatedDefaults(),
                storageKey: "phase4.approvals"
            ),
            auditRecorder: recorder,
            dateProvider: { Date(timeIntervalSince1970: 15_000) }
        )

        let prepared = try service.prepare(request)
        _ = try service.grant(for: prepared, scope: .once)

        XCTAssertEqual(recorder.records.map(\.kind), [.approvalRequested, .approvalResolved])
        XCTAssertEqual(recorder.records.map(\.outcome), [.allowed, .accepted])
        XCTAssertEqual(recorder.records.last?.actionSummary, "Type 37 characters")
        XCTAssertFalse(recorder.records.contains { $0.actionSummary.contains("private-value") })
        XCTAssertTrue(recorder.records.allSatisfy { $0.timestamp == Date(timeIntervalSince1970: 15_000) })
    }

    func testApprovalPolicyRejectsDeniedForbiddenAndUnsupportedScope() {
        let observation = makePhase3Observation(generation: 1)
        let defaults = isolatedDefaults()
        let store = ComputerUseApprovalStore(userDefaults: defaults, storageKey: "phase4.approvals")
        let policy = ComputerUsePolicyService(
            configuration: ComputerUsePolicyConfiguration(
                deniedBundleIdentifiers: [observation.target.application.bundleIdentifier],
                persistentApprovalRisks: []
            )
        )
        let service = ComputerUseApprovalPolicyService(policy: policy, store: store)
        let request = ComputerUseApprovalRequest(
            id: UUID(),
            action: .click(point: ComputerUsePoint(x: 10, y: 10)),
            target: observation.target,
            risk: .click,
            reason: "Click the target.",
            observationGeneration: observation.generation
        )

        assertPolicyError(.applicationDenied("Computer Use is blocked from using Target App by policy.")) {
            _ = try service.prepare(request)
        }

        let forbiddenService = ComputerUseApprovalPolicyService(
            policy: ComputerUsePolicyService(
                configuration: ComputerUsePolicyConfiguration(
                    forbiddenBundleIdentifiers: [observation.target.application.bundleIdentifier]
                )
            ),
            store: store
        )
        assertPolicyError(.applicationForbidden("Computer Use is not allowed to use Target App for safety reasons.")) {
            _ = try forbiddenService.prepare(request)
        }

        let allowedService = ComputerUseApprovalPolicyService(
            policy: ComputerUsePolicyService(),
            store: store
        )
        assertPolicyError(.approvalScopeNotAllowed) {
            _ = try allowedService.grant(for: request, scope: .always)
        }
    }

    func testApprovalRequestHidesTextBeforeItReachesApprovalUI() {
        let observation = makePhase3Observation(generation: 1)
        let request = ComputerUseApprovalRequest(
            id: UUID(),
            action: .typeText("do-not-show-this-secret"),
            target: observation.target,
            risk: .textEntry,
            reason: "Enter text."
        )

        XCTAssertEqual(request.textPreview, "(23 characters hidden)")
        XCTAssertFalse(request.textPreview?.contains("do-not-show") == true)
    }

    private func application(bundleIdentifier: String) -> ComputerUseApplication {
        ComputerUseApplication(
            id: "\(bundleIdentifier)#42",
            bundleIdentifier: bundleIdentifier,
            displayName: "Target App",
            processIdentifier: 42,
            isRunning: true,
            isActive: true,
            launchDate: nil
        )
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "Suniye-Phase4-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func assertPolicyError(
        _ expected: ComputerUsePolicyError,
        operation: () throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            try operation()
            XCTFail("Expected policy error \(expected)", file: file, line: line)
        } catch let error as ComputerUsePolicyError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}
