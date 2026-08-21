import SuniyeAnalytics

/// The two onboarding screens. `speak` is the activation screen: microphone
/// grant, model download progress, and the first dictation all live there so
/// value arrives before the scarier Accessibility ask on `typeAnywhere`.
enum OnboardingStep: Int, CaseIterable {
    case speak
    case typeAnywhere

    /// The visible heading, also read by VoiceOver for the step indicator.
    var title: String {
        switch self {
        case .speak:
            return "Dictate"
        case .typeAnywhere:
            return "Dictate in any app"
        }
    }

    var analyticsName: OnboardingStepName {
        switch self {
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
/// `speakReached` is kept as a stored value from the three-screen flow; it and
/// `notStarted` both resume on the first screen.
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
        case .notStarted, .speakReached:
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

/// What one permission looks like on every surface that asks for it — the
/// onboarding rows, Settings › General, and the dashboard tile all render this
/// so a label or a sentence can only drift in one place.
struct PermissionPresentation: Equatable {
    enum Kind: Equatable {
        case microphone
        case accessibility
    }

    enum Action: Equatable {
        /// The guided path: system prompt for the microphone, drag overlay for
        /// Accessibility. Denied / already-listed states route to Settings.
        case allow
        case openSettings

        var label: String {
            switch self {
            case .allow:
                return "Allow Access"
            case .openSettings:
                return "Open Settings"
            }
        }
    }

    let kind: Kind
    let title: String
    /// Why the permission exists — the row's info tip, and the tile's detail
    /// once the state-specific sentence is gone.
    let purpose: String
    /// The sentence under the row; nil once granted.
    let detail: String?
    let primary: Action?
    let secondary: Action?

    var isGranted: Bool {
        primary == nil
    }

    static func microphone(appName: String, granted: Bool, denied: Bool) -> PermissionPresentation {
        if granted {
            return PermissionPresentation(kind: .microphone, title: "Microphone", purpose: "Needed to hear your dictation.", detail: nil, primary: nil, secondary: nil)
        }
        if denied {
            return PermissionPresentation(
                kind: .microphone,
                title: "Microphone",
                purpose: "Needed to hear your dictation.",
                detail: "Microphone access is off. Turn it on in System Settings; this screen updates by itself.",
                primary: .openSettings,
                secondary: nil
            )
        }
        return PermissionPresentation(
            kind: .microphone,
            title: "Microphone",
            purpose: "Needed to hear your dictation.",
            detail: "\(appName) listens only while you hold the hotkey. Audio never leaves your Mac.",
            primary: .allow,
            secondary: nil
        )
    }

    static func accessibility(
        appName: String,
        granted: Bool,
        listedButOff: Bool,
        assistEndedWithoutGrant: Bool
    ) -> PermissionPresentation {
        let purpose = "Needed to type your dictation into other apps."
        if granted {
            return PermissionPresentation(kind: .accessibility, title: "Accessibility", purpose: purpose, detail: nil, primary: nil, secondary: nil)
        }
        if listedButOff {
            return PermissionPresentation(
                kind: .accessibility,
                title: "Accessibility",
                purpose: purpose,
                detail: "macOS listed \(appName) but left it off. Turn \(appName) on in the Accessibility list.",
                primary: .openSettings,
                secondary: nil
            )
        }
        if assistEndedWithoutGrant {
            return PermissionPresentation(
                kind: .accessibility,
                title: "Accessibility",
                purpose: purpose,
                detail: "Still need access? Open Settings and turn \(appName) on.",
                primary: .allow,
                secondary: .openSettings
            )
        }
        return PermissionPresentation(
            kind: .accessibility,
            title: "Accessibility",
            purpose: purpose,
            detail: "Drag \(appName) into the Accessibility list. Nothing is read from your screen.",
            primary: .allow,
            secondary: nil
        )
    }
}
