import AppKit
import Foundation

/// Finds the Chrome extension shipped inside the .app (mirrors
/// `LocalGemmaRuntimeLocator.findExecutable`): an env override for dev, else the
/// `Contents/Resources/BrowserExtension` folder embedded by the build script.
enum BrowserExtensionLocator {
    static func bundledURL() -> URL? {
        let fileManager = FileManager.default
        func hasManifest(_ url: URL) -> Bool {
            fileManager.fileExists(atPath: url.appendingPathComponent("manifest.json").path)
        }
        if let override = ProcessInfo.processInfo.environment["SUNIYE_BROWSER_EXTENSION_PATH"] {
            let url = URL(fileURLWithPath: override)
            if hasManifest(url) { return url }
        }
        if let resource = Bundle.main.resourceURL?.appendingPathComponent("BrowserExtension"), hasManifest(resource) {
            return resource
        }
        return nil
    }
}

/// Materializes a *paired, writable* copy of the extension: the bundled copy is
/// sealed by the app signature and must never be written to, so pairing copies it
/// OUT to Application Support and injects `pairing.json {port, token}` there. The
/// extension reads that file via `fetch(chrome.runtime.getURL('pairing.json'))`.
enum BrowserExtensionInstaller {
    /// The user-facing folder that gets loaded via chrome://extensions (load unpacked).
    static var installedURL: URL {
        appSupportDirectory().appendingPathComponent("BrowserExtension", isDirectory: true)
    }

    @discardableResult
    static func installPaired(port: UInt16, token: String) -> URL? {
        guard let source = BrowserExtensionLocator.bundledURL() else {
            AppLogger.shared.log(.warning, "browser extension not found (bundle or SUNIYE_BROWSER_EXTENSION_PATH)")
            return nil
        }
        let fileManager = FileManager.default
        let destination = installedURL
        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.copyItem(at: source, to: destination)
            let pairing: [String: Any] = ["port": Int(port), "token": token]
            let data = try JSONSerialization.data(withJSONObject: pairing, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: destination.appendingPathComponent("pairing.json"))
            AppLogger.shared.log(.info, "browser extension paired at \(destination.path) (port \(port))")
            return destination
        } catch {
            AppLogger.shared.log(.warning, "browser extension install failed: \(error)")
            return nil
        }
    }

    /// Reveals the installed folder in Finder + opens Chrome, for the load-unpacked flow.
    static func revealForInstall() {
        let folder = installedURL
        NSWorkspace.shared.selectFile(
            folder.appendingPathComponent("manifest.json").path,
            inFileViewerRootedAtPath: folder.path
        )
    }

    private static func appSupportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Suniye", isDirectory: true)
    }
}
