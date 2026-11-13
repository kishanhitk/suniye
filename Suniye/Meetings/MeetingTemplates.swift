import Foundation

/// How to write a meeting's summary: its sections and what goes in them, as
/// text that the user can edit. The title line and the heading format are
/// fixed rules in `MeetingSummaryPrompt`, so an edit cannot break the parser.
struct MeetingTemplate: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var name: String
    var sections: String

    var isBuiltIn: Bool {
        Self.builtIn.contains { $0.id == id }
    }

    /// The shipped text of a built-in template; nil for one the user added.
    var defaultSections: String? {
        Self.builtIn.first { $0.id == id }?.sections
    }

    static let general = MeetingTemplate(id: "general", name: "General", sections: """
    Write a summary of the meeting.
    Use these sections, in this order:
    ## Overview
    ## Decisions
    ## Action items
    ## Open questions
    Under Overview, write two or three sentences: what the meeting was about and what it decided.
    Write one line for each decision, task and open question. For a task, say who does it, and by when if the transcript says.
    Leave out a section with nothing in it.
    Use only what the transcript and my notes say.
    """)

    static let oneOnOne = MeetingTemplate(id: "one-on-one", name: "1:1", sections: """
    Write a summary of a one-on-one meeting.
    Use these sections, in this order:
    ## Overview
    ## Updates
    ## Feedback
    ## Action items
    Under Overview, write two or three sentences on what the two people talked about.
    Write one line for each update, piece of feedback and task. Say who gave the feedback and who does each task.
    Leave out a section with nothing in it.
    Use only what the transcript and my notes say.
    """)

    static let standUp = MeetingTemplate(id: "stand-up", name: "Stand-up", sections: """
    Write a short stand-up summary.
    Use these sections, in this order:
    ## Done
    ## Next
    ## Blockers
    Write one line for each update.
    Add a name only when the transcript says it.
    Leave out a section with nothing in it.
    Use only what the transcript and my notes say.
    Keep each line under 15 words.
    """)

    static let interview = MeetingTemplate(id: "interview", name: "Interview", sections: """
    Write a summary of an interview.
    Use these sections, in this order:
    ## Overview
    ## Questions and answers
    ## Strengths
    ## Concerns
    ## Next steps
    Under Overview, write two or three sentences: the role, and how the interview went.
    Write one line for each question with its short answer, and one line for each strength, concern and next step.
    Leave out a section with nothing in it.
    Use only what the transcript and my notes say.
    """)

    static let builtIn = [general, oneOnOne, standUp, interview]
}

/// The user's templates: the built-in ones with the user's edits, then the
/// ones the user added. Only edits and additions are on disk, so a changed
/// shipped template reaches every user who did not edit it.
actor MeetingTemplateStore {
    enum StoreError: LocalizedError, Equatable {
        case builtInTemplate

        var errorDescription: String? {
            "A built-in template can only be restored, not deleted."
        }
    }

    nonisolated let fileURL: URL

    init(fileURL: URL = MeetingTemplateStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    static func defaultFileURL(identity: AppIdentity = .current) -> URL {
        MeetingStore.supportDirectory.appendingPathComponent(identity.isPreview ? "meeting-templates-preview.json" : "meeting-templates.json")
    }

    func templates() -> [MeetingTemplate] {
        let saved = load()
        let builtIn = MeetingTemplate.builtIn.map { template in
            saved.first { $0.id == template.id } ?? template
        }
        return builtIn + saved.filter { !$0.isBuiltIn }
    }

    /// The template with `id`, or General when it was deleted.
    func template(id: String) -> MeetingTemplate {
        let all = templates()
        return all.first { $0.id == id } ?? all[0]
    }

    func save(_ template: MeetingTemplate) throws {
        var saved = load().filter { $0.id != template.id }
        if template.sections != template.defaultSections || !template.isBuiltIn {
            saved.append(template)
        }
        try write(saved)
    }

    func delete(id: String) throws {
        guard !MeetingTemplate.builtIn.contains(where: { $0.id == id }) else {
            throw StoreError.builtInTemplate
        }
        try write(load().filter { $0.id != id })
    }

    private func load() -> [MeetingTemplate] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        do {
            return try JSONDecoder().decode([MeetingTemplate].self, from: data)
        } catch {
            AppLogger.shared.log(.error, "meeting templates unreadable error=\(error.localizedDescription)")
            return []
        }
    }

    private func write(_ templates: [MeetingTemplate]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(templates).write(to: fileURL, options: .atomic)
    }
}
