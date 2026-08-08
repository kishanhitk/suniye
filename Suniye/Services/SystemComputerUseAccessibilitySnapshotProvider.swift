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
        try await Task.detached(priority: .userInitiated) {
            var reader = Reader(
                maximumDepth: maximumDepth,
                maximumElements: maximumElements,
                maximumValueLength: maximumValueLength
            )
            return try reader.snapshot(pid: processIdentifier, windowOrdinal: windowOrdinal)
        }.value
    }

    private struct Reader {
        let maximumDepth: Int
        let maximumElements: Int
        let maximumValueLength: Int
        var elementCount = 0

        mutating func snapshot(pid: Int32, windowOrdinal: Int) throws -> ComputerUseAXSnapshot {
            let application = AXUIElementCreateApplication(pid)
            let windows = try elements(kAXWindowsAttribute, from: application)
            guard windows.indices.contains(windowOrdinal) else {
                throw ComputerUseAccessibilitySnapshotError.windowUnavailable(windowOrdinal)
            }
            var roots = [read(windows[windowOrdinal], depth: 0)].compactMap { $0 }
            if let menuBar = element(kAXMenuBarAttribute, from: application),
               let menuNode = read(menuBar, depth: 0) {
                roots.append(menuNode)
            }
            return ComputerUseAXSnapshot(roots: roots)
        }

        mutating func read(_ element: AXUIElement, depth: Int) -> ComputerUseAXNode? {
            guard depth <= maximumDepth, elementCount < maximumElements else {
                return nil
            }
            elementCount += 1
            let role = string(kAXRoleAttribute, from: element) ?? "AXUnknown"
            let children = (try? elements(kAXChildrenAttribute, from: element)) ?? []
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
                secondaryActions: actionNames(from: element).filter { $0 != kAXPressAction },
                children: children.compactMap { read($0, depth: depth + 1) }
            )
        }

        private func copied(_ attribute: String, from element: AXUIElement) -> CFTypeRef? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
            else {
                return nil
            }
            return value
        }

        private func elements(_ attribute: String, from element: AXUIElement) throws
            -> [AXUIElement]
        {
            guard let value = copied(attribute, from: element) else {
                throw ComputerUseAccessibilitySnapshotError.attributeUnavailable(attribute)
            }
            return (value as? [AXUIElement]) ?? []
        }

        private func element(_ attribute: String, from source: AXUIElement) -> AXUIElement? {
            guard let value = copied(attribute, from: source),
                  CFGetTypeID(value) == AXUIElementGetTypeID() else {
                return nil
            }
            return (value as! AXUIElement)
        }

        private func string(_ attribute: String, from element: AXUIElement) -> String? {
            copied(attribute, from: element) as? String
        }

        private func boolean(_ attribute: String, from element: AXUIElement) -> Bool? {
            (copied(attribute, from: element) as? NSNumber)?.boolValue
        }

        private func isValueSettable(_ element: AXUIElement) -> Bool {
            var settable = DarwinBoolean(false)
            return AXUIElementIsAttributeSettable(
                element,
                kAXValueAttribute as CFString,
                &settable
            ) == .success && settable.boolValue
        }

        private func renderedValue(from element: AXUIElement) -> String? {
            guard let value = copied(kAXValueAttribute, from: element) else {
                return nil
            }
            let rendered = (value as? String) ?? String(describing: value)
            return String(rendered.prefix(maximumValueLength))
        }

        private func actionNames(from element: AXUIElement) -> [String] {
            var names: CFArray?
            guard AXUIElementCopyActionNames(element, &names) == .success else {
                return []
            }
            return (names as? [String]) ?? []
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
