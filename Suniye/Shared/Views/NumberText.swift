import AppKit
import SwiftUI

/// Splits UI text into numbers and the text between them, so that numbers can
/// show in the mono font.
///
/// A number is a run of digits, with a `.`, `,` or `:` between two digits and a
/// `%` directly after: "1,204", "0.0.75", "12:04", "45%". Digits that end a
/// word are part of a name ("Qwen3", "Q4_K_M"), except after a version "v"
/// ("v3", "v0.0.75").
enum NumberRuns {
    struct Run: Equatable {
        let text: String
        let isNumber: Bool
    }

    static func split(_ string: String) -> [Run] {
        let characters = Array(string)
        var runs: [Run] = []
        var plain = ""
        var index = 0

        while index < characters.count {
            guard characters[index].isASCIIDigit else {
                plain.append(characters[index])
                index += 1
                continue
            }

            let end = numberEnd(in: characters, from: index)
            let text = String(characters[index ..< end])
            if isPartOfWord(characters, before: index) {
                plain += text
            } else {
                if !plain.isEmpty {
                    runs.append(Run(text: plain, isNumber: false))
                    plain = ""
                }
                runs.append(Run(text: text, isNumber: true))
            }
            index = end
        }

        if !plain.isEmpty {
            runs.append(Run(text: plain, isNumber: false))
        }
        return runs
    }

    /// The text with its numbers in the mono design of `font`'s size and `weight`.
    static func attributed(_ string: String, font: NSFont, weight: NSFont.Weight = .regular) -> NSAttributedString {
        let mono = NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: weight)
        let output = NSMutableAttributedString()
        for run in split(string) {
            output.append(NSAttributedString(string: run.text, attributes: [.font: run.isNumber ? mono : font]))
        }
        return output
    }

    private static let separators: Set<Character> = [".", ",", ":"]

    private static func numberEnd(in characters: [Character], from start: Int) -> Int {
        var end = start
        while end < characters.count {
            if characters[end].isASCIIDigit {
                end += 1
            } else if separators.contains(characters[end]), end + 1 < characters.count, characters[end + 1].isASCIIDigit {
                end += 2
            } else {
                break
            }
        }
        if end < characters.count, characters[end] == "%" {
            end += 1
        }
        return end
    }

    private static func isPartOfWord(_ characters: [Character], before index: Int) -> Bool {
        guard index > 0, characters[index - 1].isLetter else {
            return false
        }
        let isVersionPrefix = characters[index - 1].lowercased() == "v"
            && (index == 1 || !characters[index - 2].isLetter)
        return !isVersionPrefix
    }
}

private extension Character {
    var isASCIIDigit: Bool {
        isASCII && isNumber
    }
}

extension Text {
    /// App text with its numbers in the mono design. The other text keeps the
    /// font of the view. Text that the user wrote does not use this.
    init(numbers string: String) {
        let runs = NumberRuns.split(string)
        guard runs.contains(where: \.isNumber) else {
            self.init(verbatim: string)
            return
        }
        self = runs.reduce(Text(verbatim: "")) { text, run in
            let piece = Text(verbatim: run.text)
            return Text("\(text)\(run.isNumber ? piece.monospaced() : piece)")
        }
    }
}
