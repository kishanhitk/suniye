import Foundation

protocol ComputerUseApprovalAuthorizing: Sendable {
    func authorize(
        _ request: ComputerUseApprovalRequest
    ) async throws -> ComputerUseApprovalGrant
}

struct ComputerUseAutomaticApprovalAuthorizer: ComputerUseApprovalAuthorizing {
    func authorize(
        _ request: ComputerUseApprovalRequest
    ) async throws -> ComputerUseApprovalGrant {
        ComputerUseApprovalGrant(
            requestID: request.id,
            scope: .once,
            applicationID: request.target.application.id,
            windowID: request.target.window.id,
            observationGeneration: request.observationGeneration,
            action: request.action,
            sessionID: request.sessionID
        )
    }
}

actor ComputerUseApprovalPolicyActor: ComputerUseApprovalAuthorizing {
    private let policyService: ComputerUseApprovalPolicyService

    init(policyService: ComputerUseApprovalPolicyService) {
        self.policyService = policyService
    }

    func authorize(
        _ request: ComputerUseApprovalRequest
    ) async throws -> ComputerUseApprovalGrant {
        try policyService.authorize(request)
    }
}
