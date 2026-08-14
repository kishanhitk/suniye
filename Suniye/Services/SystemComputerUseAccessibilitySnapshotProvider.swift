import ApplicationServices
import Foundation

struct SystemComputerUseAccessibilitySnapshotProvider: ComputerUseAccessibilitySnapshotProviding {
    let maximumDepth: Int
    let maximumElements: Int
    let maximumValueLength: Int

    init(maximumDepth: Int = 30, maximumElements: Int = 1_500, maximumValueLength: Int = 1_000) {
        self.maximumDepth = maximumDepth
        self.maximumElements = maximumElements
        self.maximumValueLength = maximumValueLength
    }

    func snapshot(processIdentifier: Int32, windowOrdinal: Int) async throws
        -> ComputerUseAXSnapshot
    {
        // Detached to stay off the caller's actor; cancellation is forwarded
        // explicitly because detached tasks do not inherit it.
        let traversal = Task.detached(priority: .userInitiated) {
            var reader = Reader(
                maximumDepth: maximumDepth,
                maximumElements: maximumElements,
                maximumValueLength: maximumValueLength
            )
            return try reader.snapshot(pid: processIdentifier, windowOrdinal: windowOrdinal)
        }
        return try await withTaskCancellationHandler {
            try await traversal.value
        } onCancel: {
            traversal.cancel()
        }
    }

    private struct Reader {
        let maximumDepth: Int
        let maximumElements: Int
        let maximumValueLength: Int
        var elementCount = 0
        var focusedElement: AXUIElement?

        /// Per-message AX timeout. An unresponsive target process would
        /// otherwise stall each attribute read indefinitely (the default
        /// global timeout is 6 s per message, multiplied across a traversal
        /// of hundreds of elements).
        private static let messagingTimeout: Float = 1.0

        mutating func snapshot(pid: Int32, windowOrdinal: Int) throws -> ComputerUseAXSnapshot {
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, Self.messagingTimeout)
            focusedElement = SystemComputerUseAccessibilityAPI.element(
                kAXFocusedUIElementAttribute,
                from: application
            )
            let windows = try requiredApplicationWindows(from: application)
            guard windows.indices.contains(windowOrdinal) else {
                throw ComputerUseAccessibilitySnapshotError.windowUnavailable(windowOrdinal)
            }
            var roots = [read(windows[windowOrdinal], depth: 0)].compactMap { $0 }
            if let menuBar = SystemComputerUseAccessibilityAPI.element(
                kAXMenuBarAttribute,
                from: application
            ),
               let menuNode = read(menuBar, depth: 0) {
                roots.append(menuNode)
            }
            return ComputerUseAXSnapshot(roots: roots)
        }

        mutating func read(_ element: AXUIElement, depth: Int) -> ComputerUseAXNode? {
            guard depth <= maximumDepth, elementCount < maximumElements,
                  !Task.isCancelled else {
                return nil
            }
            elementCount += 1
            let role = string(kAXRoleAttribute, from: element) ?? "AXUnknown"
            let children = SystemComputerUseAccessibilityAPI.elements(
                kAXChildrenAttribute,
                from: element
            ) ?? []
            return ComputerUseAXNode(
                role: role,
                roleDescription: string(kAXRoleDescriptionAttribute, from: element),
                subrole: string(kAXSubroleAttribute, from: element),
                title: string(kAXTitleAttribute, from: element),
                description: string(kAXDescriptionAttribute, from: element),
                help: string(kAXHelpAttribute, from: element),
                identifier: string(kAXIdentifierAttribute, from: element),
                value: renderedValue(from: element),
                isEnabled: boolean(kAXEnabledAttribute, from: element) ?? true,
                isValueSettable: isValueSettable(element),
                isFocused: isFocused(element),
                secondaryActions: actions(from: element)
                    .filter { $0.rawName != kAXPressAction }
                    .map(\.exposedName),
                children: children.compactMap { read($0, depth: depth + 1) }
            )
        }

        private func requiredElements(_ attribute: String, from element: AXUIElement) throws
            -> [AXUIElement]
        {
            guard let elements = SystemComputerUseAccessibilityAPI.elements(
                attribute,
                from: element
            ) else {
                throw ComputerUseAccessibilitySnapshotError.attributeUnavailable(attribute)
            }
            return elements
        }

        private func requiredApplicationWindows(from application: AXUIElement) throws
            -> [AXUIElement]
        {
            let result = SystemComputerUseAccessibilityAPI.applicationWindowElements(
                from: application
            )
            guard result.error == .success else {
                throw ComputerUseAccessibilitySnapshotError.attributeUnavailable(
                    kAXWindowsAttribute
                )
            }
            return result.windows
        }

        private func string(_ attribute: String, from element: AXUIElement) -> String? {
            SystemComputerUseAccessibilityAPI.string(attribute, from: element)
        }

        private func boolean(_ attribute: String, from element: AXUIElement) -> Bool? {
            SystemComputerUseAccessibilityAPI.boolean(attribute, from: element)
        }

        private func isValueSettable(_ element: AXUIElement) -> Bool {
            var settable = DarwinBoolean(false)
            return AXUIElementIsAttributeSettable(
                element,
                kAXValueAttribute as CFString,
                &settable
            ) == .success && settable.boolValue
        }

        private func isFocused(_ element: AXUIElement) -> Bool {
            if let focusedElement, CFEqual(element, focusedElement) {
                return true
            }
            return boolean(kAXFocusedAttribute, from: element) ?? false
        }

        private func renderedValue(from element: AXUIElement) -> String? {
            guard let value = SystemComputerUseAccessibilityAPI.copied(
                kAXValueAttribute,
                from: element
            ) else {
                return nil
            }
            guard let rendered = Self.renderedValueDescription(value) else {
                return nil
            }
            return String(rendered.prefix(maximumValueLength))
        }

        /// `String(describing:)` on raw AX values prints pointer addresses,
        /// which change every snapshot and defeat the revision diff. Render
        /// only value types with a stable textual form.
        private static func renderedValueDescription(_ value: CFTypeRef) -> String? {
            if let string = value as? String {
                return string
            }
            if let number = value as? NSNumber {
                return number.stringValue
            }
            if let url = value as? URL {
                return url.absoluteString
            }
            if let attributed = value as? NSAttributedString {
                return attributed.string
            }
            return nil
        }

        private func actions(from element: AXUIElement)
            -> [ComputerUseAccessibilityActionDescriptor]
        {
            SystemComputerUseAccessibilityAPI.actions(from: element)
        }
    }
}

enum ComputerUseAccessibilitySnapshotError: LocalizedError, Equatable, Sendable {
    case windowUnavailable(Int)
    case attributeUnavailable(String)

    var errorDescription: String? {
        switch self {
        case let .windowUnavailable(ordinal):
            "Accessibility window \(ordinal) is unavailable."
        case let .attributeUnavailable(attribute):
            "Accessibility attribute \(attribute) is unavailable."
        }
    }
}
