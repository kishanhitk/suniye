import Foundation

// Faithful port of the scoring in scripts/eval_magic_format.py so Apple scores
// line up with the Gemma version table. Operates on Unicode scalars to match
// Python str's code-point semantics (Swift's Character is a grapheme cluster,
// which would diverge on the difflib ratio and flip pass/fail near threshold).

enum Scoring {
    /// Mirrors python normalize(): strip, curly apostrophe -> ', en dash -> -,
    /// collapse runs of spaces/tabs to one space, collapse 2+ newlines to one.
    static func normalize(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.replacingOccurrences(of: "\u{2019}", with: "'")
        value = value.replacingOccurrences(of: "\u{2013}", with: "-")
        value = value.replacingOccurrences(of: "[ \t]+", with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: "\n{2,}", with: "\n", options: .regularExpression)
        return value
    }

    /// Mirrors python normalize_list_text(): normalize, lowercase, strip trailing . or :
    static func normalizeListText(_ text: String) -> String {
        var value = normalize(text).lowercased()
        value = value.replacingOccurrences(of: "[\\.:]+$", with: "", options: .regularExpression)
        return value
    }

    struct LineToken: Equatable {
        let kind: String
        let text: String
    }

    /// Mirrors python line_signature().
    static func lineSignature(_ text: String) -> [LineToken] {
        var signature: [LineToken] = []
        // python splitlines() on the normalized text, then strip each line.
        for rawLine in normalize(text).components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if let numbered = numberedListBody(line) {
                signature.append(LineToken(kind: "numbered", text: normalizeListText(numbered)))
            } else if line.hasPrefix("- ") {
                signature.append(LineToken(kind: "bullet", text: normalizeListText(String(line.dropFirst(2)))))
            } else {
                signature.append(LineToken(kind: "text", text: normalizeListText(line)))
            }
        }
        return signature
    }

    /// Manual equivalent of python's ^(\d+)\.\s+(.*)$ — returns the body after
    /// "<digits>. " (one or more spaces required), or nil if it doesn't match.
    private static func numberedListBody(_ line: String) -> String? {
        var idx = line.startIndex
        var sawDigit = false
        while idx < line.endIndex, line[idx].isNumber {
            sawDigit = true
            idx = line.index(after: idx)
        }
        guard sawDigit, idx < line.endIndex, line[idx] == "." else { return nil }
        idx = line.index(after: idx)
        let afterDot = idx
        while idx < line.endIndex, line[idx] == " " || line[idx] == "\t" {
            idx = line.index(after: idx)
        }
        guard idx > afterDot else { return nil } // \s+ requires at least one space
        return String(line[idx...])
    }

    /// Mirrors python list_structure_matches(): only enforced when expected is multi-line.
    static func listStructureMatches(actual: String, expected: String) -> Bool {
        if !expected.contains("\n") {
            return true
        }
        return lineSignature(actual) == lineSignature(expected)
    }

    struct Score {
        let exact: Bool
        let similarity: Double
        let structureMatches: Bool
    }

    /// Mirrors python score_output().
    static func score(actual: String, expected: String) -> Score {
        let actualNorm = normalize(actual)
        let expectedNorm = normalize(expected)
        let structureMatches = listStructureMatches(actual: actual, expected: expected)
        if actualNorm == expectedNorm {
            return Score(exact: true, similarity: 1.0, structureMatches: structureMatches)
        }
        let similarity = SequenceMatcher(a: actualNorm.lowercased(), b: expectedNorm.lowercased()).ratio()
        return Score(exact: false, similarity: similarity, structureMatches: structureMatches)
    }
}

/// Faithful port of the ratio-relevant parts of Python's difflib.SequenceMatcher
/// (isjunk=None, autojunk=True). ratio() = 2*M / T where M is the total size of
/// the matching blocks and T is the combined length of both sequences.
struct SequenceMatcher {
    private let a: [Unicode.Scalar]
    private let b: [Unicode.Scalar]
    private var b2j: [Unicode.Scalar: [Int]] = [:]

    init(a: String, b: String) {
        self.a = Array(a.unicodeScalars)
        self.b = Array(b.unicodeScalars)
        chainB()
    }

    // Build b2j (element -> sorted indices in b). isjunk is None here, so no
    // junk set. Replicates difflib's autojunk: for len(b) >= 200, elements
    // occurring more than len(b)//100 + 1 times are dropped as "popular".
    private mutating func chainB() {
        for (i, elt) in b.enumerated() {
            b2j[elt, default: []].append(i)
        }
        let n = b.count
        if n >= 200 {
            let ntest = n / 100 + 1
            var popular: Set<Unicode.Scalar> = []
            for (elt, idxs) in b2j where idxs.count > ntest {
                popular.insert(elt)
            }
            for elt in popular {
                b2j.removeValue(forKey: elt)
            }
        }
    }

    private struct Match {
        let i: Int
        let j: Int
        let size: Int
    }

    private func findLongestMatch(_ alo: Int, _ ahi: Int, _ blo: Int, _ bhi: Int) -> Match {
        var besti = alo, bestj = blo, bestsize = 0
        var j2len: [Int: Int] = [:]
        for i in alo..<ahi {
            var newj2len: [Int: Int] = [:]
            for j in b2j[a[i], default: []] {
                if j < blo { continue }
                if j >= bhi { break }
                let k = (j2len[j - 1] ?? 0) + 1
                newj2len[j] = k
                if k > bestsize {
                    besti = i - k + 1
                    bestj = j - k + 1
                    bestsize = k
                }
            }
            j2len = newj2len
        }
        // No junk, so only the pure-match extension phases apply.
        while besti > alo, bestj > blo, a[besti - 1] == b[bestj - 1] {
            besti -= 1; bestj -= 1; bestsize += 1
        }
        while besti + bestsize < ahi, bestj + bestsize < bhi,
              a[besti + bestsize] == b[bestj + bestsize] {
            bestsize += 1
        }
        return Match(i: besti, j: bestj, size: bestsize)
    }

    // Total matched size across all recursively-found matching blocks.
    private func totalMatches() -> Int {
        var total = 0
        var queue: [(Int, Int, Int, Int)] = [(0, a.count, 0, b.count)]
        while let (alo, ahi, blo, bhi) = queue.popLast() {
            let m = findLongestMatch(alo, ahi, blo, bhi)
            if m.size > 0 {
                total += m.size
                if alo < m.i, blo < m.j {
                    queue.append((alo, m.i, blo, m.j))
                }
                if m.i + m.size < ahi, m.j + m.size < bhi {
                    queue.append((m.i + m.size, ahi, m.j + m.size, bhi))
                }
            }
        }
        return total
    }

    func ratio() -> Double {
        let length = a.count + b.count
        if length == 0 { return 1.0 }
        return 2.0 * Double(totalMatches()) / Double(length)
    }
}
