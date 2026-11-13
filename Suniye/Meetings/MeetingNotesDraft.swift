import Foundation

/// The notes that the user edits on a meeting page. Only an edit saves, so
/// notes that failed to load are never written over.
struct MeetingNotesDraft: Equatable {
    var text: String
    private var savedText: String

    init(saved: String) {
        text = saved
        savedText = saved
    }

    /// The text to save, or nil when it is saved already.
    mutating func takeUnsaved() -> String? {
        guard text != savedText else { return nil }
        savedText = text
        return text
    }
}
