import CoreGraphics
import Foundation

struct ComputerUseCGWindowSnapshot: Equatable, Sendable {
    let id: UInt32
    let ownerProcessIdentifier: Int32
    let title: String?
    let bounds: CGRect
    let layer: Int
    let isOnScreen: Bool
}

struct ComputerUseAXWindowSnapshot: Equatable, Sendable {
    let ordinal: Int
    let title: String?
    let bounds: CGRect?
    let isFocused: Bool
    let isMain: Bool
}

struct ComputerUseWindow: Equatable, Sendable {
    let id: UInt32
    let ownerProcessIdentifier: Int32
    let title: String?
    let bounds: CGRect
    let layer: Int
    let isOnScreen: Bool
    let accessibilityOrdinal: Int
    let isFocused: Bool
    let isMain: Bool
}

protocol ComputerUseWindowInventoryProviding: Sendable {
    func onScreenWindows() throws -> [ComputerUseCGWindowSnapshot]
    func accessibilityWindows(processIdentifier: Int32) throws
        -> [ComputerUseAXWindowSnapshot]
}

actor ComputerUseWindowDiscovery {
    private let inventory: ComputerUseWindowInventoryProviding

    init(inventory: ComputerUseWindowInventoryProviding = SystemComputerUseWindowInventory()) {
        self.inventory = inventory
    }

    func orderedWindows(processIdentifier: Int32) throws -> [ComputerUseWindow] {
        let cgWindows = try inventory.onScreenWindows().filter {
            $0.ownerProcessIdentifier == processIdentifier
                && $0.isOnScreen
                && !$0.bounds.isEmpty
        }
        let axWindows = try inventory.accessibilityWindows(
            processIdentifier: processIdentifier
        )
        return ComputerUseWindowMatcher.match(cgWindows: cgWindows, axWindows: axWindows)
    }
}

enum ComputerUseWindowMatcher {
    private static let coordinateTolerance: CGFloat = 2

    static func match(
        cgWindows: [ComputerUseCGWindowSnapshot],
        axWindows: [ComputerUseAXWindowSnapshot]
    ) -> [ComputerUseWindow] {
        var unusedAXWindows = axWindows
        return cgWindows.compactMap { cgWindow in
            guard let matchIndex = unusedAXWindows.firstIndex(where: {
                matches(cgWindow: cgWindow, axWindow: $0)
            }) else {
                return nil
            }
            let axWindow = unusedAXWindows.remove(at: matchIndex)
            return ComputerUseWindow(
                id: cgWindow.id,
                ownerProcessIdentifier: cgWindow.ownerProcessIdentifier,
                title: cgWindow.title ?? axWindow.title,
                bounds: cgWindow.bounds,
                layer: cgWindow.layer,
                isOnScreen: cgWindow.isOnScreen,
                accessibilityOrdinal: axWindow.ordinal,
                isFocused: axWindow.isFocused,
                isMain: axWindow.isMain
            )
        }
    }

    private static func matches(
        cgWindow: ComputerUseCGWindowSnapshot,
        axWindow: ComputerUseAXWindowSnapshot
    ) -> Bool {
        let cgTitle = normalizedTitle(cgWindow.title)
        let axTitle = normalizedTitle(axWindow.title)
        if let cgTitle, let axTitle, cgTitle != axTitle {
            return false
        }
        if let axBounds = axWindow.bounds {
            return approximatelyEqual(cgWindow.bounds, axBounds)
        }
        return cgTitle != nil && cgTitle == axTitle
    }

    private static func normalizedTitle(_ title: String?) -> String? {
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return nil
        }
        return title
    }

    private static func approximatelyEqual(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= coordinateTolerance
            && abs(lhs.origin.y - rhs.origin.y) <= coordinateTolerance
            && abs(lhs.size.width - rhs.size.width) <= coordinateTolerance
            && abs(lhs.size.height - rhs.size.height) <= coordinateTolerance
    }
}

enum ComputerUseWindowDescriptionDecoder {
    static func decode(_ description: [String: Any]) -> ComputerUseCGWindowSnapshot? {
        guard let id = number(kCGWindowNumber, in: description)?.uint32Value,
              let processIdentifier = number(kCGWindowOwnerPID, in: description)?.int32Value,
              let boundsValues = description[kCGWindowBounds as String] as? [String: NSNumber],
              let layer = number(kCGWindowLayer, in: description)?.intValue else {
            return nil
        }
        let title = (description[kCGWindowName as String] as? String).flatMap {
            $0.isEmpty ? nil : $0
        }
        return ComputerUseCGWindowSnapshot(
            id: id,
            ownerProcessIdentifier: processIdentifier,
            title: title,
            bounds: CGRect(
                x: boundsValues["X"]?.doubleValue ?? 0,
                y: boundsValues["Y"]?.doubleValue ?? 0,
                width: boundsValues["Width"]?.doubleValue ?? 0,
                height: boundsValues["Height"]?.doubleValue ?? 0
            ),
            layer: layer,
            isOnScreen: number(kCGWindowIsOnscreen, in: description)?.boolValue ?? true
        )
    }

    private static func number(_ key: CFString, in description: [String: Any]) -> NSNumber? {
        description[key as String] as? NSNumber
    }
}

enum ComputerUseWindowInventoryError: LocalizedError, Equatable, Sendable {
    case windowListUnavailable
    case accessibilityFailure(Int32)

    var errorDescription: String? {
        switch self {
        case .windowListUnavailable:
            "Could not read the on-screen window list."
        case let .accessibilityFailure(code):
            "Could not read application windows (Accessibility error \(code))."
        }
    }
}
