import XCTest
@testable import Suniye

final class OnboardingModelsTests: XCTestCase {
    func testProgressResumeSteps() {
        XCTAssertEqual(OnboardingProgress.notStarted.resumeStep, .welcome)
        XCTAssertEqual(OnboardingProgress.speakReached.resumeStep, .speak)
        XCTAssertEqual(OnboardingProgress.typeAnywhereReached.resumeStep, .typeAnywhere)
        XCTAssertNil(OnboardingProgress.finished.resumeStep)
        XCTAssertTrue(OnboardingProgress.finished.isFinished)
        XCTAssertFalse(OnboardingProgress.speakReached.isFinished)
    }
}

/// Exhaustive truth table for the legacy two-Bool → enum migration. A wrong
/// mapping here re-shows onboarding to existing users, so every combination of
/// (welcome flag × completed flag × legacy usage) is pinned.
final class OnboardingProgressMigrationTests: XCTestCase {
    private func migrated(_ welcome: Bool?, _ completed: Bool?, usage: Bool) -> OnboardingProgress {
        OnboardingProgress.migrating(
            hasSeenOnboardingWelcome: welcome,
            hasCompletedCoreOnboarding: completed,
            legacyUserShowsUsage: usage
        )
    }

    func testCompletedAlwaysWins() {
        // Any completed=true combination is finished — including the illegal
        // welcome=false/nil ones the old code needed a repair pass for.
        for welcome in [true, false, nil] as [Bool?] {
            for usage in [true, false] {
                XCTAssertEqual(migrated(welcome, true, usage: usage), .finished)
            }
        }
    }

    func testPreFlagInstallUsesUsageHeuristic() {
        XCTAssertEqual(migrated(nil, nil, usage: true), .finished)
        XCTAssertEqual(migrated(nil, nil, usage: false), .notStarted)
    }

    func testMidWizardResumesOnSpeak() {
        XCTAssertEqual(migrated(true, false, usage: true), .speakReached)
        XCTAssertEqual(migrated(true, false, usage: false), .speakReached)
        XCTAssertEqual(migrated(true, nil, usage: false), .speakReached)
        XCTAssertEqual(migrated(true, nil, usage: true), .finished)
    }

    func testWelcomeUnseenStartsOver() {
        XCTAssertEqual(migrated(false, false, usage: true), .notStarted)
        XCTAssertEqual(migrated(false, false, usage: false), .notStarted)
        XCTAssertEqual(migrated(false, nil, usage: true), .notStarted)
        XCTAssertEqual(migrated(false, nil, usage: false), .notStarted)
        XCTAssertEqual(migrated(nil, false, usage: true), .notStarted)
        XCTAssertEqual(migrated(nil, false, usage: false), .notStarted)
    }
}
