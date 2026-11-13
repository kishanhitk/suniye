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
            return "Couldn’t write the summary."
        case .noSpeech:
            return "Too little speech to summarize."
        case .done:
            return summary.flatMap(Self.firstSentence)
        case .recording, .paused, .finishing, .summarizing, .interrupted:
            return transcript.first
        }
    }

    /// The first summary, notes or transcript line that contains `query`.
    func line(matching query: String) -> String? {
        let summaryLines = (summary ?? "")
            .components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("## ") }
            .map { $0.hasPrefix("- ") ? String($0.dropFirst(2)) : $0 }
        let lines = summaryLines + notes.components(separatedBy: .newlines) + transcript
        return lines.first { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// The first sentence of the first plain line of a summary body.
    static func firstSentence(of summary: String) -> String? {
        guard let line = summary
            .components(separatedBy: .newlines)
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { !$0.isEmpty && !$0.hasPrefix("## ") })
        else { return nil }
        let text = line.hasPrefix("- ") ? String(line.dropFirst(2)) : line
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
}
