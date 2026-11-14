import Foundation
import SuniyeAnalytics

/// Which on-device model can write summaries on this Mac now. A remote
/// provider is never a choice: a meeting stays on the Mac.
enum MeetingSummaryAvailability: Equatable, Sendable {
    case ready(MeetingSummaryEngine)
    /// The local model runs on this Mac once it is downloaded.
    case needsDownload
    /// No on-device model runs on this Mac.
    case unavailable

    /// The local model when it is installed, else Apple Intelligence when it
    /// is ready.
    init(apple: AppleFoundationModelsAvailability, localModel: LocalGemmaAvailability) {
        if localModel.isAvailable {
            self = .ready(.localModel)
        } else if apple.isAvailable {
            self = .ready(.appleIntelligence)
        } else if localModel == .modelNotInstalled {
            self = .needsDownload
        } else {
            self = .unavailable
        }
    }
}

/// One request to a summary model. Single-turn: the model reads
/// `instructions`, a blank line, then `input`.
struct MeetingSummaryRequest: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case summary
        /// Notes or items on part `number` of the `count` parts of a
        /// transcript.
        case part(number: Int, count: Int)
        /// One shorter set of notes from the notes on several parts.
        case join
        /// The items in the user's notes.
        case userNotes
        /// The title and the paragraph, from the joined items.
        case overview
    }

    let kind: Kind
    let instructions: String
    let input: String

    var maxOutputTokens: Int {
        switch kind {
        case .summary:
            return MeetingSummaryWriter.summaryOutputTokens
        case .overview:
            return MeetingSummaryWriter.overviewOutputTokens
        case .part, .join, .userNotes:
            return MeetingSummaryWriter.partOutputTokens
        }
    }

    var text: String {
        instructions + "\n\n" + input
    }
}

/// One on-device model, as the summary writer uses it.
protocol MeetingSummaryModel {
    /// Tokens that one request holds: the prompt and the answer together.
    func contextTokens() async -> Int
    /// Tokens in `text` by the model's own tokenizer, or nil when the model
    /// cannot count.
    func tokenCount(_ text: String) async -> Int?
    /// Throws `LLMPostProcessorError.outputTruncated` when the answer did not
    /// fit.
    func generate(_ request: MeetingSummaryRequest) async throws -> String
}

struct MeetingSummaryInput: Sendable {
    let segments: [MeetingSegment]
    let notes: String
    let template: MeetingTemplate
    /// False when the meeting had no call track, so no line has a speaker.
    let speakerLabels: Bool
}

struct MeetingSummary: Equatable, Sendable {
    let title: String?
    /// Markdown: "## " headings, "- " list lines and plain lines.
    let body: String
    /// The transcript parts that got notes of their own; 1 when the
    /// transcript fit in one request.
    let parts: Int
}

enum MeetingSummaryError: LocalizedError, Equatable {
    /// Fewer than `MeetingSummaryWriter.minimumWords` words and no notes.
    case tooLittleSpeech
    /// The model failed; the text is the cause that the meeting page shows.
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .tooLittleSpeech:
            return MeetingStatus.noSpeechTitle
        case let .failed(cause):
            return cause
        }
    }
}

/// Writes a meeting's summary with one on-device model.
///
/// For a template with list sections (`MeetingSummaryLayout`), the transcript
/// is cut into parts at segment edges, and each part, and the user's notes,
/// give their items under those sections. Code joins the items in meeting
/// order and drops repeats, so no last step can lose an item; the model then
/// writes only the title and the paragraph. A template with no list section
/// is written by the model from the whole transcript, or from notes on its
/// parts when it does not fit.
///
/// The answer to each request is kept: a summary that a dictation stopped
/// goes on where it stopped.
actor MeetingSummaryWriter {
    static let minimumWords = 25
    static let summaryOutputTokens = 1_200
    static let partOutputTokens = 500
    static let overviewOutputTokens = 300
    /// A small model keeps more items from a shorter part, so a part stays
    /// under this size also when the context could hold more.
    static let maximumPartTokens = 4_000
    /// A long template leaves less room for the transcript in each part.
    /// Below this room, a long meeting would need hundreds of requests, so
    /// the model writes the summary from the whole transcript.
    static let minimumPartTokens = 1_000
    /// The share of the context that a prompt may fill: the rest is for the
    /// chat template's own tokens and a count that is a little low.
    static let fillFactor = 0.9
    /// For a model that cannot count its tokens.
    static let charactersPerToken = 2

    private let model: MeetingSummaryModel
    private var answers: [MeetingSummaryRequest: String] = [:]

    init(model: MeetingSummaryModel) {
        self.model = model
    }

    /// A summary needs `minimumWords` spoken words, or notes.
    static func hasEnoughSpeech(_ segments: [MeetingSegment], notes: String) -> Bool {
        let spokenWords = segments.reduce(0) { $0 + MeetingTranscript.words(in: $1.text).count }
        return spokenWords >= minimumWords || !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func write(_ input: MeetingSummaryInput) async throws -> MeetingSummary {
        guard Self.hasEnoughSpeech(input.segments, notes: input.notes) else {
            throw MeetingSummaryError.tooLittleSpeech
        }
        if let layout = MeetingSummaryLayout(template: input.template),
           let summary = try await writeBySection(input, layout: layout) {
            return summary
        }
        return try await writeWhole(input)
    }

    // MARK: - By section

    /// Nil when the template leaves too little room for a part, or when the
    /// notes hold no item: the model then writes the summary from the
    /// transcript.
    private func writeBySection(_ input: MeetingSummaryInput, layout: MeetingSummaryLayout) async throws -> MeetingSummary? {
        let context = await model.contextTokens()
        let empty = MeetingSummaryPrompt.items(transcript: "", number: 1, of: 1, template: input.template, sections: layout.lists, speakerLabels: input.speakerLabels)
        let room = min(budget(context: context, output: Self.partOutputTokens), Self.maximumPartTokens) - (await tokens(in: empty.text))
        guard room >= Self.minimumPartTokens else { return nil }
        let parts = await split(input, room: room)

        // The user's items come first in each section, so a repeat of one of
        // them from the transcript goes.
        var found: [[String: [String]]] = []
        let notes = input.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            let empty = MeetingSummaryPrompt.items(notes: "", template: input.template, sections: layout.lists)
            let noteRoom = min(budget(context: context, output: Self.partOutputTokens), Self.maximumPartTokens) - (await tokens(in: empty.text))
            for piece in await split(notes: notes, room: noteRoom) {
                let request = MeetingSummaryPrompt.items(notes: piece, template: input.template, sections: layout.lists)
                found.append(MeetingSummaryItems.parse(try await run(request), sections: layout.lists))
            }
        }
        for (index, part) in parts.enumerated() {
            let transcript = MeetingTranscript.turns(part, timeline: nil, speakerLabels: input.speakerLabels).joined(separator: "\n")
            let request = MeetingSummaryPrompt.items(transcript: transcript, number: index + 1, of: parts.count, template: input.template, sections: layout.lists, speakerLabels: input.speakerLabels)
            found.append(MeetingSummaryItems.parse(try await run(request), sections: layout.lists))
        }
        let items = MeetingSummaryItems.join(found, sections: layout.lists)
        guard items.values.contains(where: { !$0.isEmpty }) else { return nil }

        let overview = try await overview(of: items, input: input, layout: layout, context: context)
        var blocks: [String] = []
        for section in layout.sections {
            if section == layout.paragraph {
                if !overview.paragraph.isEmpty {
                    blocks.append("## \(section)\n\(overview.paragraph)")
                }
            } else if let list = items[section], !list.isEmpty {
                blocks.append((["## \(section)"] + list.map { "- \($0)" }).joined(separator: "\n"))
            }
        }
        return MeetingSummary(title: overview.title, body: blocks.joined(separator: "\n\n"), parts: parts.count)
    }

    /// The title, and the paragraph when the template has one, from the
    /// joined items. When they do not all fit, each section gives its first
    /// items; when one item of each section does not fit either, the summary
    /// has no title and no paragraph.
    private func overview(
        of items: [String: [String]],
        input: MeetingSummaryInput,
        layout: MeetingSummaryLayout,
        context: Int
    ) async throws -> (title: String?, paragraph: String) {
        let room = budget(context: context, output: Self.overviewOutputTokens)
        var shown = items
        var request = MeetingSummaryPrompt.overview(items: shown, sections: layout.lists, template: input.template, paragraph: layout.paragraph)
        while await tokens(in: request.text) > room, let longest = shown.values.map(\.count).max(), longest > 1 {
            shown = shown.mapValues { Array($0.prefix(max(1, $0.count / 2))) }
            request = MeetingSummaryPrompt.overview(items: shown, sections: layout.lists, template: input.template, paragraph: layout.paragraph)
        }
        guard await tokens(in: request.text) <= room else { return (nil, "") }
        return MeetingSummaryText.overview(try await run(request))
    }

    // MARK: - Whole

    private func writeWhole(_ input: MeetingSummaryInput) async throws -> MeetingSummary {
        let notes = input.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let context = await model.contextTokens()
        let summaryBudget = budget(context: context, output: Self.summaryOutputTokens)
        let transcript = MeetingTranscript.turns(input.segments, timeline: nil, speakerLabels: input.speakerLabels)
        let whole = MeetingSummaryPrompt.summary(
            template: input.template,
            notes: notes,
            transcript: transcript.joined(separator: "\n"),
            speakerLabels: input.speakerLabels
        )
        let answer: String
        var parts = 1
        if await tokens(in: whole.text) <= summaryBudget {
            answer = try await run(whole)
        } else {
            var partNotes = try await notesOnParts(input, context: context)
            parts = partNotes.count
            while true {
                let combine = MeetingSummaryPrompt.summary(
                    template: input.template,
                    notes: notes,
                    partNotes: partNotes,
                    speakerLabels: input.speakerLabels
                )
                var fits = partNotes.count == 1
                if !fits {
                    fits = await tokens(in: combine.text) <= summaryBudget
                }
                if fits {
                    answer = try await run(combine)
                    break
                }
                partNotes = try await joinInGroups(partNotes, context: context)
            }
        }
        let parsed = MeetingSummaryText.parse(answer)
        guard !parsed.body.isEmpty else {
            throw MeetingSummaryError.failed(Self.cause(of: LLMPostProcessorError.emptyOutput))
        }
        return MeetingSummary(title: parsed.title, body: parsed.body, parts: parts)
    }

    private func notesOnParts(_ input: MeetingSummaryInput, context: Int) async throws -> [String] {
        let empty = MeetingSummaryPrompt.part(transcript: "", number: 1, of: 1, speakerLabels: input.speakerLabels)
        let room = budget(context: context, output: Self.partOutputTokens) - (await tokens(in: empty.text))
        let parts = await split(input, room: room)
        var notes: [String] = []
        for (index, part) in parts.enumerated() {
            let transcript = MeetingTranscript.turns(part, timeline: nil, speakerLabels: input.speakerLabels).joined(separator: "\n")
            let request = MeetingSummaryPrompt.part(transcript: transcript, number: index + 1, of: parts.count, speakerLabels: input.speakerLabels)
            notes.append(try await run(request))
        }
        return notes
    }

    /// Joins notes in groups of two or more, so each round has fewer notes.
    private func joinInGroups(_ notes: [String], context: Int) async throws -> [String] {
        let room = budget(context: context, output: Self.partOutputTokens)
        var groups: [[String]] = []
        var current: [String] = []
        for note in notes {
            if current.count >= 2, await tokens(in: MeetingSummaryPrompt.join(current + [note]).text) > room {
                groups.append(current)
                current = []
            }
            current.append(note)
        }
        groups.append(current)
        var joined: [String] = []
        for group in groups {
            joined.append(group.count == 1 ? group[0] : try await run(MeetingSummaryPrompt.join(group)))
        }
        return joined
    }

    // MARK: - Parts

    /// Cuts the transcript at segment edges into parts of at most `room`
    /// tokens.
    private func split(_ input: MeetingSummaryInput, room: Int) async -> [[MeetingSegment]] {
        let segments = MeetingTranscript.ordered(input.segments)
        let fullText = MeetingTranscript.turns(segments, timeline: nil, speakerLabels: input.speakerLabels).joined(separator: "\n")
        let tokensPerCharacter = Double(await tokens(in: fullText)) / Double(max(1, fullText.count))
        // A segment costs its text, a speaker label with ": ", and a line break.
        let labelCost = (MeetingTrack.allCases.map(\.speakerLabel.count).max() ?? 0) + 3
        return Self.pack(segments, room: room) { Double($0.text.count + labelCost) * tokensPerCharacter }
    }

    /// Cuts the user's notes at line ends into pieces of at most `room`
    /// tokens.
    private func split(notes: String, room: Int) async -> [String] {
        let tokensPerCharacter = Double(await tokens(in: notes)) / Double(max(1, notes.count))
        return Self.pack(notes.components(separatedBy: .newlines), room: room) { Double($0.count + 1) * tokensPerCharacter }
            .map { $0.joined(separator: "\n") }
    }

    /// Fills each group up to `room`, in order; an element that is larger
    /// than `room` is a group of its own.
    private static func pack<Element>(_ elements: [Element], room: Int, cost: (Element) -> Double) -> [[Element]] {
        var groups: [[Element]] = []
        var current: [Element] = []
        var used = 0.0
        for element in elements {
            let size = cost(element)
            if !current.isEmpty, used + size > Double(room) {
                groups.append(current)
                current = []
                used = 0
            }
            current.append(element)
            used += size
        }
        if !current.isEmpty {
            groups.append(current)
        }
        return groups
    }

    // MARK: - Requests

    private func run(_ request: MeetingSummaryRequest) async throws -> String {
        if let answer = answers[request] {
            return answer
        }
        do {
            let answer = try await model.generate(request)
            answers[request] = answer
            return answer
        } catch {
            // A cancel surfaces as different errors (a stopped server start,
            // an Apple model error); the task's state tells it from a failure.
            if Task.isCancelled {
                throw CancellationError()
            }
            // Only the domain and the code: app.log goes into diagnostic
            // reports, and an error description can hold meeting text.
            let underlying = error as NSError
            AppLogger.shared.log(.error, "meeting summary request failed kind=\(request.kind) domain=\(underlying.domain) code=\(underlying.code)")
            throw MeetingSummaryError.failed(Self.cause(of: error))
        }
    }

    private func tokens(in text: String) async -> Int {
        if let counted = await model.tokenCount(text) {
            return counted
        }
        return (text.count + Self.charactersPerToken - 1) / Self.charactersPerToken
    }

    private func budget(context: Int, output: Int) -> Int {
        Int(Double(context - output) * Self.fillFactor)
    }

    static func cause(of error: Error) -> String {
        switch error as? LLMPostProcessorError {
        case .outputTruncated:
            return "The model stopped before it finished."
        case .timeout:
            return "The model took too long."
        case .invalidConfiguration:
            return "The model is not ready."
        case .emptyOutput, .malformedResponse:
            return "The model wrote nothing."
        case .provider, .network, .unauthorized, .none:
            return "The model stopped with an error."
        }
    }
}

/// The requests to the model. A small model follows the rules it read last,
/// so each request puts the transcript or the notes first and the rules
/// after them.
enum MeetingSummaryPrompt {
    static func summary(template: MeetingTemplate, notes: String, transcript: String, speakerLabels: Bool) -> MeetingSummaryRequest {
        MeetingSummaryRequest(
            kind: .summary,
            instructions: "You write the summary of a meeting from its transcript.",
            input: "<transcript>\n\(transcript)\n</transcript>\n\n" + notesBlock(notes) + "\n\n" + summaryRules(template: template, speakerLabels: speakerLabels)
        )
    }

    static func summary(template: MeetingTemplate, notes: String, partNotes: [String], speakerLabels: Bool) -> MeetingSummaryRequest {
        MeetingSummaryRequest(
            kind: .summary,
            instructions: "You write the summary of a meeting from notes on the parts of its transcript.",
            input: partNotesBlock(partNotes) + "\n\n" + notesBlock(notes) + "\n\n" + summaryRules(template: template, speakerLabels: speakerLabels)
        )
    }

    static func part(transcript: String, number: Int, of count: Int, speakerLabels: Bool) -> MeetingSummaryRequest {
        MeetingSummaryRequest(
            kind: .part(number: number, count: count),
            instructions: "You take notes on one part of a long meeting.",
            input: """
            <transcript part="\(number) of \(count)">
            \(transcript)
            </transcript>

            Fill in these four lines from this part of the meeting:
            \(noteLines)

            Rules:
            \(noteItemRule)
            - Write each item in your own short words. Do not copy lines of the transcript.
            - Keep names, numbers and dates as the transcript says them.
            - For a task, say who does it and by when.
            - Leave out opinions and talk that decides nothing.
            \(speakerRule(speakerLabels))
            - Write in the language of the transcript.
            """
        )
    }

    static func join(_ notes: [String]) -> MeetingSummaryRequest {
        MeetingSummaryRequest(
            kind: .join,
            instructions: "You join notes on the parts of a meeting.",
            input: partNotesBlock(notes) + """


            Join these notes into the same four lines:
            \(noteLines)

            Rules:
            \(noteItemRule)
            - Keep every decision, every task with who does it, every date and number, and every open question.
            - Remove repeats.
            - Write in the language of the notes.
            """
        )
    }

    /// The items of one part under the template's list sections.
    static func items(transcript: String, number: Int, of count: Int, template: MeetingTemplate, sections: [String], speakerLabels: Bool) -> MeetingSummaryRequest {
        let rules = [noteItemRule, labelRule, onlyLinesRule, itemLimitRule]
            + sections.compactMap { sectionRules[$0] }
            + [
                "- Write each item in your own short words. Do not copy lines of the transcript.",
                "- Keep names, numbers and dates as the transcript says them.",
                "- Leave out talk with no result, such as an update with no change, \"we will see\" or \"no news yet\".",
                speakerRule(speakerLabels),
                "- Write in the language of the transcript.",
            ]
        return MeetingSummaryRequest(
            kind: .part(number: number, count: count),
            instructions: "You take notes on one part of a meeting.",
            input: """
            <transcript part="\(number) of \(count)">
            \(transcript)
            </transcript>

            \(templateGuide(template))Fill in these lines from this part of the meeting:
            \(labels(sections))

            Rules:
            \(rules.joined(separator: "\n"))
            """
        )
    }

    /// The items of the user's notes under the template's list sections.
    static func items(notes: String, template: MeetingTemplate, sections: [String]) -> MeetingSummaryRequest {
        MeetingSummaryRequest(
            kind: .userNotes,
            instructions: "You sort the notes that a user took in a meeting.",
            input: """
            \(notesBlock(notes))

            \(templateGuide(template))Fill in these lines from the notes:
            \(labels(sections))

            Rules:
            \(noteItemRule)
            \(labelRule)
            \(onlyLinesRule)
            - Keep the user's words.
            - Write in the language of the notes.
            """
        )
    }

    /// The title line and, with `paragraph`, the paragraph of the summary.
    static func overview(items: [String: [String]], sections: [String], template: MeetingTemplate, paragraph: String?) -> MeetingSummaryRequest {
        let notes = sections.compactMap { section in
            items[section].flatMap { $0.isEmpty ? nil : "\(section): \($0.joined(separator: "; "))" }
        }
        let task = paragraph.map { "- Then write the text of the \"\($0)\" section, as the template says, as one paragraph. Stop after it." }
            ?? "- Write only the title line."
        return MeetingSummaryRequest(
            kind: .overview,
            instructions: "You write the title of a meeting from notes on it.",
            input: """
            <meeting_notes>
            \(notes.joined(separator: "\n"))
            </meeting_notes>

            \(templateBlock(template))

            Rules:
            - Start with one line: "Title: " and a short title for the meeting, at most 8 words.
            \(task)
            - Use only facts from the notes. Do not guess.
            - Write plain text: no lists, no headings, and no copy of the notes.
            - Write in the language of the notes.
            """
        )
    }

    private static let datesAndNumbers = "Dates and numbers"

    private static func labels(_ sections: [String]) -> String {
        sections.map { "\($0):" }.joined(separator: "\n")
    }

    private static func templateBlock(_ template: MeetingTemplate) -> String {
        "<template>\n\(template.sections)\n</template>"
    }

    /// A template that the user wrote or edited, as a guide to its sections.
    /// The built-in sections have rules here instead: with the template text,
    /// models wrote a whole summary into each part answer.
    private static func templateGuide(_ template: MeetingTemplate) -> String {
        guard !MeetingTemplate.builtIn.contains(template) else { return "" }
        return "The user's template says what each section holds. Do not write the summary.\n" + templateBlock(template) + "\n\n"
    }

    /// What goes under the sections of the built-in templates. A model put
    /// remarks such as "the menu is hard to find" under every label.
    private static let sectionRules = [
        "Decisions": "- Under \"Decisions\", put only what the people agreed to do or not to do.",
        "Action items": "- Under \"Action items\", put only work that a person said they will do, with who does it and by when.",
        "Open questions": "- Under \"Open questions\", put only a question that someone asked and nobody answered.",
        datesAndNumbers: "- Put a date or a number with the item it belongs to. Under \"\(datesAndNumbers)\", put each one that fits no other line, with what it is about.",
    ]

    private static func summaryRules(template: MeetingTemplate, speakerLabels: Bool) -> String {
        """
        <template>
        \(template.sections)
        </template>

        Write the summary of the meeting above.

        Rules:
        - Start with one line: "Title: " and a short title for the meeting, at most 8 words.
        - Then write the sections of the template, in its order, each under its "## " heading.
        - Keep every decision, every task with who does it, and every date and number that someone gave.
        - Write each list item as one line that starts with "- ". Write plain text: no bold, no tables.
        - Leave out a section that has nothing to put in it.
        - Use only facts from the meeting. Do not guess.
        \(speakerRule(speakerLabels))
        - When the user's notes and the meeting disagree, follow the notes.
        - Write in the language of the meeting.
        """
    }

    /// The lines of part notes: the part and the join prompts ask for the
    /// same ones.
    private static let noteLines = """
        Decisions:
        Tasks:
        Dates and numbers:
        Open questions:
        """
    private static let noteItemRule = "- After each label, write the items on the same line, separated by \"; \". Write \"none\" when there is none."
    private static let labelRule = "- Copy each label exactly as it is written above, also when you write the items in another language."
    private static let onlyLinesRule = "- Write only these lines: no other section, no heading and no text before or after them."
    private static let itemLimitRule = "- Write at most 3 items after each label: the ones that matter most."

    private static func speakerRule(_ speakerLabels: Bool) -> String {
        speakerLabels
            ? "- \"\(MeetingTrack.you.speakerLabel)\" is the user. \"\(MeetingTrack.them.speakerLabel)\" is the other people on the call."
            : "- The transcript does not say who speaks."
    }

    private static func notesBlock(_ notes: String) -> String {
        "<notes>\n\(notes.isEmpty ? "(none)" : notes)\n</notes>"
    }

    private static func partNotesBlock(_ notes: [String]) -> String {
        let parts = notes.enumerated().map { "Part \($0.offset + 1):\n\($0.element)" }
        return "<part_notes>\n\(parts.joined(separator: "\n\n"))\n</part_notes>"
    }
}

/// The sections of a template that code can read: its "## " headings, in
/// order. A section named Overview or Summary is the paragraph that the model
/// writes last; every other section is a list that code joins from the notes
/// on the parts.
struct MeetingSummaryLayout: Equatable, Sendable {
    let sections: [String]
    let paragraph: String?

    static let paragraphNames = ["overview", "summary"]

    var lists: [String] {
        sections.filter { $0 != paragraph }
    }

    /// Nil for a template with no list section, or with two sections of one
    /// name: code reads the items by section name.
    init?(template: MeetingTemplate) {
        let headings = template.sections.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("## ") }
            .map { String($0.dropFirst(3)).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let paragraph = headings.first { Self.paragraphNames.contains($0.lowercased()) }
        guard headings.contains(where: { $0 != paragraph }),
              Set(headings.map { $0.lowercased() }).count == headings.count
        else { return nil }
        sections = headings
        self.paragraph = paragraph
    }
}

/// The items that a model wrote under section labels, and their join.
enum MeetingSummaryItems {
    /// Reads "Label: a; b" lines, and a label line ("Label:" or "## Label")
    /// followed by "- " or "1. " lines, or by "a; b" lines. Lines under other
    /// labels, and items that say that there is none, go.
    static func parse(_ answer: String, sections: [String]) -> [String: [String]] {
        var items: [String: [String]] = [:]
        var current: String?
        for raw in answer.components(separatedBy: .newlines) {
            let line = raw.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces)
            if let (section, rest) = labeled(line, sections: sections) {
                current = section
                items[section, default: []] += rest.components(separatedBy: ";").compactMap { clean($0, section: section) }
            } else if line.hasPrefix("#") || line.hasSuffix(":") {
                current = nil
            } else if let current, let item = listItem(line) {
                items[current, default: []] += [clean(item, section: current)].compactMap { $0 }
            } else if let current {
                items[current, default: []] += line.components(separatedBy: ";").compactMap { clean($0, section: current) }
            }
        }
        return items
    }

    /// The items of each section in the order of `answers`, each once: an
    /// item goes when an earlier item of the section has the same words in
    /// the same order.
    static func join(_ answers: [[String: [String]]], sections: [String]) -> [String: [String]] {
        var joined: [String: [String]] = [:]
        for section in sections {
            var seen: Set<[String]> = []
            joined[section] = answers.flatMap { $0[section] ?? [] }.filter { item in
                let words = MeetingTranscript.words(in: item)
                return !words.isEmpty && seen.insert(words).inserted
            }
        }
        return joined
    }

    /// The text of a "- ", "* ", "• ", "1. " or "1) " line.
    private static func listItem(_ line: String) -> String? {
        for marker in ["- ", "* ", "• "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        let digits = line.prefix { $0.isNumber }
        let rest = line.dropFirst(digits.count)
        guard !digits.isEmpty, rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return String(rest.dropFirst(2))
    }

    private static func labeled(_ line: String, sections: [String]) -> (String, String)? {
        let text = line.drop { $0 == "#" || $0 == "-" || $0 == " " }
        for section in sections where text.lowercased().hasPrefix(section.lowercased()) {
            let rest = text.dropFirst(section.count).trimmingCharacters(in: .whitespaces)
            if rest.isEmpty {
                return (section, "")
            }
            if rest.hasPrefix(":") {
                return (section, String(rest.dropFirst()))
            }
        }
        return nil
    }

    private static func clean(_ item: String, section: String) -> String? {
        let text = item.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ";,")))
        return MeetingSummaryText.saysNothing(text, about: section) ? nil : text
    }
}

/// Turns a model's answer into a title and a clean body.
enum MeetingSummaryText {
    static let maximumTitleLength = 80
    /// A longer first line is a sentence of the summary, not a title.
    static let maximumTitleWords = 12

    /// The first line is the title unless it is a section heading or a
    /// sentence. Lists use "- ", every heading uses "## ", and a section with
    /// nothing in it goes.
    static func parse(_ answer: String) -> (title: String?, body: String) {
        var lines = answer.components(separatedBy: .newlines)
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeFirst()
        }
        var title: String?
        if let first = lines.first,
           !first.trimmingCharacters(in: .whitespaces).hasPrefix("##"),
           let cleaned = cleanTitle(first),
           MeetingTranscript.words(in: cleaned).count <= maximumTitleWords {
            title = cleaned
            lines.removeFirst()
        }
        return (title, sections(lines.map(normalize)))
    }

    /// The title line and the first paragraph of an overview answer: a model
    /// that goes on after the paragraph repeats the notes.
    static func overview(_ answer: String) -> (title: String?, paragraph: String) {
        var lines = answer.components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces) }
            .drop { $0.isEmpty }
        var title: String?
        if let first = lines.first, first.lowercased().hasPrefix("title:") {
            title = cleanTitle(first)
            lines = lines.dropFirst()
        }
        let paragraph = lines
            .map(withoutParagraphLabel)
            .drop { $0.isEmpty || $0.hasPrefix("#") }
            .prefix { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("- ") && !$0.hasPrefix("* ") }
            .joined(separator: " ")
        return (title, completeSentences(paragraph))
    }

    /// Apple's model cuts an answer at its output limit with no error, so the
    /// paragraph can end in the middle of a sentence.
    private static func completeSentences(_ text: String) -> String {
        var end: String.Index?
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(after: index)
            let mark = text[index]
            // "2.4" has a point inside a sentence; a full-width mark needs no space.
            if ".!?…।".contains(mark), next == text.endIndex || text[next].isWhitespace {
                end = next
            } else if "。！？".contains(mark) {
                end = next
            }
            index = next
        }
        return end.map { String(text[..<$0]) } ?? text
    }

    /// "Overview: The team…" without "Overview:".
    private static func withoutParagraphLabel(_ line: String) -> String {
        for label in MeetingSummaryLayout.paragraphNames where line.lowercased().hasPrefix(label + ":") {
            return line.dropFirst(label.count + 1).trimmingCharacters(in: .whitespaces)
        }
        return line
    }

    private static func cleanTitle(_ line: String) -> String? {
        var title = line.trimmingCharacters(in: .whitespaces)
        while title.hasPrefix("#") {
            title.removeFirst()
        }
        title = title.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces)
        if title.lowercased().hasPrefix("title:") {
            title = String(title.dropFirst("title:".count))
        }
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: " \"'“”‘’").union(.whitespaces))
        while title.hasSuffix(".") {
            title.removeLast()
        }
        guard !title.isEmpty else { return nil }
        return String(title.prefix(maximumTitleLength))
    }

    private static func normalize(_ line: String) -> String {
        var line = line.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("#") {
            line = "## " + line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("* ") || line.hasPrefix("• ") {
            line = "- " + line.dropFirst(2)
        }
        return line
    }

    private static func sections(_ lines: [String]) -> String {
        var blocks: [(heading: String?, lines: [String])] = [(nil, [])]
        for line in lines {
            if line.hasPrefix("## ") {
                blocks.append((line, []))
            } else if !line.isEmpty {
                blocks[blocks.count - 1].lines.append(line)
            }
        }
        return blocks
            .map { block in
                guard let heading = block.heading else { return block }
                let topic = heading.dropFirst(3).trimmingCharacters(in: .whitespaces)
                return (heading, block.lines.filter { !saysNothing($0.hasPrefix("- ") ? String($0.dropFirst(2)) : $0, about: topic) })
            }
            .filter { !$0.lines.isEmpty }
            .map { block in ([block.heading].compactMap { $0 } + block.lines).joined(separator: "\n") }
            .joined(separator: "\n\n")
    }

    /// "None noted." in any section, or "No action items." or "No action
    /// items were discussed." in the "Action items" section.
    static func saysNothing(_ item: String, about section: String) -> Bool {
        let text = item.trimmingCharacters(in: CharacterSet(charactersIn: " .")).lowercased()
        if text.isEmpty || emptyPhrases.contains(text) {
            return true
        }
        let none = "no \(section.lowercased())"
        guard text.hasPrefix(none) else { return false }
        let rest = text.dropFirst(none.count).trimmingCharacters(in: .whitespaces)
        return rest.isEmpty || emptyTails.contains(rest)
    }

    private static let emptyPhrases: Set<String> = [
        "none", "none noted", "none mentioned", "none discussed", "none raised",
        "nothing", "nothing noted", "n/a", "not applicable", "not discussed",
    ]
    private static let emptyTails: Set<String> = [
        "discussed", "noted", "mentioned", "raised", "were discussed", "were noted", "were mentioned", "were raised",
    ]
}

extension MeetingRecord {
    /// Takes a summary's title only while the meeting has the placeholder
    /// title: a name that the user typed, or that an earlier summary gave,
    /// stays.
    mutating func adoptGeneratedTitle(_ generated: String?) {
        guard titleSource == .placeholder, let generated, !generated.isEmpty else { return }
        title = generated
        titleSource = .generated
    }
}
