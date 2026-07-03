import XCTest
@testable import Suniye

final class AppPromptBindingTests: XCTestCase {
    private let bindings = [
        AppPromptBinding(bundleID: "com.tinyspeck.slackmacgap", appDisplayName: "Slack", prompt: "Keep it terse."),
        AppPromptBinding(bundleID: "com.apple.Notes", appDisplayName: "Notes", prompt: "Write full prose.")
    ]

    func testAdditionalInstructionsReturnsBoundPrompt() {
        let prompt = AppPromptResolver.additionalInstructions(for: "com.tinyspeck.slackmacgap", bindings: bindings)
        XCTAssertEqual(prompt, "Keep it terse.")
    }

    func testAdditionalInstructionsIsNilForUnboundBundleID() {
        XCTAssertNil(AppPromptResolver.additionalInstructions(for: "com.apple.mail", bindings: bindings))
    }

    func testAdditionalInstructionsIsNilForNilOrEmptyBundleID() {
        XCTAssertNil(AppPromptResolver.additionalInstructions(for: nil, bindings: bindings))
        XCTAssertNil(AppPromptResolver.additionalInstructions(for: "   ", bindings: bindings))
    }

    func testAdditionalInstructionsMatchesCaseInsensitivelyAndTrims() {
        let prompt = AppPromptResolver.additionalInstructions(for: "  COM.APPLE.NOTES ", bindings: bindings)
        XCTAssertEqual(prompt, "Write full prose.")
    }

    func testAdditionalInstructionsIsNilForWhitespaceOnlyBindingPrompt() {
        let blank = [AppPromptBinding(bundleID: "com.apple.Notes", appDisplayName: "Notes", prompt: "  \n ")]
        XCTAssertNil(AppPromptResolver.additionalInstructions(for: "com.apple.Notes", bindings: blank))
    }

    func testBindingCodableRoundTrip() throws {
        let encoded = try JSONEncoder().encode(bindings)
        let decoded = try JSONDecoder().decode([AppPromptBinding].self, from: encoded)
        XCTAssertEqual(decoded, bindings)
    }

    func testLLMSettingsRoundTripsBindings() throws {
        var settings = LLMSettings()
        settings.appPromptBindings = bindings

        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(LLMSettings.self, from: encoded)
        XCTAssertEqual(decoded.appPromptBindings, bindings)
    }

    func testLLMSettingsWithoutBindingsKeyDecodesToEmptyList() throws {
        let legacyJSON = #"{"isEnabled": true}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(LLMSettings.self, from: legacyJSON)
        XCTAssertEqual(decoded.appPromptBindings, [])
    }

    func testLLMSettingsStoreRoundTripsBindings() {
        let suite = "dev.suniye.tests.apppromptbindings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LLMSettingsStore(userDefaults: defaults, storageKey: "llm")

        var settings = LLMSettings()
        settings.appPromptBindings = bindings
        store.save(settings)

        XCTAssertEqual(store.load().appPromptBindings, bindings)
    }

    /// Pins the complete set of prompt surfaces that reach providers: app-specific
    /// instructions must append to the base, apple, and gemma prompts.
    func testAppendingAppInstructionsAddsSectionToAllProviderPrompts() {
        let settings = LLMSettings(
            baseSystemPrompt: "BASE_SENTINEL",
            appleSystemPrompt: "APPLE_SENTINEL",
            gemmaSystemPrompt: "GEMMA_SENTINEL",
            systemPrompt: "USER_SENTINEL"
        )
        let appended = settings.appendingAppInstructions("Keep it terse.")

        XCTAssertEqual(
            appended.composedSystemPrompt,
            "BASE_SENTINEL\n\nUser customization:\nUSER_SENTINEL\n\nApp-specific instructions:\nKeep it terse."
        )
        XCTAssertEqual(
            appended.composedAppleSystemPrompt,
            "APPLE_SENTINEL\n\nApp-specific instructions:\nKeep it terse."
        )
        XCTAssertEqual(
            appended.composedGemmaSystemPrompt,
            "GEMMA_SENTINEL\n\nApp-specific instructions:\nKeep it terse."
        )
    }

    // MARK: - Candidate discovery

    func testCandidatesExcludeBoundOwnUnidentifiedAndDuplicateApps() {
        let apps: [(bundleID: String?, name: String?)] = [
            ("com.tinyspeck.slackmacgap", "Slack"),
            ("com.apple.mail", "Mail"),
            ("com.apple.mail", "Mail"),
            ("dev.suniye.app", "Suniye"),
            (nil, "Anonymous"),
            ("  ", "Blank")
        ]

        let candidates = AppPromptBindingCandidates.candidates(
            from: apps,
            excluding: bindings,
            ownBundleID: "dev.suniye.app"
        )

        XCTAssertEqual(candidates, [AppPromptBindingCandidate(bundleID: "com.apple.mail", appDisplayName: "Mail")])
    }

    func testCandidatesSortByDisplayNameAndFallBackToBundleID() {
        let apps: [(bundleID: String?, name: String?)] = [
            ("com.z.app", "Zed"),
            ("com.a.app", nil),
            ("com.m.app", "Mail")
        ]

        let candidates = AppPromptBindingCandidates.candidates(from: apps, excluding: [], ownBundleID: nil)

        XCTAssertEqual(candidates.map(\.appDisplayName), ["com.a.app", "Mail", "Zed"])
    }

    func testForApplicationExcludesOwnBundle() async {
        let candidate = await AppPromptBindingCandidates.forApplication(at: Bundle.main.bundleURL, ownBundleID: Bundle.main.bundleIdentifier)
        XCTAssertNil(candidate)
    }

    func testForApplicationResolvesBundleIDAndName() async throws {
        let url = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path))

        let candidate = await AppPromptBindingCandidates.forApplication(at: url, ownBundleID: "dev.suniye.app")

        XCTAssertEqual(candidate?.bundleID.lowercased(), "com.apple.calculator")
        XCTAssertFalse(candidate?.appDisplayName.isEmpty ?? true)
    }
}
