import Foundation

/// Converts a Markdown-formatted model response into text fit for speech.
/// TTS reads markup literally ("asterisk asterisk"), so formatting is
/// stripped while the content and sentence flow are kept.
enum SpokenTextSanitizer {
    static func plainSpeech(from markdown: String) -> String {
        var text = markdown

        // Fenced code blocks: content is noise when spoken.
        text = text.replacingOccurrences(
            of: #"```[\s\S]*?```"#,
            with: " ",
            options: .regularExpression
        )
        // Images before links so the alt text survives.
        text = text.replacingOccurrences(
            of: #"!\[([^\]]*)\]\([^)]*\)"#,
            with: "$1",
            options: .regularExpression
        )
        // Links: keep the label, drop the URL.
        text = text.replacingOccurrences(
            of: #"\[([^\]]+)\]\([^)]*\)"#,
            with: "$1",
            options: .regularExpression
        )
        // Headings and blockquote markers at line starts.
        text = text.replacingOccurrences(
            of: #"(?m)^\s{0,3}(#{1,6}|>)\s*"#,
            with: "",
            options: .regularExpression
        )
        // List bullets and numbering become sentence-like pauses.
        text = text.replacingOccurrences(
            of: #"(?m)^\s*([-*+]|\d+[.)])\s+"#,
            with: "",
            options: .regularExpression
        )
        // Emphasis, inline code, and strikethrough markers.
        text = text.replacingOccurrences(
            of: #"[*_`~]{1,3}"#,
            with: "",
            options: .regularExpression
        )
        // Table pipes and horizontal rules.
        text = text.replacingOccurrences(
            of: #"(?m)^\s*[-|:\s]{3,}\s*$"#,
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(of: "|", with: ", ")

        // Collapse the leftover whitespace into speakable prose.
        text = text.replacingOccurrences(
            of: #"[ \t]+"#,
            with: " ",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"\n{2,}"#,
            with: ". ",
            options: .regularExpression
        )
        text = text.replacingOccurrences(of: "\n", with: ". ")
        // Adjacent sentence breaks left by removed blocks collapse into one.
        text = text.replacingOccurrences(
            of: #"\.(\s*\.)+"#,
            with: ".",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"\s{2,}"#,
            with: " ",
            options: .regularExpression
        )
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
