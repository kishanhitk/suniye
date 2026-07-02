import Foundation

/// Binds a Magic Format system prompt to a specific app, keyed by bundle ID.
struct AppPromptBinding: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var bundleID: String
    var appDisplayName: String
    var prompt: String

    enum CodingKeys: String, CodingKey {
        case id
        case bundleID
        case appDisplayName
        case prompt
    }

    init(id: UUID = UUID(), bundleID: String, appDisplayName: String, prompt: String) {
        self.id = id
        self.bundleID = bundleID
        self.appDisplayName = appDisplayName
        self.prompt = prompt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        bundleID = try container.decodeIfPresent(String.self, forKey: .bundleID) ?? ""
        appDisplayName = try container.decodeIfPresent(String.self, forKey: .appDisplayName) ?? ""
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? ""
    }
}

/// Candidate app offered in the per-app prompt picker.
struct AppPromptBindingCandidate: Identifiable, Equatable {
    var id: String { bundleID }
    let bundleID: String
    let appDisplayName: String
}

enum AppPromptResolver {
    /// Returns the binding matching the bundle ID, ignoring case and surrounding whitespace.
    static func binding(for bundleID: String?, in bindings: [AppPromptBinding]) -> AppPromptBinding? {
        guard let normalized = normalizedBundleID(bundleID) else {
            return nil
        }
        return bindings.first { normalizedBundleID($0.bundleID) == normalized }
    }

    /// Returns the per-app prompt override, or nil when the app is unbound or its prompt is blank.
    static func overridePrompt(for bundleID: String?, bindings: [AppPromptBinding]) -> String? {
        guard let binding = binding(for: bundleID, in: bindings) else {
            return nil
        }
        let prompt = binding.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return prompt.isEmpty ? nil : prompt
    }

    static func resolvedPrompt(for bundleID: String?, bindings: [AppPromptBinding], defaultPrompt: String) -> String {
        overridePrompt(for: bundleID, bindings: bindings) ?? defaultPrompt
    }

    static func normalizedBundleID(_ bundleID: String?) -> String? {
        guard let trimmed = bundleID?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed.lowercased()
    }
}
