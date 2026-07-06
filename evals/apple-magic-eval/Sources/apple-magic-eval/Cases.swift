import Foundation

// Case schema matches the shared JSON files consumed by scripts/eval_magic_format.py
// (id, category, input, expected). Loaded verbatim so both harnesses score the
// same suite.
struct EvalCase: Codable {
    let id: String
    let category: String
    let input: String
    let expected: String
}

enum CaseLoader {
    static func load(_ url: URL) throws -> [EvalCase] {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([EvalCase].self, from: data)
    }
}
