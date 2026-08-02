import AppKit
import Foundation

struct SystemComputerUseTargetValidator: ComputerUseTargetValidating {
    private let windowDiscovery: ComputerUseWindowDiscovering
    private let frontmostProcessIdentifierProvider: () -> Int32?

    init(
        windowDiscovery: ComputerUseWindowDiscovering = SystemComputerUseWindowDiscovery(),
        frontmostProcessIdentifierProvider: @escaping () -> Int32? = {
            NSWorkspace.shared.frontmostApplication?.processIdentifier
        }
    ) {
        self.windowDiscovery = windowDiscovery
        self.frontmostProcessIdentifierProvider = frontmostProcessIdentifierProvider
    }

    func isCurrent(target: ComputerUseTarget) -> Bool {
        guard frontmostProcessIdentifierProvider() == target.application.processIdentifier else {
            return false
        }

        guard let currentWindow = windowDiscovery
            .listWindows(for: target.application)
            .first(where: { $0.id == target.window.id }) else {
            return false
        }

        return currentWindow.isKeyWindow
    }
}

final class ComputerUseActionService: ComputerUseActionServicing {
    private let inputEventPoster: ComputerUseInputEventPosting
    private let textInserter: TextInsertionServiceProtocol
    private let semanticActionPerformer: ComputerUseSemanticActionPerforming
    private let targetValidator: ComputerUseTargetValidating
    private let permissionManager: ComputerUsePermissionManaging
    private let dateProvider: () -> Date

    init(
        inputEventPoster: ComputerUseInputEventPosting = SystemComputerUseInputEventPoster(),
        textInserter: TextInsertionServiceProtocol = TextInsertionService(),
        semanticActionPerformer: ComputerUseSemanticActionPerforming = SystemComputerUseAccessibilityReader(),
        targetValidator: ComputerUseTargetValidating = SystemComputerUseTargetValidator(),
        permissionManager: ComputerUsePermissionManaging = SystemComputerUsePermissionService(),
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.inputEventPoster = inputEventPoster
        self.textInserter = textInserter
        self.semanticActionPerformer = semanticActionPerformer
        self.targetValidator = targetValidator
        self.permissionManager = permissionManager
        self.dateProvider = dateProvider
    }

    func execute(
        action: ComputerUseAction,
        observation: ComputerUseObservation,
        approval: ComputerUseApprovalGrant,
        requestID: UUID,
        cancellation: ComputerUseCancellationToken
    ) throws -> ComputerUseActionResult {
        guard !cancellation.isCancelled else {
            throw ComputerUseActionError.cancelled
        }
        guard approval.scope == .once else {
            throw ComputerUseActionError.approvalRequired
        }
        guard approval.requestID == requestID,
              approval.applicationID == observation.target.application.id,
              approval.windowID == observation.target.window.id,
              approval.observationGeneration == observation.generation,
              approval.action == action else {
            throw ComputerUseActionError.staleApproval
        }
        try ComputerUseActionPolicy.validate(action: action, observation: observation)
        guard permissionManager.snapshot().canReadAccessibility else {
            throw ComputerUseActionError.permissionRequired
        }
        guard targetValidator.isCurrent(target: observation.target) else {
            throw ComputerUseActionError.targetNotFrontmost
        }

        switch action {
        case let .click(point):
            try inputEventPoster.click(at: point, cancellation: cancellation)
        case let .keyPress(key, modifiers):
            try inputEventPoster.keyPress(
                key: key,
                modifiers: modifiers,
                cancellation: cancellation
            )
        case let .scroll(horizontal, vertical):
            try inputEventPoster.scroll(
                horizontal: horizontal,
                vertical: vertical,
                cancellation: cancellation
            )
        case let .typeText(text):
            do {
                guard !cancellation.isCancelled else {
                    throw ComputerUseActionError.cancelled
                }
                try textInserter.insertText(text)
            } catch let error as ComputerUseActionError {
                throw error
            } catch {
                throw ComputerUseActionError.textInsertionFailed(error.localizedDescription)
            }
        case let .semantic(elementIndex, semanticAction):
            try semanticActionPerformer.perform(
                action: semanticAction,
                elementIndex: elementIndex,
                target: observation.target,
                cancellation: cancellation
            )
        }

        guard !cancellation.isCancelled else {
            throw ComputerUseActionError.cancelled
        }
        return ComputerUseActionResult(
            action: action,
            target: observation.target,
            completedAt: dateProvider()
        )
    }

}

enum ComputerUseActionPolicy {
    static func validate(
        action: ComputerUseAction,
        observation: ComputerUseObservation
    ) throws {
        switch action {
        case let .click(point):
            guard point.x.isFinite,
                  point.y.isFinite,
                  observation.target.window.bounds.cgRect.contains(point.cgPoint) else {
                throw ComputerUseActionError.invalidAction("click must be inside the target window")
            }
        case let .keyPress(key, _):
            if case let .character(value) = key,
               value.count != 1 {
                throw ComputerUseActionError.invalidAction("character key must contain one character")
            }
        case let .scroll(horizontal, vertical):
            guard horizontal.isFinite,
                  vertical.isFinite,
                  abs(horizontal) <= 5_000,
                  abs(vertical) <= 5_000 else {
                throw ComputerUseActionError.invalidAction("scroll values exceed the allowed range")
            }
        case let .typeText(text):
            guard !text.isEmpty, text.count <= 10_000 else {
                throw ComputerUseActionError.invalidAction("text must contain between 1 and 10,000 characters")
            }
        case let .semantic(elementIndex, semanticAction):
            guard let element = observation.accessibility.elements.first(where: { $0.index == elementIndex }) else {
                throw ComputerUseActionError.invalidAction("element index is not in the observation")
            }
            guard element.isEnabled != false else {
                throw ComputerUseActionError.invalidAction("the element is disabled")
            }
            guard element.actions.contains(semanticAction.rawValue) else {
                throw ComputerUseActionError.invalidAction("the element does not expose \(semanticAction.rawValue)")
            }
        }
    }
}
