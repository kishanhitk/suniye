import Foundation

/// What the meetings list shows and searches for one meeting.
struct MeetingListText: Equatable, Sendable {
    let summary: String?
    let notes: String
    /// The transcript's segment texts, in time order.
    let transcript: [String]

    /// The line under the meeting's title.
    func snippet(for status: MeetingStatus) -> String? {
        switch status {
        case .summaryFailed:
            return MeetingStatus.summaryFailedTitle + "."
        case .noSpeech:
            return MeetingStatus.noSpeechTitle + "."
        case .done:
            return summary.flatMap(Self.firstSentence)
        case .recording, .paused, .finishing, .summarizing, .interrupted:
            return transcript.first
        }
    }

    /// The first summary, notes or transcript line that contains `query`.
    func line(matching query: String) -> String? {
        let lines = Self.contentLines(of: summary ?? "") + notes.components(separatedBy: .newlines) + transcript
        return lines.first { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// A summary's list items and plain lines, without its headings.
    private static func contentLines(of summary: String) -> [String] {
        MeetingSummaryBlock.parse(summary).compactMap { block in
            switch block {
            case .heading:
                return nil
            case let .item(text), let .paragraph(text):
                return text
            }
        }
    }

    /// The first sentence of the first plain line of a summary body.
    static func firstSentence(of summary: String) -> String? {
        guard let text = contentLines(of: summary).first else { return nil }
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
}
