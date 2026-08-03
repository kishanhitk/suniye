import ApplicationServices
import Foundation

final class ComputerUseActionService: ComputerUseActionServicing {
    private let inputEventPoster: ComputerUseInputEventPosting
    private let textInserter: TextInsertionServiceProtocol
    private let secondaryActionPerformer: ComputerUseSecondaryActionPerforming
    private let valueActionPerformer: ComputerUseValueActionPerforming
    private let targetActivator: ComputerUseWindowActivating
    private let permissionManager: ComputerUsePermissionManaging
    private let approvalStore: ComputerUseApprovalStoring
    private let policy: ComputerUsePolicyChecking
    private let dateProvider: () -> Date

    init(
        inputEventPoster: ComputerUseInputEventPosting = SystemComputerUseInputEventPoster(),
        textInserter: TextInsertionServiceProtocol = TextInsertionService(),
        secondaryActionPerformer: ComputerUseSecondaryActionPerforming = SystemComputerUseAccessibilityReader(),
        valueActionPerformer: ComputerUseValueActionPerforming = SystemComputerUseAccessibilityReader(),
        targetActivator: ComputerUseWindowActivating = SystemComputerUseWindowActivator(),
        permissionManager: ComputerUsePermissionManaging = SystemComputerUsePermissionService(),
        approvalStore: ComputerUseApprovalStoring = ComputerUseApprovalStore(),
        policy: ComputerUsePolicyChecking = ComputerUsePolicyService(),
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.inputEventPoster = inputEventPoster
        self.textInserter = textInserter
        self.secondaryActionPerformer = secondaryActionPerformer
        self.valueActionPerformer = valueActionPerformer
        self.targetActivator = targetActivator
        self.permissionManager = permissionManager
        self.approvalStore = approvalStore
        self.policy = policy
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
        try validateActionShape(action)
        guard isApprovalValid(
            action: action,
            observation: observation,
            approval: approval
        ) else {
            throw ComputerUseActionError.approvalRequired
        }
        guard approval.requestID == requestID,
              approval.applicationID == observation.target.application.id,
              approval.windowID == observation.target.window.id,
              approval.observationGeneration == observation.generation,
              approval.action == action else {
            throw ComputerUseActionError.staleApproval
        }
        guard permissionManager.snapshot().canReadAccessibility else {
            throw ComputerUseActionError.permissionRequired
        }
        guard targetActivator.activate(target: observation.target) else {
            throw ComputerUseActionError.targetActivationFailed
        }

        switch action {
        case let .click(point, clickCount, mouseButton):
            try inputEventPoster.click(
                at: screenPoint(point, in: observation.target.window),
                mouseButton: mouseButton,
                clickCount: clickCount,
                cancellation: cancellation
            )
        case let .clickElement(elementIndex, clickCount, mouseButton):
            try clickElement(
                elementIndex: elementIndex,
                clickCount: clickCount,
                mouseButton: mouseButton,
                observation: observation,
                cancellation: cancellation
            )
        case let .keyPress(key, modifiers):
            try inputEventPoster.keyPress(
                key: key,
                modifiers: modifiers,
                targetProcessIdentifier: observation.target.application.processIdentifier,
                cancellation: cancellation
            )
        case let .scroll(elementIndex, direction, pages):
            let point = observation.accessibility.elements
                .first(where: { $0.index == elementIndex })
                .flatMap { computerUseElementCenter($0, in: observation.target.window) }
            let delta = direction.eventDelta(pages: pages)
            try inputEventPoster.scroll(
                horizontal: delta.horizontal,
                vertical: delta.vertical,
                at: point.map { screenPoint($0, in: observation.target.window) },
                cancellation: cancellation
            )
        case let .typeText(text):
            do {
                guard !cancellation.isCancelled else {
                    throw ComputerUseActionError.cancelled
                }
                try textInserter.insertTextForComputerUse(
                    text,
                    targetProcessIdentifier: observation.target.application.processIdentifier
                )
            } catch let error as ComputerUseActionError {
                throw error
            } catch {
                throw ComputerUseActionError.textInsertionFailed(error.localizedDescription)
            }
        case let .setValue(elementIndex, value):
            try valueActionPerformer.setValue(
                value,
                elementIndex: elementIndex,
                target: observation.target,
                cancellation: cancellation
            )
        case let .drag(from, to):
            try inputEventPoster.drag(
                from: screenPoint(from, in: observation.target.window),
                to: screenPoint(to, in: observation.target.window),
                cancellation: cancellation
            )
        case let .selectText(elementIndex, text, prefix, suffix, selectionType):
            try valueActionPerformer.selectText(
                text,
                elementIndex: elementIndex,
                prefix: prefix,
                suffix: suffix,
                selectionType: selectionType,
                target: observation.target,
                cancellation: cancellation
            )
        case let .secondaryAction(elementIndex, action):
            try secondaryActionPerformer.perform(
                action: action,
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

    private func screenPoint(
        _ point: ComputerUsePoint,
        in window: ComputerUseWindow
    ) -> ComputerUsePoint {
        ComputerUsePoint(
            x: window.bounds.x + point.x,
            y: window.bounds.y + point.y
        )
    }

    private func validateActionShape(_ action: ComputerUseAction) throws {
        switch action {
        case let .click(point, clickCount, _):
            guard clickCount >= 1 else {
                throw ComputerUseActionError.invalidAction("click count must be at least 1")
            }
            guard point.x.isFinite, point.y.isFinite else {
                throw ComputerUseActionError.invalidAction("click coordinates must be finite")
            }
        case let .clickElement(_, clickCount, _):
            guard clickCount >= 1 else {
                throw ComputerUseActionError.invalidAction("click count must be at least 1")
            }
        case .keyPress, .typeText:
            break
        case let .scroll(_, _, pages):
            guard pages.isFinite, pages > 0 else {
                throw ComputerUseActionError.invalidAction("pages must be a finite number greater than 0")
            }
        case .setValue, .selectText, .secondaryAction:
            break
        case let .drag(from, to):
            guard from.x.isFinite, from.y.isFinite, to.x.isFinite, to.y.isFinite else {
                throw ComputerUseActionError.invalidAction("drag coordinates must be finite")
            }
        }
    }

    private func clickElement(
        elementIndex: Int,
        clickCount: Int,
        mouseButton: ComputerUseMouseButton,
        observation: ComputerUseObservation,
        cancellation: ComputerUseCancellationToken
    ) throws {
        if mouseButton != .left,
           let element = observation.accessibility.elements.first(where: { $0.index == elementIndex }),
           let point = computerUseElementCenter(element, in: observation.target.window) {
            try inputEventPoster.click(
                at: screenPoint(point, in: observation.target.window),
                mouseButton: mouseButton,
                clickCount: clickCount,
                cancellation: cancellation
            )
            return
        }

        for _ in 0 ..< clickCount {
            guard !cancellation.isCancelled else {
                throw ComputerUseActionError.cancelled
            }
            try secondaryActionPerformer.perform(
                action: kAXPressAction as String,
                elementIndex: elementIndex,
                target: observation.target,
                cancellation: cancellation
            )
        }
    }

    private func isApprovalValid(
        action: ComputerUseAction,
        observation: ComputerUseObservation,
        approval: ComputerUseApprovalGrant
    ) -> Bool {
        guard case let .allowed(scopes) = policy.evaluate(
            application: observation.target.application,
            action: action
        ), scopes.contains(approval.scope) else {
            return false
        }

        switch approval.scope {
        case .once:
            return true
        case .session, .always:
            return approvalStore.rememberedScope(
                applicationBundleIdentifier: observation.target.application.bundleIdentifier,
                risk: action.risk,
                sessionID: approval.sessionID,
                now: dateProvider()
            ) == approval.scope
        }
    }

}

private extension ComputerUseScrollDirection {
    func eventDelta(pages: Double) -> (horizontal: Double, vertical: Double) {
        let amount = pages * 400
        switch self {
        case .up:
            return (0, -amount)
        case .down:
            return (0, amount)
        case .left:
            return (-amount, 0)
        case .right:
            return (amount, 0)
        }
    }
}

fileprivate func computerUseElementCenter(
    _ element: ComputerUseAXElement,
    in window: ComputerUseWindow
) -> ComputerUsePoint? {
    guard let bounds = element.bounds,
          bounds.x.isFinite,
          bounds.y.isFinite,
          bounds.width > 0,
          bounds.height > 0 else {
        return nil
    }

    let point = ComputerUsePoint(
        x: bounds.x - window.bounds.x + bounds.width / 2,
        y: bounds.y - window.bounds.y + bounds.height / 2
    )
    return point
}
