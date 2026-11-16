import Foundation

/// What the meetings list shows and searches for one meeting.
struct MeetingListText: Equatable, Sendable {
    /// The summary as plain text, without its headings.
    let summaryLines: [String]
    let notes: String
    /// The transcript's segment texts, in time order.
    let transcript: [String]

    init(summary: String?, notes: String, transcript: [String]) {
        summaryLines = summary.map(Self.contentLines) ?? []
        self.notes = notes
        self.transcript = transcript
    }

    /// The line under the meeting's title.
    func snippet(for status: MeetingStatus) -> String? {
        switch status {
        case .summaryFailed:
            return MeetingStatus.summaryFailedTitle + "."
        case .noSpeech:
            return MeetingStatus.noSpeechTitle + "."
        case .done:
            return summaryLines.first.map(Self.firstSentence)
        case .notTranscribed:
            return "No transcript yet."
        case .recording, .paused, .finishing, .summarizing, .interrupted:
            return transcript.first
        }
    }

    /// The first summary, notes or transcript line that contains `query`.
    func line(matching query: String) -> String? {
        let lines = summaryLines + notes.components(separatedBy: .newlines) + transcript
        return lines.first { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// Markdown as plain lines: one for each paragraph, list item and table
    /// cell, with no marks. Headings are no content. CommonMark joins the
    /// lines of one paragraph.
    private static func contentLines(of markdown: String) -> [String] {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
        let text = (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
        var items: Set<Int> = []
        return text.runs[\.presentationIntent].flatMap { intent, range -> [String] in
            let blocks = intent?.components ?? []
            let item = blocks.first { if case .listItem = $0.kind { true } else { false } }
            let opensItem = item.map { items.insert($0.identity).inserted } ?? false
            if blocks.contains(where: { if case .header = $0.kind { true } else { false } }) {
                return []
            }
            var block = text[range]
            if opensItem, case .paragraph = blocks.first?.kind {
                block = withoutTaskMarker(block)
            }
            return String(block.characters).components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
    }

    /// The first paragraph of a list item without a GFM task marker, which
    /// Foundation does not read.
    private static func withoutTaskMarker(_ paragraph: AttributedSubstring) -> AttributedSubstring {
        guard let first = paragraph.runs.first, first.inlinePresentationIntent?.contains(.code) != true else { return paragraph }
        let start = String(paragraph[first.range].characters)
        for marker in ["[ ] ", "[x] ", "[X] "] where start.hasPrefix(marker) {
            return paragraph[paragraph.index(paragraph.startIndex, offsetByCharacters: marker.count)...]
        }
        return paragraph
    }

    private static func firstSentence(of text: String) -> String {
        var sentence = text
        text.enumerateSubstrings(in: text.startIndex ..< text.endIndex, options: .bySentences) { substring, _, _, stop in
            if let substring {
                sentence = substring.trimmingCharacters(in: .whitespaces)
            }
            stop = true
        }
        return sentence
    }
}

enum MeetingDurationText {
    /// "1 min" at least, "38 min", "1 h 52 min", "2 h".
    static func text(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 {
            return "\(minutes) min"
        }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    /// "4 hours", "15 minutes", "1 hour, 30 minutes", in English like the
    /// rest of the app's copy.
    static func spelledOut(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.hour, .minute]
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        formatter.calendar = calendar
        return formatter.string(from: seconds) ?? text(seconds)
    }

    /// "42 minutes of audio from 10:02 AM are saved.": the recorded time,
    /// without the pauses, of a meeting that has no transcript yet.
    static func savedAudio(of record: MeetingRecord) -> String {
        let recorded = record.duration.map { MeetingTimeline(pauses: record.pauses).audioSeconds(forWallSeconds: $0) } ?? 0
        let minutes = max(1, Int((recorded / 60).rounded()))
        let time = record.startedAt.formatted(date: .omitted, time: .shortened)
        return "\(spelledOut(TimeInterval(minutes * 60))) of audio from \(time) \(minutes == 1 ? "is" : "are") saved."
    }
}
