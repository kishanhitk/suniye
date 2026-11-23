import Foundation

/// The spoken "new paragraph" command. Kept free of app types: the Apple eval
/// harness (evals/apple-magic-eval) compiles this file through a symlink.
enum MagicFormatParagraphBreaks {
    /// After one of these words, "new paragraph" is a noun phrase ("add a new
    /// paragraph"), not a command.
    private static let nounPhraseWords = [
        "a", "an", "the", "this", "that", "each", "every", "another", "any", "one", "no", "some", "more",
        "my", "your", "our", "their", "his", "her", "its",
        "whole", "entire", "short", "long", "next", "last", "first", "final", "brand", "separate", "fresh", "extra",
    ]

    /// Before one of these words, "new paragraph" names a thing ("new paragraph spacing").
    private static let nounFollowers = [
        "break", "breaks", "spacing", "style", "format", "formatting", "mark", "symbol", "tag",
        "setting", "button", "key", "command", "indent",
    ]

    private static let commandPattern = #"(?i)\s*"#
        + nounPhraseWords.map { #"(?<!\b\#($0) )"# }.joined()
        + #"\bnew\s+paragraph\b(?!\s+(?:"#
        + nounFollowers.joined(separator: "|")
        + #")\b)[\s,.;:]*"#

    /// The transcript with each spoken command replaced by one blank line.
    static func applied(to transcript: String) -> String {
        transcript
            .replacingOccurrences(of: commandPattern, with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// How many paragraph breaks the speaker dictated.
    static func dictatedCount(in transcript: String) -> Int {
        blankLineGapCount(in: applied(to: transcript))
    }

    /// Models often keep a dictated paragraph break as a single line break. Call this
    /// only for a transcript with no list cue: the output check then allows one line
    /// per paragraph, so when the answer has no blank line and one line break per
    /// dictated break, each line break is one of them and becomes a blank line.
    static func separatingParagraphs(in answer: String, dictatedCount: Int) -> String {
        guard dictatedCount > 0, blankLineGapCount(in: answer) == 0 else {
            return answer
        }
        let lines = answer.split(whereSeparator: \.isNewline)
        guard lines.count == dictatedCount + 1 else {
            return answer
        }
        return lines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n\n")
    }

    /// The models copy a lowercase word that follows a dictated break ("Hi Nora, new
    /// paragraph, the lease…"). A word with a capital inside ("iPhone") stays as is.
    static func capitalizingParagraphStarts(in text: String) -> String {
        var lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        for index in lines.indices.dropFirst() where isBlank(lines[index - 1][...]) && !isBlank(lines[index][...]) {
            let firstWord = lines[index].prefix { !$0.isWhitespace }
            guard let first = firstWord.first, first.isLowercase, !firstWord.contains(where: \.isUppercase) else {
                continue
            }
            lines[index] = first.uppercased() + lines[index].dropFirst()
        }
        return lines.joined(separator: "\n")
    }

    /// How many places in `text` have one or more empty lines between text lines.
    static func blankLineGapCount(in text: String) -> Int {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        return zip(lines, lines.dropFirst())
            .filter { !isBlank($0) && isBlank($1) }
            .count
    }

    static func isBlank(_ line: Substring) -> Bool {
        line.allSatisfy(\.isWhitespace)
    }
}
