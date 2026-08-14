import Foundation

enum ComputerUseTextSelectionResolver {
    static func resolve(
        text: String,
        prefix: String?,
        suffix: String?,
        selectionType: ComputerUseTextSelectionType,
        in value: String
    ) throws -> CFRange {
        let matches = matchingRanges(text: text, prefix: prefix, suffix: suffix, in: value)
        guard !matches.isEmpty else {
            throw ComputerUseActionError.textNotFound(text)
        }
        guard matches.count == 1, let match = matches.first else {
            throw ComputerUseActionError.textAmbiguous(text)
        }

        return switch selectionType {
        case .text:
            CFRange(location: match.location, length: match.length)
        case .cursorBefore:
            CFRange(location: match.location, length: 0)
        case .cursorAfter:
            CFRange(location: match.location + match.length, length: 0)
        }
    }

    private static func matchingRanges(
        text: String,
        prefix: String?,
        suffix: String?,
        in value: String
    ) -> [NSRange] {
        let source = value as NSString
        let targetLength = (text as NSString).length
        var searchLocation = 0
        var results: [NSRange] = []

        while searchLocation <= source.length - targetLength {
            let range = source.range(
                of: text,
                options: [],
                range: NSRange(location: searchLocation, length: source.length - searchLocation)
            )
            guard range.location != NSNotFound else {
                break
            }
            if context(prefix, matchesBefore: range, in: source),
               context(suffix, matchesAfter: range, in: source) {
                results.append(range)
            }
            searchLocation = range.location + max(range.length, 1)
        }
        return results
    }

    private static func context(
        _ expected: String?,
        matchesBefore range: NSRange,
        in source: NSString
    ) -> Bool {
        guard let expected else { return true }
        let length = (expected as NSString).length
        guard range.location >= length else { return false }
        return source.substring(
            with: NSRange(location: range.location - length, length: length)
        ) == expected
    }

    private static func context(
        _ expected: String?,
        matchesAfter range: NSRange,
        in source: NSString
    ) -> Bool {
        guard let expected else { return true }
        let location = range.location + range.length
        let length = (expected as NSString).length
        guard location + length <= source.length else { return false }
        return source.substring(with: NSRange(location: location, length: length)) == expected
    }
}
