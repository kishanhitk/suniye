import AppKit
import XCTest
@testable import Suniye

@MainActor
final class AppPromptBindingMoreTests: XCTestCase {
    func testCandidateIdentityIsItsBundleID() {
        let candidate = AppPromptBindingCandidate(bundleID: "com.example.app", appDisplayName: "Example")

        XCTAssertEqual(candidate.id, "com.example.app")
    }

    func testRunningCandidatesExcludeOwnAppBoundAppsAndDuplicates() {
        let candidates = AppPromptBindingCandidates.running(excluding: [])

        if let ownBundleID = Bundle.main.bundleIdentifier {
            XCTAssertFalse(candidates.contains { AppPromptResolver.matches($0.bundleID, ownBundleID) })
        }
        XCTAssertEqual(Set(candidates.map(\.bundleID)).count, candidates.count)

        let sortedNames = candidates.map(\.appDisplayName)
        XCTAssertEqual(
            sortedNames,
            sortedNames.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        )

        // Binding a running app removes it from the next candidate list.
        guard let first = candidates.first else {
            return
        }
        let remaining = AppPromptBindingCandidates.running(excluding: [
            AppPromptBinding(bundleID: first.bundleID, appDisplayName: first.appDisplayName, prompt: "p")
        ])
        XCTAssertFalse(remaining.contains { AppPromptResolver.matches($0.bundleID, first.bundleID) })
    }
}
