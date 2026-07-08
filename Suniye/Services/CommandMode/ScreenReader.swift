import AppKit
import ApplicationServices

/// Resolves an element id (assigned by the last `read_screen`) back to its live AX
/// element, so the click/focus tools can act on what the model referenced.
@MainActor
protocol ElementResolving {
    func element(forId id: String) -> AXUIElement?
}

/// Production perception: walks the frontmost app's accessibility tree, keeps the
/// actionable elements (buttons / menus / fields / links), id-stamps them so the
/// model can say `click("e12")`, and renders a compact text snapshot. The
/// id→element map is retained until the next read and shared (same instance) with
/// the click/focus tools.
@MainActor
final class AXTreeReader: ScreenReading, ElementResolving {
    private var elementsById: [String: AXUIElement] = [:]
    private let maxElements: Int
    private let maxDepth: Int

    init(maxElements: Int = 60, maxDepth: Int = 25) {
        self.maxElements = maxElements
        self.maxDepth = maxDepth
    }

    func element(forId id: String) -> AXUIElement? { elementsById[id] }

    func readScreen() async -> String {
        elementsById = [:]
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return "No frontmost app."
        }
        let appName = app.localizedName ?? "unknown app"
        let root = AXUIElementCreateApplication(app.processIdentifier)
        // Electron/Chromium expose their subtree only after this is set on the app.
        AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        var rows: [String] = []
        var index = 0
        walk(root, depth: 0, index: &index, rows: &rows)
        return Self.summary(appName: appName, focused: focusedField(), rows: rows)
    }

    /// Pure: assemble the snapshot text from the app name, focused field, and rows.
    nonisolated static func summary(appName: String, focused: String?, rows: [String]) -> String {
        var lines = ["Frontmost app: \(appName)"]
        if let focused { lines.append("Focused: \(focused)") }
        if rows.isEmpty {
            lines.append("No actionable elements found.")
        } else {
            lines.append("Actionable elements — reference an id with click/focus:")
            lines.append(contentsOf: rows)
        }
        return lines.joined(separator: "\n")
    }

    /// Pure: decide whether an element is worth surfacing, and its one-line label.
    /// Returns nil for non-actionable or disabled elements.
    nonisolated static func actionableLabel(role: String, title: String?, description: String?, value: String?, enabled: Bool) -> String? {
        let roles: Set<String> = [
            "AXButton", "AXMenuItem", "AXMenuButton", "AXPopUpButton",
            "AXCheckBox", "AXRadioButton", "AXLink",
            "AXTextField", "AXTextArea", "AXComboBox", "AXSearchField",
        ]
        guard roles.contains(role), enabled else { return nil }
        let raw = [title, description, value].compactMap { $0 }.first { !$0.isEmpty } ?? ""
        let label = raw.count > 60 ? String(raw.prefix(60)) + "…" : raw
        let shortRole = role.hasPrefix("AX") ? String(role.dropFirst(2)).lowercased() : role
        return label.isEmpty ? shortRole : "\(shortRole) \"\(label)\""
    }

    private func walk(_ element: AXUIElement, depth: Int, index: inout Int, rows: inout [String]) {
        if depth > maxDepth || rows.count >= maxElements { return }
        let role = copyString(element, kAXRoleAttribute) ?? ""
        if let label = Self.actionableLabel(
            role: role,
            title: copyString(element, kAXTitleAttribute),
            description: copyString(element, kAXDescriptionAttribute),
            value: copyString(element, kAXValueAttribute),
            enabled: copyBool(element, kAXEnabledAttribute) ?? true
        ) {
            let id = "e\(index)"
            elementsById[id] = element
            rows.append("\(id): \(label)")
            index += 1
        }
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                if rows.count >= maxElements { break }
                walk(child, depth: depth + 1, index: &index, rows: &rows)
            }
        }
    }

    private func focusedField() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let el = focused, CFGetTypeID(el) == AXUIElementGetTypeID() else { return nil }
        let element = el as! AXUIElement
        guard let role = copyString(element, kAXRoleAttribute) else { return nil }
        let value = copyString(element, kAXValueAttribute) ?? ""
        let short = value.count > 120 ? String(value.prefix(120)) + "…" : value
        return "\(role) = \"\(short)\""
    }

    private func copyString(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func copyBool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.boolValue
    }
}
