import ApplicationServices
import Foundation

struct SystemComputerUseAccessibilityActions: ComputerUseAccessibilityActionPerforming {
    func performPrimaryClick(
        reference: ComputerUseAccessibilityElementReference,
        target: ComputerUseObservedTarget,
        clickCount: Int
    ) async throws -> Bool {
        try await run(reference: reference, target: target) { worker, element in
            // AX actions only cover single clicks; multi-clicks fall through
            // to synthetic mouse events.
            guard clickCount == 1 else { return false }
            for action in [ComputerUseAccessibilityActionResolver.pickAction, kAXPressAction as String] {
                if try worker.performPrimaryActionIfPossible(action, on: element) {
                    return true
                }
            }
            return false
        }
    }

    func center(
        reference: ComputerUseAccessibilityElementReference,
        target: ComputerUseObservedTarget
    ) async throws -> CGPoint {
        try await run(reference: reference, target: target) { worker, element in
            guard let position = SystemComputerUseAccessibilityAPI.point(
                kAXPositionAttribute,
                from: element
            ),
                let size = SystemComputerUseAccessibilityAPI.size(kAXSizeAttribute, from: element),
                  size.width > 0,
                  size.height > 0 else {
                throw ComputerUseActionError.elementChanged
            }
            return CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
        }
    }

    func perform(
        action: String,
        reference: ComputerUseAccessibilityElementReference,
        target: ComputerUseObservedTarget
    ) async throws {
        try await run(reference: reference, target: target) { worker, element in
            let descriptors = worker.actions(element)
            guard let rawName = ComputerUseAccessibilityActionResolver.rawName(
                exposedName: action,
                descriptors: descriptors
            ),
                worker.perform(rawAction: rawName, on: element) else {
                throw ComputerUseActionError.actionUnavailable(action)
            }
        }
    }

    func setValue(
        _ value: String,
        reference: ComputerUseAccessibilityElementReference,
        target: ComputerUseObservedTarget
    ) async throws {
        try await run(reference: reference, target: target) { worker, element in
            worker.focusIfPossible(element)
            var settable = DarwinBoolean(false)
            guard AXUIElementIsAttributeSettable(
                element,
                kAXValueAttribute as CFString,
                &settable
            ) == .success,
                settable.boolValue,
                AXUIElementSetAttributeValue(
                    element,
                    kAXValueAttribute as CFString,
                    value as CFTypeRef
                ) == .success else {
                throw ComputerUseActionError.valueNotSettable
            }
        }
    }

    func selectText(
        _ text: String,
        prefix: String?,
        suffix: String?,
        selectionType: ComputerUseTextSelectionType,
        reference: ComputerUseAccessibilityElementReference,
        target: ComputerUseObservedTarget
    ) async throws {
        try await run(reference: reference, target: target) { worker, element in
            guard let value = SystemComputerUseAccessibilityAPI.string(
                kAXValueAttribute,
                from: element
            ) else {
                throw ComputerUseActionError.textNotFound(text)
            }
            var selection = try ComputerUseTextSelectionResolver.resolve(
                text: text,
                prefix: prefix,
                suffix: suffix,
                selectionType: selectionType,
                in: value
            )
            guard let range = AXValueCreate(.cfRange, &selection),
                  AXUIElementSetAttributeValue(
                    element,
                    kAXSelectedTextRangeAttribute as CFString,
                    range
                  ) == .success else {
                throw ComputerUseActionError.actionUnavailable(kAXSelectedTextRangeAttribute)
            }
        }
    }

    private func run<T: Sendable>(
        reference: ComputerUseAccessibilityElementReference,
        target: ComputerUseObservedTarget,
        operation: @escaping @Sendable (Worker, AXUIElement) throws -> T
    ) async throws -> T {
        try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let worker = Worker(target: target)
            let element = try worker.resolve(reference)
            try worker.prepareForInteraction(element)
            let result = try operation(worker, element)
            try Task.checkCancellation()
            return result
        }.value
    }
}

private struct Worker: Sendable {
    private static let maximumSearchDepth = 30
    private static let maximumSearchElements = 1_500
    private static let scrollToVisibleAction = "AXScrollToVisible"

    let target: ComputerUseObservedTarget

    func resolve(_ reference: ComputerUseAccessibilityElementReference) throws -> AXUIElement {
        let roots = try accessibilityRoots()
        if roots.indices.contains(reference.rootIndex),
           let candidate = element(at: reference.path, from: roots[reference.rootIndex]),
           matches(candidate, reference) {
            return candidate
        }

        guard let identifier = reference.identifier else {
            throw ComputerUseActionError.elementChanged
        }
        var remaining = Self.maximumSearchElements
        let candidates = roots.flatMap {
            descendants(of: $0, depth: 0, remaining: &remaining)
        }.filter {
            SystemComputerUseAccessibilityAPI.string(kAXRoleAttribute, from: $0) == reference.role
                && SystemComputerUseAccessibilityAPI.string(
                    kAXIdentifierAttribute,
                    from: $0
                ) == identifier
        }
        guard candidates.count == 1, let match = candidates.first else {
            throw ComputerUseActionError.elementChanged
        }
        return match
    }

    func prepareForInteraction(_ element: AXUIElement) throws {
        if SystemComputerUseAccessibilityAPI.boolean(kAXEnabledAttribute, from: element) == false {
            throw ComputerUseActionError.elementDisabled
        }
        if actions(element).contains(where: { $0.rawName == Self.scrollToVisibleAction }) {
            AXUIElementPerformAction(element, Self.scrollToVisibleAction as CFString)
        }
    }

    func actions(_ element: AXUIElement) -> [ComputerUseAccessibilityActionDescriptor] {
        SystemComputerUseAccessibilityAPI.actions(from: element)
    }

    func focusIfPossible(_ element: AXUIElement) {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(
            element,
            kAXFocusedAttribute as CFString,
            &settable
        ) == .success,
            settable.boolValue else {
            return
        }
        _ = AXUIElementSetAttributeValue(
            element,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )
    }

    func performPrimaryActionIfPossible(
        _ action: String,
        on element: AXUIElement
    ) throws -> Bool {
        guard actions(element).contains(where: { $0.rawName == action }) else {
            return false
        }
        guard AXUIElementPerformAction(element, action as CFString) == .success else {
            throw ComputerUseActionError.actionUnavailable(action)
        }
        return true
    }

    func perform(rawAction: String, on element: AXUIElement) -> Bool {
        if AXUIElementPerformAction(element, rawAction as CFString) == .success {
            return true
        }
        guard let pageScroll = PageScroll(rawAction: rawAction),
              let scrollBar = SystemComputerUseAccessibilityAPI.element(
                pageScroll.scrollBarAttribute,
                from: element
              ),
              let pageButton = descendants(of: scrollBar).first(where: {
                SystemComputerUseAccessibilityAPI.string(kAXSubroleAttribute, from: $0)
                    == pageScroll.buttonSubrole
              }) else {
            return false
        }
        return AXUIElementPerformAction(pageButton, kAXPressAction as CFString) == .success
    }

    private func accessibilityRoots() throws -> [AXUIElement] {
        guard let pid = target.application.processIdentifier else {
            throw ComputerUseActionError.staleObservation(target.application.displayName)
        }
        let app = AXUIElementCreateApplication(pid)
        let windowResult = SystemComputerUseAccessibilityAPI.applicationWindowElements(from: app)
        let windows = windowResult.error == .success ? windowResult.windows : []
        guard windows.indices.contains(target.window.accessibilityOrdinal) else {
            throw ComputerUseActionError.staleObservation(target.application.displayName)
        }
        var roots = [windows[target.window.accessibilityOrdinal]]
        if let menuBar = SystemComputerUseAccessibilityAPI.element(
            kAXMenuBarAttribute,
            from: app
        ) {
            roots.append(menuBar)
        }
        return roots
    }

    private func element(at path: [Int], from root: AXUIElement) -> AXUIElement? {
        path.reduce(Optional(root)) { current, index in
            guard let current else { return nil }
            let children = SystemComputerUseAccessibilityAPI.elements(
                kAXChildrenAttribute,
                from: current
            ) ?? []
            return children.indices.contains(index) ? children[index] : nil
        }
    }

    private func descendants(
        of root: AXUIElement,
        depth: Int,
        remaining: inout Int
    ) -> [AXUIElement] {
        guard depth <= Self.maximumSearchDepth, remaining > 0 else {
            return []
        }
        remaining -= 1
        let children = SystemComputerUseAccessibilityAPI.elements(
            kAXChildrenAttribute,
            from: root
        ) ?? []
        return [root] + children.flatMap {
            descendants(of: $0, depth: depth + 1, remaining: &remaining)
        }
    }

    private func descendants(of root: AXUIElement) -> [AXUIElement] {
        var remaining = Self.maximumSearchElements
        return descendants(of: root, depth: 0, remaining: &remaining)
    }

    private func matches(
        _ element: AXUIElement,
        _ reference: ComputerUseAccessibilityElementReference
    ) -> Bool {
        guard SystemComputerUseAccessibilityAPI.string(
            kAXRoleAttribute,
            from: element
        ) == reference.role else {
            return false
        }
        if let identifier = reference.identifier {
            return SystemComputerUseAccessibilityAPI.string(
                kAXIdentifierAttribute,
                from: element
            ) == identifier
        }
        return reference.traits.isConsistent(with: liveTraits(of: element))
    }

    private func liveTraits(
        of element: AXUIElement
    ) -> ComputerUseAccessibilityElementTraits {
        ComputerUseAccessibilityElementTraits(
            subrole: SystemComputerUseAccessibilityAPI.string(
                kAXSubroleAttribute,
                from: element
            ),
            roleDescription: SystemComputerUseAccessibilityAPI.string(
                kAXRoleDescriptionAttribute,
                from: element
            ),
            title: SystemComputerUseAccessibilityAPI.string(kAXTitleAttribute, from: element),
            description: SystemComputerUseAccessibilityAPI.string(
                kAXDescriptionAttribute,
                from: element
            )
        )
    }
}

private struct PageScroll {
    let scrollBarAttribute: String
    let buttonSubrole: String

    init?(rawAction: String) {
        switch rawAction {
        case "AXScrollDownByPage":
            scrollBarAttribute = kAXVerticalScrollBarAttribute as String
            buttonSubrole = kAXIncrementPageSubrole as String
        case "AXScrollUpByPage":
            scrollBarAttribute = kAXVerticalScrollBarAttribute as String
            buttonSubrole = kAXDecrementPageSubrole as String
        case "AXScrollRightByPage":
            scrollBarAttribute = kAXHorizontalScrollBarAttribute as String
            buttonSubrole = kAXIncrementPageSubrole as String
        case "AXScrollLeftByPage":
            scrollBarAttribute = kAXHorizontalScrollBarAttribute as String
            buttonSubrole = kAXDecrementPageSubrole as String
        default:
            return nil
        }
    }
}
