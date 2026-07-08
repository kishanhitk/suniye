import AppKit
import ApplicationServices

/// The minimal facts the Increment-1 perception needs about the frontmost UI.
/// A later increment replaces this with a filtered, id-stamped tree walk.
protocol FrontmostContextProviding {
    var appName: String? { get }
    var focusedRoleAndValue: (role: String, value: String)? { get }
}

/// Increment-1 perception: frontmost app + focused element only.
struct AXScreenReader: ScreenReading {
    let context: FrontmostContextProviding

    init(context: FrontmostContextProviding = SystemFrontmostContext()) {
        self.context = context
    }

    func readScreen() async -> String {
        let app = context.appName ?? "unknown app"
        if let focus = context.focusedRoleAndValue {
            let value = focus.value.count > 200 ? String(focus.value.prefix(200)) + "…" : focus.value
            return "Frontmost app: \(app)\nFocused: \(focus.role) = \"\(value)\""
        }
        return "Frontmost app: \(app)\nNo focused text field."
    }
}

/// Real provider: NSWorkspace frontmost app + the system-wide focused element.
struct SystemFrontmostContext: FrontmostContextProviding {
    var appName: String? { NSWorkspace.shared.frontmostApplication?.localizedName }

    var focusedRoleAndValue: (role: String, value: String)? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused,
              CFGetTypeID(element) == AXUIElementGetTypeID() else { return nil }
        let axElement = element as! AXUIElement

        func string(_ attribute: String) -> String? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axElement, attribute as CFString, &value) == .success else { return nil }
            return value as? String
        }

        guard let role = string(kAXRoleAttribute as String) else { return nil }
        return (role, string(kAXValueAttribute as String) ?? "")
    }
}
