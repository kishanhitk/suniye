import AppKit

/// Bundle ID → app icon, resolved once.
///
/// Misses are cached too, so an uninstalled app is not re-queried per frame.
@MainActor
final class AppIconCache {
    static let shared = AppIconCache()

    private let resolve: (String) -> NSImage?
    private var icons: [String: NSImage?] = [:]
    private(set) var resolveCount = 0

    init(resolve: @escaping (String) -> NSImage? = AppIconCache.launchServicesIcon) {
        self.resolve = resolve
    }

    func icon(for bundleID: String) -> NSImage? {
        if let cached = icons[bundleID] {
            return cached
        }
        resolveCount += 1
        let icon = resolve(bundleID)
        icons[bundleID] = icon
        return icon
    }

    static func launchServicesIcon(for bundleID: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}
