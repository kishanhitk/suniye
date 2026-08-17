import AppKit

/// Bundle ID → app icon, resolved once.
///
/// The transcript row used to ask Launch Services on every body evaluation —
/// measured at ~1.35 ms per lookup against a 0.01 ms cache hit — and a
/// scrolling LazyVStack re-evaluates dozens of rows a frame (KIS-203).
///
/// Misses are cached too, so an uninstalled app is not re-queried per frame.
/// The resolver is injectable so the caching itself can be tested without
/// Launch Services.
@MainActor
final class AppIconCache {
    static let shared = AppIconCache()

    private let resolve: (String) -> NSImage?
    private var icons: [String: NSImage?] = [:]
    /// How many times the resolver actually ran. Only for tests, which is why
    /// it is not exposed on the shared instance's public surface beyond this.
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
