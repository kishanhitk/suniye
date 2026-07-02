import XCTest
@testable import Suniye

final class AppPromptBindingTests: XCTestCase {
    private let bindings = [
        AppPromptBinding(bundleID: "com.tinyspeck.slackmacgap", appDisplayName: "Slack", prompt: "Keep it terse."),
        AppPromptBinding(bundleID: "com.apple.Notes", appDisplayName: "Notes", prompt: "Write full prose.")
    ]

    func testOverridePromptReturnsBoundPrompt() {
        let prompt = AppPromptResolver.overridePrompt(for: "com.tinyspeck.slackmacgap", bindings: bindings)
        XCTAssertEqual(prompt, "Keep it terse.")
    }

    func testOverridePromptIsNilForUnboundBundleID() {
        XCTAssertNil(AppPromptResolver.overridePrompt(for: "com.apple.mail", bindings: bindings))
    }

    func testOverridePromptIsNilForNilOrEmptyBundleID() {
        XCTAssertNil(AppPromptResolver.overridePrompt(for: nil, bindings: bindings))
        XCTAssertNil(AppPromptResolver.overridePrompt(for: "   ", bindings: bindings))
    }

    func testOverridePromptMatchesCaseInsensitivelyAndTrims() {
        let prompt = AppPromptResolver.overridePrompt(for: "  COM.APPLE.NOTES ", bindings: bindings)
        XCTAssertEqual(prompt, "Write full prose.")
    }

    func testOverridePromptIgnoresWhitespaceOnlyBindingPrompt() {
        let blank = [AppPromptBinding(bundleID: "com.apple.Notes", appDisplayName: "Notes", prompt: "  \n ")]
        XCTAssertNil(AppPromptResolver.overridePrompt(for: "com.apple.Notes", bindings: blank))
        XCTAssertEqual(
            AppPromptResolver.resolvedPrompt(for: "com.apple.Notes", bindings: blank, defaultPrompt: "default"),
            "default"
        )
    }

    func testResolvedPromptPrefersBindingOverDefault() {
        XCTAssertEqual(
            AppPromptResolver.resolvedPrompt(for: "com.tinyspeck.slackmacgap", bindings: bindings, defaultPrompt: "default"),
            "Keep it terse."
        )
        XCTAssertEqual(
            AppPromptResolver.resolvedPrompt(for: "com.apple.mail", bindings: bindings, defaultPrompt: "default"),
            "default"
        )
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
}
