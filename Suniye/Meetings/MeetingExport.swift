import Foundation

/// A meeting as text, for Copy and for Export as Markdown.
enum MeetingExport {
    /// One line per turn, with its wall-clock time and, when the meeting had
    /// a call track, its speaker.
    static func transcript(record: MeetingRecord, segments: [MeetingSegment]) -> String {
        MeetingTranscript.turns(
            segments,
            timeline: MeetingTimeline(pauses: record.pauses),
            speakerLabels: record.hasCallTrack
        )
        .joined(separator: "\n")
    }

    static func markdown(record: MeetingRecord, summary: String?, notes: String, segments: [MeetingSegment]) -> String {
        var parts = ["# \(record.title)"]
        if let summary, !summary.isEmpty {
            parts.append(summary)
        }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty {
            parts.append("## Notes\n\(trimmedNotes)")
        }
        let transcript = transcript(record: record, segments: segments)
        if !transcript.isEmpty {
            parts.append("## Transcript\n\(transcript)")
        }
        return parts.joined(separator: "\n\n") + "\n"
    }
}

/// One block of a summary for the meeting page.
enum MeetingSummaryBlock: Equatable {
    case heading(String)
    case item(String)
    case paragraph(String)

    static func parse(_ markdown: String) -> [MeetingSummaryBlock] {
        markdown.components(separatedBy: .newlines).compactMap { line in
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.isEmpty {
                return nil
            }
            if let heading = headingText(text) {
                return .heading(heading)
            }
            if text.hasPrefix("- ") {
                return .item(String(text.dropFirst(2)))
            }
            return .paragraph(text)
        }
    }

    /// The text of a `#` to `######` heading line.
    private static func headingText(_ line: String) -> String? {
        let marks = line.prefix { $0 == "#" }.count
        guard (1 ... 6).contains(marks), line.dropFirst(marks).first == " " else { return nil }
        return String(line.dropFirst(marks + 1))
    }
}
