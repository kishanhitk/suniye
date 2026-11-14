import Foundation
import SuniyeAnalytics

/// The onboarding screens. `speak` is the activation screen: the first
/// dictation lives there so value arrives before the scarier Accessibility ask
/// on `typeAnywhere`. `more` only names what else exists, then hands off.
enum OnboardingStep: Int, CaseIterable {
    case welcome
    case speak
    case typeAnywhere
    case more

    var title: String {
        switch self {
        case .welcome:
            return "Welcome"
        case .speak:
            return "Speak"
        case .typeAnywhere:
            return "Type Anywhere"
        case .more:
            return "More"
        }
    }

    var analyticsName: OnboardingStepName {
        switch self {
        case .welcome:
            return .welcome
        case .speak:
            return .speak
        case .typeAnywhere:
            return .typeAnywhere
        case .more:
            return .more
        }
    }
}

extension OnboardingStep {
    /// Closing the window on the last two screens finishes onboarding. Without
    /// Accessibility that is the quiet skip, and dictations are copied.
    var closingTheWindowFinishesOnboarding: Bool {
        switch self {
        case .typeAnywhere, .more:
            return true
        case .welcome, .speak:
            return false
        }
    }
}

/// What one onboarding run in this launch has seen, for the onboarding events.
struct OnboardingRun {
    private(set) var startedAt: Date?
    private var shownSteps: Set<OnboardingStep> = []
    private var resumed = false
    /// What is about to move onboarding to its next step.
    var pendingAdvance: OnboardingAdvance?
    /// Gates the Continue button of the Speak screen.
    private(set) var practiceSucceeded = false
    /// Drives the "Continue anyway" button and the practice analytics. Capped,
    /// so that a retry loop cannot inflate the metric.
    private(set) var practiceAttempts = 0
    /// The practice dictation as transcribed, to tell whether the user edited it.
    private var practiceTranscript: String?
    private(set) var practiceEdited = false

    mutating func begin(at date: Date, resumed: Bool) {
        if resumed {
            self.resumed = true
        }
        if startedAt == nil {
            startedAt = date
        }
    }

    mutating func end() {
        startedAt = nil
    }

    func elapsedMs(at date: Date) -> Int? {
        startedAt.map { Int(date.timeIntervalSince($0) * 1000) }
    }

    /// The first showing of `step` in this run, with whether a relaunch resumed
    /// it and what moved onboarding there; nil when the step was shown before.
    mutating func stepShown(_ step: OnboardingStep?) -> (resumed: Bool, advancedBy: OnboardingAdvance?)? {
        defer { resumed = false }
        guard let step, !shownSteps.contains(step) else {
            return nil
        }
        shownSteps.insert(step)
        let advancedBy = pendingAdvance
        pendingAdvance = nil
        return (resumed, advancedBy)
    }

    mutating func practiceDidSucceed(transcript: String) {
        practiceSucceeded = true
        practiceTranscript = transcript
    }

    mutating func countPracticeAttempt() -> Int {
        practiceAttempts = min(practiceAttempts + 1, 10)
        return practiceAttempts
    }

    mutating func leaveSpeak(withText text: String) {
        practiceEdited = practiceTranscript.map { $0 != text } ?? false
    }
}

/// Persisted onboarding position — the single source of truth that replaces the
/// legacy `hasSeenOnboardingWelcome`/`hasCompletedCoreOnboarding` Bool pair
/// (whose illegal combinations needed a repair pass on every launch).
enum OnboardingProgress: String, Codable, Equatable, CaseIterable {
    case notStarted
    case speakReached
    case typeAnywhereReached
    case finished

    var isFinished: Bool {
        self == .finished
    }

    /// Which screen a relaunch resumes on; nil once finished.
    var resumeStep: OnboardingStep? {
        switch self {
        case .notStarted:
            return .welcome
        case .speakReached:
            return .speak
        case .typeAnywhereReached:
            return .typeAnywhere
        case .finished:
            return nil
        }
    }

    /// Maps the legacy two-Bool persistence onto the enum, including installs
    /// that predate the flags entirely (`legacyUserShowsUsage` is the old
    /// auto-complete heuristic). A wrong mapping here re-shows onboarding to
    /// existing users, so the truth table is exhaustively unit-tested.
    static func migrating(
        hasSeenOnboardingWelcome: Bool?,
        hasCompletedCoreOnboarding: Bool?,
        legacyUserShowsUsage: Bool
    ) -> OnboardingProgress {
        if hasCompletedCoreOnboarding == true {
            return .finished
        }

        switch (hasSeenOnboardingWelcome, hasCompletedCoreOnboarding) {
        case (nil, nil):
            // Pre-flag install: trust the usage heuristic.
            return legacyUserShowsUsage ? .finished : .notStarted
        case (true, nil):
            return legacyUserShowsUsage ? .finished : .speakReached
        case (true, false):
            // Mid-wizard when they quit (old setup/magicFormat steps) — resume
            // on the speak screen, which owns the same prerequisites.
            return .speakReached
        default:
            // welcome unseen (false or nil): they never got past screen one.
            return .notStarted
        }
    }
}

struct OnboardingPracticeResult: Equatable {
    enum Severity: Equatable {
        case success
        case error
    }

    let message: String
    let severity: Severity
}

extension Notification.Name {
    /// Posted when onboarding finishes, so the menu bar can show where Suniye lives.
    static let suniyeOnboardingDidFinish = Notification.Name("dev.suniye.onboardingDidFinish")
}
