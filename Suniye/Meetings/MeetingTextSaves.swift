import Foundation

/// A part of a meeting that the user edits on its page.
enum MeetingTextPart: Hashable, CaseIterable {
    case title
    case notes
    case summary
    case transcript
}

/// The saves of the text that the user edits on a meeting page. A burst of
/// typing writes once, after a short pause; a page change writes at once; a
/// quit waits for every save. The saves of one part run in the order they
/// were asked for, so an older text never lands after a newer one.
@MainActor
final class MeetingTextSaves {
    private struct Key: Hashable {
        let meetingID: UUID
        let part: MeetingTextPart
    }

    private struct Waiting {
        let save: () async -> Void
        let timer: Task<Void, Never>
    }

    private struct Running {
        let token: UUID
        let task: Task<Void, Never>
    }

    private let pause: Duration
    private var waiting: [Key: Waiting] = [:]
    private var running: [Key: Running] = [:]

    init(pause: Duration = .milliseconds(750)) {
        self.pause = pause
    }

    /// Nothing waits and nothing runs.
    var isIdle: Bool {
        waiting.isEmpty && running.isEmpty
    }

    /// Keeps the newest text of a part. It saves after the pause, unless more
    /// typing comes first.
    func stage(_ part: MeetingTextPart, of meetingID: UUID, save: @escaping () async -> Void) {
        let key = Key(meetingID: meetingID, part: part)
        waiting[key]?.timer.cancel()
        let pause = pause
        let timer = Task { [weak self] in
            try? await Task.sleep(for: pause)
            guard !Task.isCancelled else { return }
            self?.start(key)
        }
        waiting[key] = Waiting(save: save, timer: timer)
    }

    /// Saves a part now, with no pause: an edit that ended, such as a title
    /// after Return.
    func save(_ part: MeetingTextPart, of meetingID: UUID, save: @escaping () async -> Void) {
        stage(part, of: meetingID, save: save)
        start(Key(meetingID: meetingID, part: part))
    }

    /// Starts the waiting saves of one meeting: its page goes away or shows
    /// another tab.
    func saveNow(_ meetingID: UUID) {
        for key in waiting.keys where key.meetingID == meetingID {
            start(key)
        }
    }

    /// Starts every waiting save and returns when no save runs: a quit.
    func finish() async {
        for key in waiting.keys {
            start(key)
        }
        while let next = running.values.first {
            await next.task.value
        }
    }

    private func start(_ key: Key) {
        guard let entry = waiting.removeValue(forKey: key) else { return }
        entry.timer.cancel()
        let previous = running[key]?.task
        let token = UUID()
        let task = Task { [weak self] in
            await previous?.value
            await entry.save()
            if self?.running[key]?.token == token {
                self?.running[key] = nil
            }
        }
        running[key] = Running(token: token, task: task)
    }
}
