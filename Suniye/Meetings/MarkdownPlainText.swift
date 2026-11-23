import Foundation

/// Markdown read by Foundation's CommonMark reader, as plain text.
enum MarkdownPlainText {
    /// Markdown as plain lines, with no marks: each heading, list item and
    /// table cell, and each line of a paragraph, as the editor shows it.
    static func lines(of markdown: String, headings: Bool) -> [String] {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
        let text = (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
        var items: Set<Int> = []
        return text.runs[\.presentationIntent].flatMap { intent, range -> [String] in
            let blocks = intent?.components ?? []
            let item = blocks.first { if case .listItem = $0.kind { true } else { false } }
            let opensItem = item.map { items.insert($0.identity).inserted } ?? false
            if !headings, blocks.contains(where: { if case .header = $0.kind { true } else { false } }) {
                return []
            }
            var block = text[range]
            if opensItem, case .paragraph = blocks.first?.kind {
                block = withoutTaskMarker(block)
            }
            let plain = block.runs.map { run in
                run.inlinePresentationIntent?.contains(.softBreak) == true ? "\n" : String(block[run.range].characters)
            }
            return plain.joined().components(separatedBy: .newlines)
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
}
