import SuniyeAnalytics

/// The three onboarding screens. `speak` is the activation screen: microphone
/// grant, model download progress, and the first dictation all live there so
/// value arrives before the scarier Accessibility ask on `typeAnywhere`.
enum OnboardingStep: Int, CaseIterable {
    case welcome
    case speak
    case typeAnywhere

    var title: String {
        switch self {
        case .welcome:
            return "Welcome"
        case .speak:
            return "Speak"
        case .typeAnywhere:
            return "Type Anywhere"
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
        }
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
