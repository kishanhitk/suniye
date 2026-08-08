import ApplicationServices
import CoreGraphics
import Foundation

struct SystemComputerUseWindowInventory: ComputerUseWindowInventoryProviding {
    func onScreenWindows() throws -> [ComputerUseCGWindowSnapshot] {
        guard let descriptions = SuniyeCopyOnScreenWindowDescriptions() else {
            throw ComputerUseWindowInventoryError.windowListUnavailable
        }
        return descriptions.compactMap(ComputerUseWindowDescriptionDecoder.decode)
    }

    func accessibilityWindows(processIdentifier: Int32) throws
        -> [ComputerUseAXWindowSnapshot]
    {
        let application = AXUIElementCreateApplication(processIdentifier)
        let windows = try elements(attribute: kAXWindowsAttribute, from: application)
        let focusedWindow = element(attribute: kAXFocusedWindowAttribute, from: application)
        let mainWindow = element(attribute: kAXMainWindowAttribute, from: application)

        return windows.enumerated().map { ordinal, window in
            ComputerUseAXWindowSnapshot(
                ordinal: ordinal,
                title: string(attribute: kAXTitleAttribute, from: window),
                bounds: bounds(of: window),
                isFocused: focusedWindow.map { CFEqual(window, $0) } ?? false,
                isMain: mainWindow.map { CFEqual(window, $0) } ?? false
            )
        }
    }

    private func elements(attribute: String, from element: AXUIElement) throws
        -> [AXUIElement]
    {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success else {
            throw ComputerUseWindowInventoryError.accessibilityFailure(error.rawValue)
        }
        return (value as? [AXUIElement]) ?? []
    }

    private func element(attribute: String, from source: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(source, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private func string(attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func bounds(of element: AXUIElement) -> CGRect? {
        guard let position = point(attribute: kAXPositionAttribute, from: element),
              let size = size(attribute: kAXSizeAttribute, from: element) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func point(attribute: String, from element: AXUIElement) -> CGPoint? {
        guard let value = axValue(attribute: attribute, from: element),
              AXValueGetType(value) == .cgPoint else {
            return nil
        }
        var point = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &point) ? point : nil
    }

    private func size(attribute: String, from element: AXUIElement) -> CGSize? {
        guard let value = axValue(attribute: attribute, from: element),
              AXValueGetType(value) == .cgSize else {
            return nil
        }
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : nil
    }

    private func axValue(attribute: String, from element: AXUIElement) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        return (value as! AXValue)
    }
}
