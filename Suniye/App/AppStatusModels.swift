import Foundation

enum AttentionSeverity: String {
    case error
    case warning
}

enum AttentionItemFixAction: Equatable {
    case requestMicrophonePermission
    case requestAccessibilityPermission

    var title: String {
        switch self {
        case .requestMicrophonePermission, .requestAccessibilityPermission:
            return "Grant Access"
        }
    }
}

struct AttentionItem: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let severity: AttentionSeverity
    let recommendedSection: MainWindowSection
    let fixAction: AttentionItemFixAction?

    var fixTitle: String? {
        fixAction?.title
    }

    init(id: String, title: String, detail: String, severity: AttentionSeverity, recommendedSection: MainWindowSection, fixAction: AttentionItemFixAction? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
        self.severity = severity
        self.recommendedSection = recommendedSection
        self.fixAction = fixAction
    }
}
