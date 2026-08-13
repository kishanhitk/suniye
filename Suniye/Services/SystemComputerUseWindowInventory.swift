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

    func allWindows() throws -> [ComputerUseCGWindowSnapshot] {
        guard let descriptions = SuniyeCopyAllWindowDescriptions() else {
            throw ComputerUseWindowInventoryError.windowListUnavailable
        }
        return descriptions.compactMap(ComputerUseWindowDescriptionDecoder.decode)
    }

    func accessibilityWindows(processIdentifier: Int32) throws
        -> [ComputerUseAXWindowSnapshot]
    {
        let application = AXUIElementCreateApplication(processIdentifier)
        let windows = try requiredApplicationWindows(from: application)
        let focusedWindow = SystemComputerUseAccessibilityAPI.element(
            kAXFocusedWindowAttribute,
            from: application
        )
        let mainWindow = SystemComputerUseAccessibilityAPI.element(
            kAXMainWindowAttribute,
            from: application
        )

        return windows.enumerated().map { ordinal, window in
            ComputerUseAXWindowSnapshot(
                ordinal: ordinal,
                title: SystemComputerUseAccessibilityAPI.string(kAXTitleAttribute, from: window),
                bounds: bounds(of: window),
                isFocused: focusedWindow.map { CFEqual(window, $0) } ?? false,
                isMain: mainWindow.map { CFEqual(window, $0) } ?? false
            )
        }
    }

    private func requiredApplicationWindows(from application: AXUIElement) throws
        -> [AXUIElement]
    {
        let result = SystemComputerUseAccessibilityAPI.applicationWindowElements(
            from: application
        )
        guard result.error == .success else {
            throw ComputerUseWindowInventoryError.accessibilityFailure(result.error.rawValue)
        }
        return result.windows
    }

    private func bounds(of element: AXUIElement) -> CGRect? {
        guard let position = SystemComputerUseAccessibilityAPI.point(
            kAXPositionAttribute,
            from: element
        ),
            let size = SystemComputerUseAccessibilityAPI.size(kAXSizeAttribute, from: element) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }
}
