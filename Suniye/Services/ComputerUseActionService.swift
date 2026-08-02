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
    private let valueActionPerformer: ComputerUseValueActionPerforming
    private let targetValidator: ComputerUseTargetValidating
    private let permissionManager: ComputerUsePermissionManaging
    private let approvalStore: ComputerUseApprovalStoring
    private let policy: ComputerUsePolicyChecking
    private let dateProvider: () -> Date

    init(
        inputEventPoster: ComputerUseInputEventPosting = SystemComputerUseInputEventPoster(),
        textInserter: TextInsertionServiceProtocol = TextInsertionService(),
        semanticActionPerformer: ComputerUseSemanticActionPerforming = SystemComputerUseAccessibilityReader(),
        valueActionPerformer: ComputerUseValueActionPerforming = SystemComputerUseAccessibilityReader(),
        targetValidator: ComputerUseTargetValidating = SystemComputerUseTargetValidator(),
        permissionManager: ComputerUsePermissionManaging = SystemComputerUsePermissionService(),
        approvalStore: ComputerUseApprovalStoring = ComputerUseApprovalStore(),
        policy: ComputerUsePolicyChecking = ComputerUsePolicyService(),
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.inputEventPoster = inputEventPoster
        self.textInserter = textInserter
        self.semanticActionPerformer = semanticActionPerformer
        self.valueActionPerformer = valueActionPerformer
        self.targetValidator = targetValidator
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
        try ComputerUseActionPolicy.validate(action: action, observation: observation)
        guard permissionManager.snapshot().canReadAccessibility else {
            throw ComputerUseActionError.permissionRequired
        }
        guard targetValidator.isCurrent(target: observation.target) else {
            throw ComputerUseActionError.targetNotFrontmost
        }

        switch action {
        case let .click(point, clickCount, mouseButton, _):
            try inputEventPoster.click(
                at: screenPoint(point, in: observation.target.window),
                mouseButton: mouseButton,
                clickCount: clickCount,
                cancellation: cancellation
            )
        case let .clickElement(elementIndex, clickCount, mouseButton, _):
            guard let element = observation.accessibility.elements.first(where: { $0.index == elementIndex }),
                  let point = computerUseElementCenter(element, in: observation.target.window) else {
                throw ComputerUseActionError.invalidAction("element does not expose bounds for a coordinate click")
            }
            try inputEventPoster.click(
                at: screenPoint(point, in: observation.target.window),
                mouseButton: mouseButton,
                clickCount: clickCount,
                cancellation: cancellation
            )
        case let .keyPress(key, modifiers):
            try inputEventPoster.keyPress(
                key: key,
                modifiers: modifiers,
                cancellation: cancellation
            )
        case let .scroll(horizontal, vertical, point, _):
            try inputEventPoster.scroll(
                horizontal: horizontal,
                vertical: vertical,
                at: point.map { screenPoint($0, in: observation.target.window) },
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
        case let .setValue(elementIndex, value):
            try valueActionPerformer.setValue(
                value,
                elementIndex: elementIndex,
                target: observation.target,
                cancellation: cancellation
            )
        case let .drag(from, to, _):
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
            let canonicalAction = try ComputerUseActionPolicy.resolvedAction(
                action,
                elementIndex: elementIndex,
                observation: observation
            )
            try semanticActionPerformer.perform(
                action: canonicalAction,
                elementIndex: elementIndex,
                target: observation.target,
                cancellation: cancellation
            )
        case let .semantic(elementIndex, semanticAction):
            try semanticActionPerformer.perform(
                action: semanticAction.rawValue,
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

enum ComputerUseActionPolicy {
    static func validate(
        action: ComputerUseAction,
        observation: ComputerUseObservation
    ) throws {
        switch action {
        case let .click(point, clickCount, _, screenshotID):
            try validateScreenshot(screenshotID, observation: observation)
            guard clickCount >= 1, clickCount <= 3 else {
                throw ComputerUseActionError.invalidAction("click count must be between 1 and 3")
            }
            guard isInsideWindow(point, observation.target.window) else {
                throw ComputerUseActionError.invalidAction("click must be inside the target window")
            }
        case let .clickElement(elementIndex, clickCount, _, screenshotID):
            try validateScreenshot(screenshotID, observation: observation)
            guard clickCount >= 1, clickCount <= 3 else {
                throw ComputerUseActionError.invalidAction("click count must be between 1 and 3")
            }
            let element = try validateElement(
                index: elementIndex,
                observation: observation,
                actionDescription: "click"
            )
            guard computerUseElementCenter(element, in: observation.target.window) != nil else {
                throw ComputerUseActionError.invalidAction("element bounds must be inside the target window")
            }
        case let .keyPress(key, _):
            if case let .character(value) = key,
               value.count != 1 {
                throw ComputerUseActionError.invalidAction("character key must contain one character")
            }
        case let .scroll(horizontal, vertical, point, screenshotID):
            try validateScreenshot(screenshotID, observation: observation)
            guard horizontal.isFinite,
                  vertical.isFinite,
                  abs(horizontal) <= 5_000,
                  abs(vertical) <= 5_000 else {
                throw ComputerUseActionError.invalidAction("scroll values exceed the allowed range")
            }
            if let point, !isInsideWindow(point, observation.target.window) {
                throw ComputerUseActionError.invalidAction("scroll point must be inside the target window")
            }
        case let .typeText(text):
            guard !text.isEmpty, text.count <= 10_000 else {
                throw ComputerUseActionError.invalidAction("text must contain between 1 and 10,000 characters")
            }
        case let .setValue(elementIndex, value):
            _ = try validateElement(
                index: elementIndex,
                observation: observation,
                actionDescription: "set value"
            )
            guard !value.isEmpty, value.count <= 10_000 else {
                throw ComputerUseActionError.invalidAction("value must contain between 1 and 10,000 characters")
            }
        case let .drag(from, to, screenshotID):
            try validateScreenshot(screenshotID, observation: observation)
            guard isInsideWindow(from, observation.target.window),
                  isInsideWindow(to, observation.target.window) else {
                throw ComputerUseActionError.invalidAction("drag points must be inside the target window")
            }
        case let .selectText(elementIndex, text, prefix, suffix, _):
            _ = try validateElement(
                index: elementIndex,
                observation: observation,
                actionDescription: "select text"
            )
            guard !text.isEmpty, text.count <= 10_000 else {
                throw ComputerUseActionError.invalidAction("selected text must contain between 1 and 10,000 characters")
            }
            guard (prefix?.count ?? 0) <= 2_000,
                  (suffix?.count ?? 0) <= 2_000 else {
                throw ComputerUseActionError.invalidAction("text selection context is too large")
            }
        case let .secondaryAction(elementIndex, action):
            let element = try validateElement(
                index: elementIndex,
                observation: observation,
                actionDescription: nil
            )
            guard !action.isEmpty, action.count <= 256 else {
                throw ComputerUseActionError.invalidAction("Accessibility action name is invalid")
            }
            guard resolvedAction(action, on: element) != nil else {
                throw ComputerUseActionError.invalidAction("the element does not expose \(action)")
            }
        case let .semantic(elementIndex, semanticAction):
            let element = try validateElement(index: elementIndex, observation: observation, actionDescription: nil)
            guard element.actions.contains(semanticAction.rawValue) else {
                throw ComputerUseActionError.invalidAction("the element does not expose \(semanticAction.rawValue)")
            }
        }
    }

    private static func isInsideWindow(
        _ point: ComputerUsePoint,
        _ window: ComputerUseWindow
    ) -> Bool {
        point.x.isFinite
            && point.y.isFinite
            && CGRect(
                origin: .zero,
                size: CGSize(width: window.bounds.width, height: window.bounds.height)
            ).contains(point.cgPoint)
    }

    private static func validateScreenshot(
        _ screenshotID: String?,
        observation: ComputerUseObservation
    ) throws {
        guard let screenshotID else {
            return
        }
        guard observation.screenshot?.id == screenshotID else {
            throw ComputerUseActionError.staleScreenshot
        }
    }

    private static func validateElement(
        index: Int,
        observation: ComputerUseObservation,
        actionDescription: String?
    ) throws -> ComputerUseAXElement {
        guard let element = observation.accessibility.elements.first(where: { $0.index == index }) else {
            throw ComputerUseActionError.invalidAction("element index is not in the observation")
        }
        guard element.isEnabled != false else {
            if let actionDescription {
                throw ComputerUseActionError.invalidAction("the element is disabled for \(actionDescription)")
            }
            throw ComputerUseActionError.invalidAction("the element is disabled")
        }
        return element
    }

    fileprivate static func resolvedAction(
        _ requestedAction: String,
        elementIndex: Int,
        observation: ComputerUseObservation
    ) throws -> String {
        let element = try validateElement(
            index: elementIndex,
            observation: observation,
            actionDescription: nil
        )
        guard let action = resolvedAction(requestedAction, on: element) else {
            throw ComputerUseActionError.invalidAction("the element does not expose \(requestedAction)")
        }
        return action
    }

    private static func resolvedAction(
        _ requestedAction: String,
        on element: ComputerUseAXElement
    ) -> String? {
        element.actions.first {
            $0.caseInsensitiveCompare(requestedAction) == .orderedSame
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
    return CGRect(
        origin: .zero,
        size: CGSize(width: window.bounds.width, height: window.bounds.height)
    ).contains(point.cgPoint) ? point : nil
}
