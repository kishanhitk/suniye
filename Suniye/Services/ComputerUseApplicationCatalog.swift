import AppKit
import Foundation

final class SystemComputerUseApplicationCatalog: ComputerUseApplicationCatalog {
    private let runningApplicationsProvider: () -> [NSRunningApplication]
    private let installedApplicationURLsProvider: () -> [URL]

    init(
        runningApplicationsProvider: @escaping () -> [NSRunningApplication] = {
            NSWorkspace.shared.runningApplications
        },
        installedApplicationURLsProvider: @escaping () -> [URL] = {
            SystemComputerUseApplicationCatalog.defaultInstalledApplicationURLs()
        }
    ) {
        self.runningApplicationsProvider = runningApplicationsProvider
        self.installedApplicationURLsProvider = installedApplicationURLsProvider
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

    func resolveApplication(identifier: String) -> ComputerUseApplication? {
        let applications = listAvailableApplications()
        return applications.first { application in
            application.id == identifier
                || application.bundleIdentifier == identifier
                || application.displayName.localizedCaseInsensitiveCompare(identifier) == .orderedSame
        }
    }

    func activeApplication() -> ComputerUseApplication? {
        let applications = listApplications()
        return applications.first(where: \.isActive)
    }

    func listAvailableApplications() -> [ComputerUseApplication] {
        let running = listApplications()
        let runningBundleIdentifiers = Set(running.map(\.bundleIdentifier))
        var seenBundleIdentifiers = runningBundleIdentifiers
        let installed = installedApplicationURLsProvider()
            .compactMap(Self.makeInstalledApplication)
            .filter { seenBundleIdentifiers.insert($0.bundleIdentifier).inserted }

        return (running + installed).sorted { lhs, rhs in
            if lhs.isRunning != rhs.isRunning {
                return lhs.isRunning && !rhs.isRunning
            }
            if lhs.isActive != rhs.isActive {
                return lhs.isActive && !rhs.isActive
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    func launchApplication(identifier: String) async -> ComputerUseApplication? {
        guard let candidate = resolveApplication(identifier: identifier) else {
            return nil
        }
        guard !candidate.isRunning else {
            return candidate
        }
        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: candidate.bundleIdentifier
        ) else {
            return nil
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        let launchedApplication = await withCheckedContinuation { continuation in
            NSWorkspace.shared.openApplication(
                at: applicationURL,
                configuration: configuration
            ) { application, _ in
                continuation.resume(returning: application)
            }
        }

        return launchedApplication.flatMap(Self.makeApplication)
            ?? listApplications().first { $0.bundleIdentifier == candidate.bundleIdentifier }
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
            isActive: application.isActive
        )
    }

    static func applicationID(bundleIdentifier: String, processIdentifier _: Int32) -> String {
        bundleIdentifier
    }

    private static func makeInstalledApplication(_ url: URL) -> ComputerUseApplication? {
        guard let bundle = Bundle(url: url),
              let bundleIdentifier = bundle.bundleIdentifier,
              !bundleIdentifier.isEmpty else {
            return nil
        }
        let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? bundleIdentifier

        return ComputerUseApplication(
            id: bundleIdentifier,
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            processIdentifier: 0,
            isRunning: false,
            isActive: false
        )
    }

    static func defaultInstalledApplicationURLs() -> [URL] {
        let fileManager = FileManager.default
        let directories = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Library/CoreServices"),
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications"),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]

        return directories.flatMap { directory in
            (try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
        }.filter { $0.pathExtension == "app" }
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
        let appIsFrontmost = frontmostProcessIdentifierProvider() == application.processIdentifier

        return orderedWindows.enumerated().map { index, window in
            ComputerUseWindow(
                id: window.id,
                title: window.title,
                ownerProcessIdentifier: window.ownerProcessIdentifier,
                bounds: window.bounds,
                layer: window.layer,
                isOnScreen: window.isOnScreen,
                // CGWindowList returns front-to-back ordering for this query.
                // AX remains the source of truth when the observation service
                // resolves the window.
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
