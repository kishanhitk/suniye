import Foundation

protocol ComputerUseApprovalAuthorizing: Sendable {
    func prepare(
        _ request: ComputerUseApprovalRequest
    ) async throws -> ComputerUseApprovalRequest

    func rememberedScope(
        for request: ComputerUseApprovalRequest
    ) async throws -> ComputerUseApprovalScope?

    func grant(
        for request: ComputerUseApprovalRequest,
        scope: ComputerUseApprovalScope
    ) async throws -> ComputerUseApprovalGrant
}

actor ComputerUseApprovalPolicyActor: ComputerUseApprovalAuthorizing {
    private let policyService: ComputerUseApprovalPolicyService

    init(policyService: ComputerUseApprovalPolicyService) {
        self.policyService = policyService
    }

    func prepare(
        _ request: ComputerUseApprovalRequest
    ) async throws -> ComputerUseApprovalRequest {
        try policyService.prepare(request)
    }

    func rememberedScope(
        for request: ComputerUseApprovalRequest
    ) async throws -> ComputerUseApprovalScope? {
        try policyService.rememberedScope(for: request)
    }

    func grant(
        for request: ComputerUseApprovalRequest,
        scope: ComputerUseApprovalScope
    ) async throws -> ComputerUseApprovalGrant {
        try policyService.grant(for: request, scope: scope)
    }
}
