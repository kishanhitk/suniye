import AppKit

/// Bundle ID → app icon, resolved once.
///
/// Misses are cached too, so an uninstalled app is not re-queried per frame.
@MainActor
final class AppIconCache {
    static let shared = AppIconCache()

    private var icons: [String: NSImage?] = [:]

    func icon(for bundleID: String) -> NSImage? {
        if let cached = icons[bundleID] {
            return cached
        }
        let icon = Self.launchServicesIcon(for: bundleID)
        icons[bundleID] = icon
        return icon
    }

    private static func launchServicesIcon(for bundleID: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}
