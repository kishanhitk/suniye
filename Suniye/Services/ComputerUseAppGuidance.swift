import Foundation

/// Per-app navigation hints prepended to the first observation of an app in a
/// run. Mirrors the reference's `appSpecificInstructions`: a complex app's
/// Accessibility tree alone does not reveal how to navigate it, so a short
/// note (which control drives navigation, where to search) keeps the model out
/// of coordinate-clicking loops. Hints are advisory and never override the
/// observed state.
protocol ComputerUseAppGuidanceProviding: Sendable {
    /// Guidance for an app, or nil when none applies. Matched by bundle
    /// identifier first, then case-insensitive display name.
    func instructions(bundleIdentifier: String?, displayName: String) -> String?
}

struct ComputerUseAppGuidance: ComputerUseAppGuidanceProviding {
    func instructions(bundleIdentifier: String?, displayName: String) -> String? {
        if let bundleIdentifier,
           let byBundle = Self.hints[bundleIdentifier.lowercased()] {
            return byBundle
        }
        return Self.hints[displayName.lowercased()]
    }

    /// Keyed by lowercased bundle identifier and lowercased display name so
    /// either resolves. Keep each hint short and navigation-focused.
    private static let hints: [String: String] = {
        var hints: [String: String] = [:]

        let systemSettings = """
        System Settings has a scrollable sidebar of panes on the left and the \
        selected pane's controls on the right. To reach a pane, first type its \
        name into the sidebar search field at the top of the sidebar, then click \
        the matching result, rather than scrolling or guessing coordinates. \
        Battery health is under Battery (open it, then the Battery Health info \
        button). The macOS version is under General, then About. Confirm the \
        pane title changed in a fresh observation before reading values.
        """
        for key in ["com.apple.systempreferences", "system settings", "system preferences"] {
            hints[key] = systemSettings
        }

        return hints
    }()
}
