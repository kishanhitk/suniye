import Foundation

extension String {
    /// Word count that also works for scripts written without spaces. A
    /// whitespace split counts a whole Japanese or Chinese sentence as one word
    /// (measured: 1 vs 17 and 1 vs 9), and Suniye ships multilingual recognizers.
    /// `.byWords` segments by the locale's rules and is faster than splitting.
    var dictationWordCount: Int {
        var count = 0
        enumerateSubstrings(in: startIndex..., options: [.byWords, .localized]) { _, _, _, _ in
            count += 1
        }
        return count
    }
}

struct RecentResult: Identifiable, Equatable, Codable {
    let id: UUID
    let text: String
    /// The transcript before Magic Format changed it; nil when `text` is the
    /// transcript as spoken, and for history written before this existed.
    let rawText: String?
    let createdAt: Date
    let durationSeconds: TimeInterval
    let wasLLMPolished: Bool
    /// Where the dictation was inserted. Optional because history written before
    /// this existed has no source app — those rows decode with nil rather than
    /// failing, and simply show no app.
    var appBundleID: String?

    var wordCount: Int {
        text.dictationWordCount
    }

    init(
        id: UUID,
        text: String,
        createdAt: Date,
        durationSeconds: TimeInterval,
        wasLLMPolished: Bool,
        appBundleID: String? = nil,
        rawText: String? = nil
    ) {
        self.id = id
        self.text = text
        self.rawText = rawText
        self.createdAt = createdAt
        self.durationSeconds = durationSeconds
        self.wasLLMPolished = wasLLMPolished
        self.appBundleID = appBundleID
    }
}
