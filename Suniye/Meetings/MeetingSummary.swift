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

    /// Apple Intelligence when it is ready, else the local model when it is
    /// installed.
    init(apple: AppleFoundationModelsAvailability, localModel: LocalGemmaAvailability) {
        if apple.isAvailable {
            self = .ready(.appleIntelligence)
        } else if localModel.isAvailable {
            self = .ready(.localModel)
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
        /// Notes on part `number` of the `count` parts of a transcript.
        case part(number: Int, count: Int)
        /// One shorter set of notes from the notes on several parts.
        case join
    }

    let kind: Kind
    let instructions: String
    let input: String

    var maxOutputTokens: Int {
        kind == .summary ? MeetingSummaryWriter.summaryOutputTokens : MeetingSummaryWriter.partOutputTokens
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
            return "Too little speech to summarize"
        case let .failed(cause):
            return cause
        }
    }
}

/// Writes a meeting's summary with one on-device model.
///
/// A transcript that fits in one request goes in one request. A longer one is
/// cut into parts at segment edges; each part becomes short notes, and a last
/// request writes the summary from the notes of all parts. When those notes
/// do not fit either, they are first joined in groups. The answer to each
/// request is kept: a summary that a dictation stopped goes on where it
/// stopped, and a new template reuses the notes on the parts.
actor MeetingSummaryWriter {
    static let minimumWords = 25
    static let summaryOutputTokens = 1_200
    static let partOutputTokens = 500
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

    func write(_ input: MeetingSummaryInput) async throws -> MeetingSummary {
        let notes = input.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let spokenWords = input.segments.reduce(0) { $0 + MeetingTranscript.words(in: $1.text).count }
        guard spokenWords >= Self.minimumWords || !notes.isEmpty else {
            throw MeetingSummaryError.tooLittleSpeech
        }

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

    // MARK: - Parts

    private func notesOnParts(_ input: MeetingSummaryInput, context: Int) async throws -> [String] {
        let segments = MeetingTranscript.ordered(input.segments)
        let fullText = MeetingTranscript.turns(segments, timeline: nil, speakerLabels: input.speakerLabels).joined(separator: "\n")
        let tokensPerCharacter = Double(await tokens(in: fullText)) / Double(max(1, fullText.count))
        let overhead = await tokens(in: MeetingSummaryPrompt.part(transcript: "", number: 1, of: 1, speakerLabels: input.speakerLabels).text)
        let room = Double(budget(context: context, output: Self.partOutputTokens) - overhead)

        var parts: [[MeetingSegment]] = []
        var current: [MeetingSegment] = []
        var used = 0.0
        for segment in segments {
            // A segment costs its text, a label and a line break.
            let cost = Double(segment.text.count + 7) * tokensPerCharacter
            if !current.isEmpty, used + cost > room {
                parts.append(current)
                current = []
                used = 0
            }
            current.append(segment)
            used += cost
        }
        if !current.isEmpty {
            parts.append(current)
        }

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
            // A canceled HTTP request surfaces as a network error.
            if Task.isCancelled {
                throw CancellationError()
            }
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

/// The text of each request. The model reads one message: the rules first,
/// then the data in tags.
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
            Decisions:
            Tasks:
            Dates and numbers:
            Open questions:

            Rules:
            - After each label, write the items on the same line, separated by "; ". Write "none" when there is none.
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
            Decisions:
            Tasks:
            Dates and numbers:
            Open questions:

            Rules:
            - After each label, write the items on the same line, separated by "; ". Write "none" when there is none.
            - Keep every decision, every task with who does it, every date and number, and every open question.
            - Remove repeats.
            - Write in the language of the notes.
            """
        )
    }

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

    private static func speakerRule(_ speakerLabels: Bool) -> String {
        speakerLabels
            ? "- \"You\" is the user. \"Them\" is the other people on the call."
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
                return (heading, block.lines.filter { !saysNothing($0, under: heading) })
            }
            .filter { !$0.lines.isEmpty }
            .map { block in ([block.heading].compactMap { $0 } + block.lines).joined(separator: "\n") }
            .joined(separator: "\n\n")
    }

    /// "- None noted." under any heading, or "- No action items." under
    /// "## Action items".
    private static func saysNothing(_ line: String, under heading: String) -> Bool {
        var text = line.hasPrefix("- ") ? String(line.dropFirst(2)) : line
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " .")).lowercased()
        let topic = heading.dropFirst(3).trimmingCharacters(in: .whitespaces).lowercased()
        return emptyPhrases.contains(text) || text == "no \(topic)"
    }

    private static let emptyPhrases: Set<String> = [
        "none", "none noted", "none mentioned", "none discussed", "none raised",
        "nothing", "nothing noted", "n/a", "not applicable", "not discussed",
    ]
}

extension MeetingRecord {
    /// Takes a summary's title only while the meeting has the placeholder
    /// title, so a name that the user typed stays.
    mutating func adoptGeneratedTitle(_ generated: String?) {
        guard titleSource == .placeholder, let generated, !generated.isEmpty else { return }
        title = generated
        titleSource = .generated
    }
}
