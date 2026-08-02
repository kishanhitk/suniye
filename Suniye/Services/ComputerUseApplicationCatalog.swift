import AppKit
import Foundation

final class SystemComputerUseApplicationCatalog: ComputerUseApplicationCatalog {
    private let runningApplicationsProvider: () -> [NSRunningApplication]

    init(
        runningApplicationsProvider: @escaping () -> [NSRunningApplication] = {
            NSWorkspace.shared.runningApplications
        }
    ) {
        self.runningApplicationsProvider = runningApplicationsProvider
    }

    func listApplications() -> [ComputerUseApplication] {
        runningApplicationsProvider()
            .compactMap(Self.makeApplication)
            .sorted { lhs, rhs in
                if lhs.isActive != rhs.isActive {
                    return lhs.isActive && !rhs.isActive
                }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    func application(withID identifier: String) -> ComputerUseApplication? {
        listApplications().first { $0.id == identifier }
    }

    private static func makeApplication(_ application: NSRunningApplication) -> ComputerUseApplication? {
        guard let bundleIdentifier = application.bundleIdentifier,
              !application.isTerminated,
              application.activationPolicy != .prohibited else {
            return nil
        }

        return ComputerUseApplication(
            id: Self.applicationID(
                bundleIdentifier: bundleIdentifier,
                processIdentifier: application.processIdentifier
            ),
            bundleIdentifier: bundleIdentifier,
            displayName: application.localizedName ?? bundleIdentifier,
            processIdentifier: application.processIdentifier,
            isRunning: true,
            isActive: application.isActive,
            launchDate: application.launchDate
        )
    }

    static func applicationID(bundleIdentifier: String, processIdentifier: Int32) -> String {
        "\(bundleIdentifier)#\(processIdentifier)"
    }
}

final class SystemComputerUseWindowDiscovery: ComputerUseWindowDiscovering {
    private let windowInfoProvider: () -> [[String: Any]]
    private let frontmostProcessIdentifierProvider: () -> Int32?

    init(
        windowInfoProvider: @escaping () -> [[String: Any]] = {
            CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]] ?? []
        },
        frontmostProcessIdentifierProvider: @escaping () -> Int32? = {
            NSWorkspace.shared.frontmostApplication?.processIdentifier
        }
    ) {
        self.windowInfoProvider = windowInfoProvider
        self.frontmostProcessIdentifierProvider = frontmostProcessIdentifierProvider
    }

    func listWindows(for application: ComputerUseApplication) -> [ComputerUseWindow] {
        let windows = windowInfoProvider().compactMap { info -> ComputerUseWindow? in
            guard numberValue(info[kCGWindowOwnerPID as String])?.int32Value == application.processIdentifier,
                  let windowID = numberValue(info[kCGWindowNumber as String])?.uint32Value,
                  let bounds = Self.rect(from: info[kCGWindowBounds as String]),
                  !bounds.isEmpty,
                  let layer = numberValue(info[kCGWindowLayer as String])?.intValue,
                  layer == 0 else {
                return nil
            }

            let title = (info[kCGWindowName as String] as? String).flatMap { value in
                value.isEmpty ? nil : value
            }
            let isOnScreen = (info[kCGWindowIsOnscreen as String] as? Bool) ?? true

            return ComputerUseWindow(
                id: windowID,
                title: title,
                ownerProcessIdentifier: application.processIdentifier,
                bounds: ComputerUseRect(bounds),
                layer: layer,
                isOnScreen: isOnScreen,
                isKeyWindow: false
            )
        }

        let orderedWindows = windows.filter(\.isOnScreen)
        let appIsFrontmost = application.isActive
            || frontmostProcessIdentifierProvider() == application.processIdentifier

        return orderedWindows.enumerated().map { index, window in
            ComputerUseWindow(
                id: window.id,
                title: window.title,
                ownerProcessIdentifier: window.ownerProcessIdentifier,
                bounds: window.bounds,
                layer: window.layer,
                isOnScreen: window.isOnScreen,
                // CGWindowList returns front-to-back ordering for this query.
                // This is a fallback marker. AX remains the source of truth
                // when the observation service resolves the window.
                isKeyWindow: appIsFrontmost && index == 0
            )
        }
    }

    private func numberValue(_ value: Any?) -> NSNumber? {
        value as? NSNumber
    }

    private static func rect(from value: Any?) -> CGRect? {
        if let values = value as? [String: CGFloat] {
            return CGRect(
                x: values["X"] ?? 0,
                y: values["Y"] ?? 0,
                width: values["Width"] ?? 0,
                height: values["Height"] ?? 0
            )
        }

        if let values = value as? [String: NSNumber] {
            return CGRect(
                x: values["X"]?.doubleValue ?? 0,
                y: values["Y"]?.doubleValue ?? 0,
                width: values["Width"]?.doubleValue ?? 0,
                height: values["Height"]?.doubleValue ?? 0
            )
        }

        if let values = value as? [String: Any] {
            return CGRect(
                x: (values["X"] as? NSNumber)?.doubleValue ?? 0,
                y: (values["Y"] as? NSNumber)?.doubleValue ?? 0,
                width: (values["Width"] as? NSNumber)?.doubleValue ?? 0,
                height: (values["Height"] as? NSNumber)?.doubleValue ?? 0
            )
        }

        return nil
    }
}
