import ApplicationServices
import CoreGraphics
import Foundation

private func computerUseAXElement(from value: AnyObject?) -> AXUIElement? {
    guard let value,
          CFGetTypeID(value) == AXUIElementGetTypeID() else {
        return nil
    }
    // The CF type-ID check makes this bridge safe. Swift cannot express this
    // Core Foundation type relationship with a non-forced cast.
    return unsafeBitCast(value, to: AXUIElement.self)
}

private func computerUseAXValue(from value: AnyObject?) -> AXValue? {
    guard let value,
          CFGetTypeID(value) == AXValueGetTypeID() else {
        return nil
    }
    // The CF type-ID check makes this bridge safe. Swift cannot express this
    // Core Foundation type relationship with a non-forced cast.
    return unsafeBitCast(value, to: AXValue.self)
}

struct SystemComputerUseAccessibilityReader: ComputerUseAccessibilityReading {
    private let accessibilityTrustProvider: () -> Bool

    init(accessibilityTrustProvider: @escaping () -> Bool = { AXIsProcessTrusted() }) {
        self.accessibilityTrustProvider = accessibilityTrustProvider
    }

    func read(
        application: ComputerUseApplication,
        window: ComputerUseWindow,
        configuration: ComputerUseObservationConfiguration,
        shouldCancel: () -> Bool
    ) throws -> ComputerUseAXSnapshot {
        guard !shouldCancel() else {
            throw ComputerUseObservationError.cancelled
        }
        guard accessibilityTrustProvider() else {
            throw ComputerUseObservationError.accessibilityNotTrusted
        }

        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        guard let windowElement = resolveWindow(
            in: applicationElement,
            target: window,
            shouldCancel: shouldCancel
        ) else {
            throw ComputerUseObservationError.accessibilityWindowNotFound(window.title ?? "untitled")
        }

        let builder = ComputerUseAXTreeBuilder(configuration: configuration)
        return try builder.build(root: windowElement, shouldCancel: shouldCancel)
    }

    static func resolveWindowElement(
        in applicationElement: AXUIElement,
        target: ComputerUseWindow,
        shouldCancel: () -> Bool
    ) -> AXUIElement? {
        SystemComputerUseAccessibilityReader().resolveWindow(
            in: applicationElement,
            target: target,
            shouldCancel: shouldCancel
        )
    }

    private func resolveWindow(
        in applicationElement: AXUIElement,
        target: ComputerUseWindow,
        shouldCancel: () -> Bool
    ) -> AXUIElement? {
        guard !shouldCancel() else {
            return nil
        }

        let windows = axElements(
            from: copyAttribute(kAXWindowsAttribute as CFString, on: applicationElement)
        )
        guard !windows.isEmpty else {
            return nil
        }

        if let focusedWindowValue = copyAttribute(
            kAXFocusedWindowAttribute as CFString,
            on: applicationElement
        ),
           target.isKeyWindow,
           let focusedWindow = computerUseAXElement(from: focusedWindowValue) {
            if matches(focusedWindow, target: target) {
                return focusedWindow
            }
        }

        let titleMatches = windows.filter { element in
            guard let targetTitle = target.title,
                  !targetTitle.isEmpty,
                  let title = stringAttribute(kAXTitleAttribute as CFString, from: element) else {
                return false
            }
            return title == targetTitle
        }
        if titleMatches.count == 1 {
            return titleMatches[0]
        }

        let boundsMatches = windows.filter { matches($0, target: target) }
        if boundsMatches.count == 1 {
            return boundsMatches[0]
        }

        if windows.count == 1 {
            return windows[0]
        }

        return nil
    }

    private func matches(_ element: AXUIElement, target: ComputerUseWindow) -> Bool {
        guard let position = pointAttribute(kAXPositionAttribute as CFString, from: element),
              let size = sizeAttribute(kAXSizeAttribute as CFString, from: element) else {
            return false
        }

        let targetRect = target.bounds.cgRect
        let elementRect = CGRect(
            x: position.x,
            y: position.y,
            width: size.width,
            height: size.height
        )
        return approximatelyEqual(elementRect, targetRect)
    }

    private func approximatelyEqual(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let tolerance: CGFloat = 3
        return abs(lhs.minX - rhs.minX) <= tolerance
            && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance
            && abs(lhs.height - rhs.height) <= tolerance
    }

    private func copyAttribute(_ attribute: CFString, on element: AXUIElement) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value
    }

    private func axElements(from value: AnyObject?) -> [AXUIElement] {
        if let elements = value as? [AXUIElement] {
            return elements
        }

        guard let values = value as? [AnyObject] else {
            return []
        }
        return values.compactMap(computerUseAXElement)
    }

    fileprivate func stringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
    }

    fileprivate func boolAttribute(_ attribute: CFString, from element: AXUIElement) -> Bool? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return (value as? Bool) ?? (value as? NSNumber)?.boolValue
    }

    fileprivate func pointAttribute(_ attribute: CFString, from element: AXUIElement) -> CGPoint? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value,
              let axValue = computerUseAXValue(from: value) else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else {
            return nil
        }
        return point
    }

    fileprivate func sizeAttribute(_ attribute: CFString, from element: AXUIElement) -> CGSize? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value,
              let axValue = computerUseAXValue(from: value) else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else {
            return nil
        }
        return size
    }
}

extension SystemComputerUseAccessibilityReader: ComputerUseSemanticActionPerforming {
    func perform(
        action: String,
        elementIndex: Int,
        target: ComputerUseTarget,
        cancellation: ComputerUseCancellationToken
    ) throws {
        guard !cancellation.isCancelled else {
            throw ComputerUseActionError.cancelled
        }

        let applicationElement = AXUIElementCreateApplication(target.application.processIdentifier)
        guard let windowElement = resolveWindow(
            in: applicationElement,
            target: target.window,
            shouldCancel: { cancellation.isCancelled }
        ) else {
            throw ComputerUseActionError.semanticActionFailed("target window not found")
        }

        let builder = ComputerUseAXTreeBuilder(configuration: .default)
        guard let element = try builder.element(
            at: elementIndex,
            root: windowElement,
            shouldCancel: { cancellation.isCancelled }
        ) else {
            throw ComputerUseActionError.semanticActionFailed("element \(elementIndex) not found")
        }

        guard !cancellation.isCancelled else {
            throw ComputerUseActionError.cancelled
        }
        guard AXUIElementPerformAction(element, action as CFString) == .success else {
            throw ComputerUseActionError.semanticActionFailed(action)
        }
    }
}

extension SystemComputerUseAccessibilityReader: ComputerUseValueActionPerforming {
    func setValue(
        _ value: String,
        elementIndex: Int,
        target: ComputerUseTarget,
        cancellation: ComputerUseCancellationToken
    ) throws {
        let element = try resolveActionElement(
            elementIndex: elementIndex,
            target: target,
            cancellation: cancellation
        )
        var isSettable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(
            element,
            kAXValueAttribute as CFString,
            &isSettable
        ) == .success,
        isSettable.boolValue else {
            throw ComputerUseActionError.accessibilityValueActionFailed("value is not editable")
        }

        guard !cancellation.isCancelled else {
            throw ComputerUseActionError.cancelled
        }
        guard AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            value as CFTypeRef
        ) == .success else {
            throw ComputerUseActionError.accessibilityValueActionFailed("set value")
        }
    }

    func selectText(
        _ text: String,
        elementIndex: Int,
        prefix: String?,
        suffix: String?,
        selectionType: ComputerUseTextSelectionType,
        target: ComputerUseTarget,
        cancellation: ComputerUseCancellationToken
    ) throws {
        let element = try resolveActionElement(
            elementIndex: elementIndex,
            target: target,
            cancellation: cancellation
        )
        guard let value = stringAttribute(kAXValueAttribute as CFString, from: element) else {
            throw ComputerUseActionError.textSelectionFailed("the element has no text value")
        }
        guard let match = findTextRange(
            text,
            in: value,
            prefix: prefix,
            suffix: suffix
        ) else {
            throw ComputerUseActionError.textSelectionFailed("text was not found")
        }

        var range = match
        switch selectionType {
        case .text:
            break
        case .cursorBefore:
            range.length = 0
        case .cursorAfter:
            range.location += range.length
            range.length = 0
        }

        guard !cancellation.isCancelled else {
            throw ComputerUseActionError.cancelled
        }
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let selectionValue = AXValueCreate(.cfRange, &cfRange),
              AXUIElementSetAttributeValue(
                  element,
                  kAXSelectedTextRangeAttribute as CFString,
                  selectionValue
              ) == .success else {
            throw ComputerUseActionError.textSelectionFailed("the element does not expose a selectable text range")
        }
    }

    private func resolveActionElement(
        elementIndex: Int,
        target: ComputerUseTarget,
        cancellation: ComputerUseCancellationToken
    ) throws -> AXUIElement {
        guard !cancellation.isCancelled else {
            throw ComputerUseActionError.cancelled
        }

        let applicationElement = AXUIElementCreateApplication(target.application.processIdentifier)
        guard let windowElement = resolveWindow(
            in: applicationElement,
            target: target.window,
            shouldCancel: { cancellation.isCancelled }
        ) else {
            throw ComputerUseActionError.accessibilityValueActionFailed("target window not found")
        }

        let builder = ComputerUseAXTreeBuilder(configuration: .default)
        guard let element = try builder.element(
            at: elementIndex,
            root: windowElement,
            shouldCancel: { cancellation.isCancelled }
        ) else {
            throw ComputerUseActionError.accessibilityValueActionFailed("element \(elementIndex) not found")
        }
        return element
    }

    private func findTextRange(
        _ text: String,
        in value: String,
        prefix: String?,
        suffix: String?
    ) -> CFRange? {
        let source = value as NSString
        let target = text as NSString
        var searchLocation = 0

        while searchLocation <= source.length {
            let remaining = NSRange(
                location: searchLocation,
                length: source.length - searchLocation
            )
            let match = source.range(of: target as String, options: [], range: remaining)
            guard match.location != NSNotFound else {
                return nil
            }

            let prefixMatches = prefix.map { expected in
                guard match.location >= expected.utf16.count else {
                    return false
                }
                return source.substring(
                    with: NSRange(
                        location: match.location - expected.utf16.count,
                        length: expected.utf16.count
                    )
                ) == expected
            } ?? true
            let suffixMatches = suffix.map { expected in
                let suffixLocation = match.location + match.length
                guard suffixLocation + expected.utf16.count <= source.length else {
                    return false
                }
                return source.substring(
                    with: NSRange(
                        location: suffixLocation,
                        length: expected.utf16.count
                    )
                ) == expected
            } ?? true

            if prefixMatches && suffixMatches {
                return CFRange(location: match.location, length: match.length)
            }
            searchLocation = match.location + max(match.length, 1)
        }
        return nil
    }
}

private final class ComputerUseAXTreeBuilder {
    private let configuration: ComputerUseObservationConfiguration
    private let reader = SystemComputerUseAccessibilityReader()
    private var elements: [ComputerUseAXElement] = []
    private var lines: [String] = []
    private var wasTruncated = false

    init(configuration: ComputerUseObservationConfiguration) {
        self.configuration = configuration
    }

    func build(
        root: AXUIElement,
        shouldCancel: () -> Bool
    ) throws -> ComputerUseAXSnapshot {
        _ = try append(root, depth: 0, indent: "", shouldCancel: shouldCancel)

        var text = lines.joined(separator: "\n")
        if wasTruncated {
            text += "\n[truncated]"
        }
        if text.count > configuration.maxTextLength {
            text = String(text.prefix(configuration.maxTextLength)) + "\n[truncated]"
            wasTruncated = true
        }

        return ComputerUseAXSnapshot(
            text: text,
            elements: elements,
            wasTruncated: wasTruncated
        )
    }

    func element(
        at targetIndex: Int,
        root: AXUIElement,
        shouldCancel: () -> Bool
    ) throws -> AXUIElement? {
        guard targetIndex >= 0 else {
            return nil
        }

        var nextIndex = 0
        return try find(
            targetIndex: targetIndex,
            element: root,
            depth: 0,
            nextIndex: &nextIndex,
            shouldCancel: shouldCancel
        )
    }

    private func find(
        targetIndex: Int,
        element: AXUIElement,
        depth: Int,
        nextIndex: inout Int,
        shouldCancel: () -> Bool
    ) throws -> AXUIElement? {
        guard !shouldCancel() else {
            throw ComputerUseObservationError.cancelled
        }
        guard nextIndex < configuration.maxElements else {
            return nil
        }

        let currentIndex = nextIndex
        nextIndex += 1
        if currentIndex == targetIndex {
            return element
        }
        guard depth < configuration.maxDepth else {
            return nil
        }

        for child in children(of: element) {
            if let match = try find(
                targetIndex: targetIndex,
                element: child,
                depth: depth + 1,
                nextIndex: &nextIndex,
                shouldCancel: shouldCancel
            ) {
                return match
            }
        }
        return nil
    }

    private func append(
        _ element: AXUIElement,
        depth: Int,
        indent: String,
        shouldCancel: () -> Bool
    ) throws -> Int? {
        guard !shouldCancel() else {
            throw ComputerUseObservationError.cancelled
        }
        guard elements.count < configuration.maxElements else {
            wasTruncated = true
            return nil
        }

        let index = elements.count
        elements.append(
            ComputerUseAXElement(
                index: index,
                role: nil,
                subrole: nil,
                title: nil,
                description: nil,
                value: nil,
                isEnabled: nil,
                isFocused: false,
                isSelected: false,
                bounds: nil,
                actions: [],
                childIndexes: []
            )
        )
        lines.append("")

        let role = reader.stringAttribute(kAXRoleAttribute as CFString, from: element)
        let subrole = reader.stringAttribute(kAXSubroleAttribute as CFString, from: element)
        let title = reader.stringAttribute(kAXTitleAttribute as CFString, from: element)
        let description = reader.stringAttribute(kAXDescriptionAttribute as CFString, from: element)
        let sensitive = configuration.redactSensitiveValues && Self.isSensitiveRole(role)
        let rawValue = reader.stringAttribute(kAXValueAttribute as CFString, from: element)
        let value: String? = sensitive
            ? "[redacted]"
            : rawValue.flatMap { Self.shortValue($0) }
        let isEnabled = reader.boolAttribute(kAXEnabledAttribute as CFString, from: element)
        let isFocused = reader.boolAttribute(kAXFocusedAttribute as CFString, from: element) ?? false
        let isSelected = reader.boolAttribute(kAXSelectedAttribute as CFString, from: element) ?? false
        let bounds = configuration.includeElementBounds
            ? bounds(of: element)
            : nil
        let actions = actionNames(of: element)

        var childIndexes: [Int] = []
        if depth >= configuration.maxDepth {
            if !children(of: element).isEmpty {
                wasTruncated = true
            }
        } else {
            for child in children(of: element) {
                guard let childIndex = try append(
                    child,
                    depth: depth + 1,
                    indent: indent + "  ",
                    shouldCancel: shouldCancel
                ) else {
                    break
                }
                childIndexes.append(childIndex)
            }
        }

        elements[index] = ComputerUseAXElement(
            index: index,
            role: role,
            subrole: subrole,
            title: title,
            description: description,
            value: value,
            isEnabled: isEnabled,
            isFocused: isFocused,
            isSelected: isSelected,
            bounds: bounds,
            actions: actions,
            childIndexes: childIndexes
        )
        lines[index] = formatLine(
            index: index,
            indent: indent,
            role: role,
            title: title,
            description: description,
            value: value,
            isEnabled: isEnabled,
            isFocused: isFocused,
            isSelected: isSelected,
            actions: actions
        )

        return index
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else {
            return []
        }
        if let elements = value as? [AXUIElement] {
            return elements
        }
        guard let values = value as? [AnyObject] else {
            return []
        }
        return values.compactMap(computerUseAXElement)
    }

    private func bounds(of element: AXUIElement) -> ComputerUseRect? {
        guard let position = reader.pointAttribute(kAXPositionAttribute as CFString, from: element),
              let size = reader.sizeAttribute(kAXSizeAttribute as CFString, from: element) else {
            return nil
        }
        return ComputerUseRect(
            x: position.x,
            y: position.y,
            width: size.width,
            height: size.height
        )
    }

    private func actionNames(of element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success,
              let names else {
            return []
        }
        return (names as? [String]) ?? []
    }

    private func formatLine(
        index: Int,
        indent: String,
        role: String?,
        title: String?,
        description: String?,
        value: String?,
        isEnabled: Bool?,
        isFocused: Bool,
        isSelected: Bool,
        actions: [String]
    ) -> String {
        var parts = ["[\(index)]"]
        if let role {
            parts.append("role=\(role)")
        }
        if let title = Self.shortValue(title) {
            parts.append("title=\"\(title)\"")
        }
        if let description = Self.shortValue(description) {
            parts.append("description=\"\(description)\"")
        }
        if let value = Self.shortValue(value) {
            parts.append("value=\"\(value)\"")
        }
        if let isEnabled {
            parts.append("enabled=\(isEnabled)")
        }
        if isFocused {
            parts.append("focused=true")
        }
        if isSelected {
            parts.append("selected=true")
        }
        if !actions.isEmpty {
            parts.append("actions=\(actions.joined(separator: ","))")
        }
        return indent + parts.joined(separator: " ")
    }

    private static func isSensitiveRole(_ role: String?) -> Bool {
        guard let role else {
            return false
        }
        return role == "AXPasswordField"
            || role.localizedCaseInsensitiveContains("password")
    }

    private static func shortValue(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        let normalized = value.replacingOccurrences(of: "\n", with: " ")
        return String(normalized.prefix(512))
    }
}
