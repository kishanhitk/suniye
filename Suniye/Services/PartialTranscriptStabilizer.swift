import Foundation

/// Smooths successive partial decodes for the live preview. Each tick re-decodes
/// the audio from scratch, so earlier words can be rewritten retroactively and the
/// displayed text churns. When the new hypothesis still agrees with most of what
/// was already shown, keep the shown prefix verbatim and append only the new tail;
/// when it diverges drastically, accept the rewrite wholesale.
enum PartialTranscriptStabilizer {
    static func stabilize(previous: String, current: String) -> String {
        let previousWords = words(of: previous)
        guard !previousWords.isEmpty else {
            return current
        }
        let currentWords = words(of: current)

        var commonPrefixLength = 0
        for (previousWord, currentWord) in zip(previousWords, currentWords) {
            guard normalized(previousWord) == normalized(currentWord) else {
                break
            }
            commonPrefixLength += 1
        }

        guard commonPrefixLength > previousWords.count / 2 else {
            return current
        }
        return (previousWords.prefix(commonPrefixLength) + currentWords.dropFirst(commonPrefixLength))
            .joined(separator: " ")
    }

    private static func words(of text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)
    }

    /// Words match case-insensitively, ignoring leading/trailing punctuation, so a
    /// re-decode that only flips casing or commas does not count as divergence.
    private static func normalized(_ word: String) -> String {
        word.trimmingCharacters(in: .punctuationCharacters).lowercased()
    }
}
