import ApplicationServices
import Foundation

struct SystemComputerUseAccessibilityActions: ComputerUseAccessibilityActionPerforming {
    func press(
        reference: ComputerUseAccessibilityElementReference,
        target: ComputerUseObservedTarget
    ) async throws -> Bool {
        try await run(reference: reference, target: target) { worker, element in
            guard worker.actions(element).contains(kAXPressAction as String) else {
                return false
            }
            guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else {
                throw ComputerUseActionError.actionUnavailable(kAXPressAction as String)
            }
            return true
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
            guard worker.actions(element).contains(action),
                  AXUIElementPerformAction(element, action as CFString) == .success else {
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
        if actions(element).contains(Self.scrollToVisibleAction) {
            AXUIElementPerformAction(element, Self.scrollToVisibleAction as CFString)
        }
    }

    func actions(_ element: AXUIElement) -> [String] {
        SystemComputerUseAccessibilityAPI.actionNames(from: element)
    }

    private func accessibilityRoots() throws -> [AXUIElement] {
        guard let pid = target.application.processIdentifier else {
            throw ComputerUseActionError.staleObservation(target.application.displayName)
        }
        let app = AXUIElementCreateApplication(pid)
        let windows = SystemComputerUseAccessibilityAPI.elements(
            kAXWindowsAttribute,
            from: app
        ) ?? []
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
        guard let identifier = reference.identifier else {
            return true
        }
        return SystemComputerUseAccessibilityAPI.string(
            kAXIdentifierAttribute,
            from: element
        ) == identifier
    }
}
