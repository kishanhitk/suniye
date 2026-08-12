import ApplicationServices
import Foundation

struct ComputerUseAccessibilityActionDescriptor: Equatable, Sendable {
    let rawName: String
    let exposedName: String
}

enum ComputerUsePrimaryClickOperation: Equatable {
    case pick
    case press
}

enum ComputerUseAccessibilityActionResolver {
    static let pickAction = "AXPick"

    private static let canonicalNames = [
        "AXScrollDownByPage": "Scroll Down",
        "AXScrollLeftByPage": "Scroll Left",
        "AXScrollRightByPage": "Scroll Right",
        "AXScrollUpByPage": "Scroll Up",
    ]

    static func descriptor(rawName: String, description: String?)
        -> ComputerUseAccessibilityActionDescriptor
    {
        let exposedName = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ComputerUseAccessibilityActionDescriptor(
            rawName: rawName,
            exposedName: canonicalNames[rawName]
                ?? exposedName.flatMap { $0.isEmpty ? nil : $0 }
                ?? rawName
        )
    }

    static func rawName(
        exposedName: String,
        descriptors: [ComputerUseAccessibilityActionDescriptor]
    ) -> String? {
        let matches = descriptors.filter { $0.exposedName == exposedName }
        return matches.count == 1 ? matches[0].rawName : nil
    }

    static func primaryClickOperations(clickCount: Int) -> [ComputerUsePrimaryClickOperation] {
        clickCount == 1 ? [.pick, .press] : []
    }
}

enum SystemComputerUseAccessibilityAPI {
    static func copy(
        _ attribute: String,
        from element: AXUIElement
    ) -> (error: AXError, value: CFTypeRef?) {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return (error, value)
    }

    static func copied(_ attribute: String, from element: AXUIElement) -> CFTypeRef? {
        let result = copy(attribute, from: element)
        return result.error == .success ? result.value : nil
    }

    static func elements(_ attribute: String, from element: AXUIElement) -> [AXUIElement]? {
        guard let value = copied(attribute, from: element) else {
            return nil
        }
        return elements(from: value)
    }

    static func applicationWindows(from application: AXUIElement)
        -> (error: AXError, value: CFTypeRef?)
    {
        let result = copy(kAXWindowsAttribute, from: application)
        guard result.error == .success else {
            return result
        }
        guard elements(from: result.value).isEmpty else {
            return result
        }

        var windows: [AXUIElement] = []
        for attribute in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
            guard let window = element(attribute, from: application),
                  !windows.contains(where: { CFEqual($0, window) }) else {
                continue
            }
            windows.append(window)
        }
        return (.success, windows as CFArray)
    }

    static func elements(from value: CFTypeRef?) -> [AXUIElement] {
        guard let values = value as? [AnyObject] else {
            return []
        }
        return values.compactMap(element(from:))
    }

    static func element(_ attribute: String, from source: AXUIElement) -> AXUIElement? {
        element(from: copied(attribute, from: source))
    }

    static func element(from value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    static func string(_ attribute: String, from element: AXUIElement) -> String? {
        copied(attribute, from: element) as? String
    }

    static func boolean(_ attribute: String, from element: AXUIElement) -> Bool? {
        (copied(attribute, from: element) as? NSNumber)?.boolValue
    }

    static func point(_ attribute: String, from element: AXUIElement) -> CGPoint? {
        guard let value = axValue(attribute, from: element),
              AXValueGetType(value) == .cgPoint else {
            return nil
        }
        var point = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &point) ? point : nil
    }

    static func size(_ attribute: String, from element: AXUIElement) -> CGSize? {
        guard let value = axValue(attribute, from: element),
              AXValueGetType(value) == .cgSize else {
            return nil
        }
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : nil
    }

    static func actionNames(from element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else {
            return []
        }
        return names as? [String] ?? []
    }

    static func actions(from element: AXUIElement) -> [ComputerUseAccessibilityActionDescriptor] {
        actionNames(from: element).map { rawName in
            ComputerUseAccessibilityActionResolver.descriptor(
                rawName: rawName,
                description: actionDescription(rawName, from: element)
            )
        }
    }

    private static func actionDescription(_ action: String, from element: AXUIElement) -> String? {
        var description: CFString?
        guard AXUIElementCopyActionDescription(
            element,
            action as CFString,
            &description
        ) == .success else {
            return nil
        }
        return description as String?
    }

    private static func axValue(_ attribute: String, from element: AXUIElement) -> AXValue? {
        guard let value = copied(attribute, from: element),
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        return unsafeBitCast(value, to: AXValue.self)
    }
}
