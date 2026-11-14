import AppKit

/// One app's share of dictation history, for the Transcripts header. The name is
/// resolved once when the ranking is built, not per read: an uninstalled app has
/// no honest name to show and has to be dropped *before* the ranking is cut to
/// three, or an installed app ranked fourth is lost with it.
struct DictationAppUsage: Identifiable, Equatable {
    let bundleID: String
    let count: Int
    let name: String

    var id: String { bundleID }

    static func resolvedName(for bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }
}
