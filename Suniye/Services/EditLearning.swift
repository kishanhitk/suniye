import Foundation

struct WordSubstitution: Equatable {
    let original: String
    let replacement: String
}

/// Word-level diff between the field value captured right after insertion and a
/// later re-read, scoped to words that came from the inserted transcription.
enum TranscriptionEditDiff {
    static func substitutions(
        insertedText: String,
        baseline: String,
        current: String
    ) -> [WordSubstitution] {
        guard baseline != current else {
            return []
        }

        let baselineWords = tokenize(baseline)
        let currentWords = tokenize(current)
        let insertedWords = Set(tokenize(insertedText))

        var substitutions: [WordSubstitution] = []
        for block in changedBlocks(from: baselineWords, to: currentWords) {
            for (original, replacement) in zip(block.removed, block.added)
            where original != replacement && insertedWords.contains(original) {
                substitutions.append(WordSubstitution(original: original, replacement: replacement))
            }
        }
        return substitutions
    }

    private struct ChangedBlock {
        var removed: [String] = []
        var added: [String] = []
    }

    private static func changedBlocks(from old: [String], to new: [String]) -> [ChangedBlock] {
        var lcsLength = [[Int]](repeating: [Int](repeating: 0, count: new.count + 1), count: old.count + 1)
        for oldIndex in stride(from: old.count - 1, through: 0, by: -1) {
            for newIndex in stride(from: new.count - 1, through: 0, by: -1) {
                if old[oldIndex] == new[newIndex] {
                    lcsLength[oldIndex][newIndex] = lcsLength[oldIndex + 1][newIndex + 1] + 1
                } else {
                    lcsLength[oldIndex][newIndex] = max(lcsLength[oldIndex + 1][newIndex], lcsLength[oldIndex][newIndex + 1])
                }
            }
        }

        var blocks: [ChangedBlock] = []
        var pending = ChangedBlock()
        var oldIndex = 0
        var newIndex = 0

        func closePendingBlock() {
            if !pending.removed.isEmpty || !pending.added.isEmpty {
                blocks.append(pending)
                pending = ChangedBlock()
            }
        }

        while oldIndex < old.count, newIndex < new.count {
            if old[oldIndex] == new[newIndex] {
                closePendingBlock()
                oldIndex += 1
                newIndex += 1
            } else if lcsLength[oldIndex + 1][newIndex] >= lcsLength[oldIndex][newIndex + 1] {
                pending.removed.append(old[oldIndex])
                oldIndex += 1
            } else {
                pending.added.append(new[newIndex])
                newIndex += 1
            }
        }
        pending.removed.append(contentsOf: old[oldIndex...])
        pending.added.append(contentsOf: new[newIndex...])
        closePendingBlock()

        return blocks
    }

    private static func tokenize(_ text: String) -> [String] {
        text.matches(of: /[\p{L}\p{N}]+(?:['’-][\p{L}\p{N}]+)*/).map { String($0.output) }
    }
}

/// Decides which word substitutions are transcription corrections worth learning,
/// as opposed to the user simply changing their mind about content.
enum CorrectionClassifier {
    static let minimumTermLength = 3
    static let similarityThreshold = 0.6
    static let maximumTermsPerSession = 3

    static func learnableTerms(
        from substitutions: [WordSubstitution],
        existingVocabulary: [String],
        isKnownWord: (String) -> Bool,
        maxTerms: Int = maximumTermsPerSession
    ) -> [String] {
        let vocabulary = Set(existingVocabulary.map { $0.lowercased() })
        var terms: [String] = []

        for substitution in substitutions {
            guard terms.count < maxTerms else {
                break
            }
            let term = substitution.replacement
            guard term.count >= minimumTermLength,
                  !vocabulary.contains(term.lowercased()),
                  !terms.contains(where: { $0.caseInsensitiveCompare(term) == .orderedSame }),
                  isProperNounLike(substitution, isKnownWord: isKnownWord),
                  phoneticSimilarity(substitution.original, term) >= similarityThreshold else {
                continue
            }
            terms.append(term)
        }
        return terms
    }

    private static func isProperNounLike(
        _ substitution: WordSubstitution,
        isKnownWord: (String) -> Bool
    ) -> Bool {
        let replacement = substitution.replacement
        // A pure case change of a dictionary word ("the" -> "The") is formatting, not vocabulary.
        if substitution.original.lowercased() == replacement.lowercased() {
            return !isKnownWord(replacement)
        }
        if replacement.contains(where: \.isNumber) {
            return true
        }
        if !isKnownWord(replacement) {
            return true
        }
        let letters = replacement.filter(\.isLetter)
        let isAcronym = letters.count >= 2 && letters.allSatisfy(\.isUppercase)
        let hasInteriorUppercase = replacement.dropFirst().contains(where: \.isUppercase)
        let isCapitalized = replacement.first?.isUppercase == true
            && replacement.dropFirst().contains(where: \.isLowercase)
        return isAcronym || hasInteriorUppercase || isCapitalized
    }

    static func phoneticSimilarity(_ first: String, _ second: String) -> Double {
        let firstSkeleton = phoneticSkeleton(first)
        let secondSkeleton = phoneticSkeleton(second)
        guard !firstSkeleton.isEmpty || !secondSkeleton.isEmpty else {
            return first.lowercased() == second.lowercased() ? 1.0 : 0.0
        }
        let distance = levenshteinDistance(firstSkeleton, secondSkeleton)
        let maxLength = max(firstSkeleton.count, secondSkeleton.count)
        return 1.0 - Double(distance) / Double(maxLength)
    }

    /// Collapses a word to a rough consonant skeleton so that different spellings
    /// of the same sound ("Keshawn"/"Kishan") compare as near-identical.
    private static func phoneticSkeleton(_ word: String) -> [Character] {
        var normalized = word.lowercased().filter(\.isLetter)
        for (digraph, replacement) in [("ph", "f"), ("ck", "k"), ("ch", "k"), ("sh", "s"), ("th", "t"), ("gh", "g")] {
            normalized = normalized.replacingOccurrences(of: digraph, with: replacement)
        }

        let dropped: Set<Character> = ["a", "e", "i", "o", "u", "h", "w", "y"]
        let mapped: [Character: String] = ["c": "k", "q": "k", "z": "s", "x": "ks"]

        var skeleton: [Character] = []
        for (index, character) in normalized.enumerated() {
            if index > 0, dropped.contains(character) {
                continue
            }
            let substitute = mapped[character].map(Array.init) ?? [character]
            if let last = skeleton.last, substitute.first == last {
                skeleton.append(contentsOf: substitute.dropFirst())
            } else {
                skeleton.append(contentsOf: substitute)
            }
        }
        return skeleton
    }

    private static func levenshteinDistance(_ first: [Character], _ second: [Character]) -> Int {
        guard !first.isEmpty else { return second.count }
        guard !second.isEmpty else { return first.count }

        var previousRow = Array(0 ... second.count)
        for (firstIndex, firstCharacter) in first.enumerated() {
            var currentRow = [firstIndex + 1]
            for (secondIndex, secondCharacter) in second.enumerated() {
                let substitutionCost = firstCharacter == secondCharacter ? 0 : 1
                currentRow.append(min(
                    previousRow[secondIndex] + substitutionCost,
                    previousRow[secondIndex + 1] + 1,
                    currentRow[secondIndex] + 1
                ))
            }
            previousRow = currentRow
        }
        return previousRow[second.count]
    }
}
