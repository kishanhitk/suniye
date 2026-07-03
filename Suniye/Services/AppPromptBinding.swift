import AppKit

/// Binds Magic Format app-specific instructions to an app, keyed by bundle ID.
struct AppPromptBinding: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var bundleID: String
    var appDisplayName: String
    var prompt: String
}

/// Candidate app offered in the per-app prompt picker.
struct AppPromptBindingCandidate: Identifiable, Equatable, Sendable {
    var id: String { bundleID }
    let bundleID: String
    let appDisplayName: String
}

enum AppPromptResolver {
    /// Trimmed bundle ID, or nil when empty. Bindings store this normalized form.
    static func normalizedBundleID(_ bundleID: String?) -> String? {
        guard let trimmed = bundleID?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    /// Single matching rule for bundle IDs everywhere: trimmed, case-insensitive.
    static func matches(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs = normalizedBundleID(lhs), let rhs = normalizedBundleID(rhs) else {
            return false
        }
        return lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }

    static func binding(for bundleID: String?, in bindings: [AppPromptBinding]) -> AppPromptBinding? {
        bindings.first { matches($0.bundleID, bundleID) }
    }

    /// Returns the per-app additional instructions, or nil when the app is unbound or its prompt is blank.
    static func additionalInstructions(for bundleID: String?, bindings: [AppPromptBinding]) -> String? {
        guard let binding = binding(for: bundleID, in: bindings) else {
            return nil
        }
        let prompt = binding.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return prompt.isEmpty ? nil : prompt
    }
}

/// Discovers apps offered by the per-app prompt picker.
enum AppPromptBindingCandidates {
    @MainActor
    static func running(excluding bindings: [AppPromptBinding]) -> [AppPromptBindingCandidate] {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .map { (bundleID: $0.bundleIdentifier, name: $0.localizedName) }
        return candidates(from: apps, excluding: bindings, ownBundleID: Bundle.main.bundleIdentifier)
    }

    /// Reads the app bundle off the main thread; Bundle lookups touch disk.
    static func forApplication(at url: URL, ownBundleID: String? = Bundle.main.bundleIdentifier) async -> AppPromptBindingCandidate? {
        await Task.detached(priority: .userInitiated) {
            resolveApplication(at: url, ownBundleID: ownBundleID)
        }.value
    }

    private static func resolveApplication(at url: URL, ownBundleID: String?) -> AppPromptBindingCandidate? {
        guard let bundle = Bundle(url: url),
              let bundleID = AppPromptResolver.normalizedBundleID(bundle.bundleIdentifier),
              !AppPromptResolver.matches(bundleID, ownBundleID) else {
            return nil
        }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return AppPromptBindingCandidate(bundleID: bundleID, appDisplayName: name)
    }

    /// Pure filter over (bundleID, name) pairs so candidate discovery is unit-testable.
    static func candidates(
        from apps: [(bundleID: String?, name: String?)],
        excluding bindings: [AppPromptBinding],
        ownBundleID: String?
    ) -> [AppPromptBindingCandidate] {
        var seen = Set<String>()
        var result: [AppPromptBindingCandidate] = []
        for app in apps {
            guard let bundleID = AppPromptResolver.normalizedBundleID(app.bundleID),
                  !AppPromptResolver.matches(bundleID, ownBundleID),
                  AppPromptResolver.binding(for: bundleID, in: bindings) == nil,
                  seen.insert(bundleID).inserted else {
                continue
            }
            result.append(AppPromptBindingCandidate(bundleID: bundleID, appDisplayName: app.name ?? bundleID))
        }
        return result.sorted { $0.appDisplayName.localizedCaseInsensitiveCompare($1.appDisplayName) == .orderedAscending }
    }
}
