enum OnboardingStep: Int, CaseIterable {
    case welcome
    case setup
    case magicFormat
    case practice

    var title: String {
        switch self {
        case .welcome:
            return "Welcome"
        case .setup:
            return "Set Up"
        case .magicFormat:
            return "Magic Format"
        case .practice:
            return "Try It"
        }
    }
}

enum OnboardingMagicFormatProvider: Hashable {
    case localModel
    case appleIntelligence

    var magicFormatProvider: MagicFormatProvider {
        switch self {
        case .localModel:
            return .localGemma
        case .appleIntelligence:
            return .appleFoundationModels
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
