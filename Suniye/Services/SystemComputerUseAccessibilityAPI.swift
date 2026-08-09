import ApplicationServices
import Foundation

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

    private static func axValue(_ attribute: String, from element: AXUIElement) -> AXValue? {
        guard let value = copied(attribute, from: element),
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        return unsafeBitCast(value, to: AXValue.self)
    }
}
