import AppKit
import Foundation

struct EditLearningSession {
    let insertedText: String
    let fieldValueAfterInsertion: String?
    let existingVocabulary: [String]
    let readCurrentFieldValue: () -> String?
}

@MainActor
protocol EditLearningServiceProtocol: AnyObject {
    var onLearnedTerms: (([String]) -> Void)? { get set }
    /// Reports, once per finalized session, how much of the inserted dictation
    /// the user corrected — a coarse 0...100 bucket (content-free), used as an
    /// ASR/cleanup accuracy signal.
    var onEditRate: ((Int) -> Void)? { get set }
    func beginTracking(_ session: EditLearningSession)
    func finalizeActiveSession()
}

/// Watches the text field a dictation was inserted into and learns vocabulary
/// from the user's manual corrections. Re-reads the field at fixed checkpoints
/// and on terminal events (app switch, next dictation) instead of observing
/// live AX notifications, which are unreliable in Chromium/Electron apps.
@MainActor
final class EditLearningService: EditLearningServiceProtocol {
    static let checkpointDelays: [TimeInterval] = [10, 30, 60]

    var onLearnedTerms: (([String]) -> Void)?
    var onEditRate: ((Int) -> Void)?

    private let isKnownWord: (String) -> Bool
    private let scheduleTimer: (TimeInterval, @escaping @MainActor () -> Void) -> () -> Void
    private let workspaceNotificationCenter: NotificationCenter

    private struct ActiveSession {
        let session: EditLearningSession
        var baseline: String?
        var learnedTerms: [String] = []
        var cancelTimers: [() -> Void] = []
        var appActivationObserver: NSObjectProtocol?
    }

    private var activeSession: ActiveSession?

    nonisolated init(
        isKnownWord: @escaping (String) -> Bool = EditLearningService.spellCheckerKnowsWord,
        scheduleTimer: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> () -> Void = EditLearningService.scheduleMainRunLoopTimer,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.isKnownWord = isKnownWord
        self.scheduleTimer = scheduleTimer
        self.workspaceNotificationCenter = workspaceNotificationCenter
    }

    func beginTracking(_ session: EditLearningSession) {
        finalizeActiveSession()

        let baseline = session.fieldValueAfterInsertion.flatMap { value in
            value.contains(session.insertedText) ? value : nil
        }
        var active = ActiveSession(session: session, baseline: baseline)
        active.appActivationObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // queue: .main delivers on the main queue — the MainActor's executor —
            // regardless of the posting thread, so this cannot trap.
            MainActor.assumeIsolated {
                self?.finalizeActiveSession()
            }
        }
        for (index, delay) in Self.checkpointDelays.enumerated() {
            let isTerminal = index == Self.checkpointDelays.count - 1
            active.cancelTimers.append(scheduleTimer(delay) { [weak self] in
                self?.processRead(terminal: isTerminal)
            })
        }
        activeSession = active
    }

    func finalizeActiveSession() {
        processRead(terminal: true)
    }

    private func processRead(terminal: Bool) {
        guard var active = activeSession else {
            return
        }

        var learnedNow: [String] = []
        var editRateBucket: Int?
        if let currentValue = active.session.readCurrentFieldValue() {
            if let baseline = active.baseline {
                learnedNow = newlyLearnedTerms(in: active, baseline: baseline, currentValue: currentValue)
                active.learnedTerms.append(contentsOf: learnedNow)
                if terminal {
                    editRateBucket = Self.editRateBucket(insertedText: active.session.insertedText, baseline: baseline, current: currentValue)
                }
            } else if currentValue.contains(active.session.insertedText) {
                // Clipboard paste lands asynchronously; adopt the first read
                // that contains the inserted text as the diff baseline.
                active.baseline = currentValue
                if terminal { editRateBucket = 0 } // still verbatim → unedited
            }
        }

        // Commit session state before emitting the callback so a reentrant
        // beginTracking/finalizeActiveSession sees consistent state.
        if terminal {
            tearDown(active)
            activeSession = nil
        } else {
            activeSession = active
        }

        if !learnedNow.isEmpty {
            onLearnedTerms?(learnedNow)
        }
        if let editRateBucket {
            onEditRate?(editRateBucket)
        }
    }

    /// Coarse % of the inserted words that were substituted, rounded to a
    /// 10-point bucket (0...100). Derived from word counts only — no text leaves.
    nonisolated static func editRateBucket(insertedText: String, baseline: String, current: String) -> Int {
        let insertedWords = insertedText.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        guard insertedWords > 0 else { return 0 }
        let subs = TranscriptionEditDiff.substitutions(insertedText: insertedText, baseline: baseline, current: current)
        let pct = min(100, subs.count * 100 / insertedWords)
        return Int((Double(pct) / 10).rounded()) * 10
    }

    private func newlyLearnedTerms(
        in active: ActiveSession,
        baseline: String,
        currentValue: String
    ) -> [String] {
        let remainingCapacity = CorrectionClassifier.maximumTermsPerSession - active.learnedTerms.count
        guard remainingCapacity > 0 else {
            return []
        }
        let substitutions = TranscriptionEditDiff.substitutions(
            insertedText: active.session.insertedText,
            baseline: baseline,
            current: currentValue
        )
        return CorrectionClassifier.learnableTerms(
            from: substitutions,
            existingVocabulary: active.session.existingVocabulary + active.learnedTerms,
            isKnownWord: isKnownWord,
            maxTerms: remainingCapacity
        )
    }

    private func tearDown(_ active: ActiveSession) {
        for cancel in active.cancelTimers {
            cancel()
        }
        if let observer = active.appActivationObserver {
            workspaceNotificationCenter.removeObserver(observer)
        }
    }

    /// NSSpellChecker is main-thread-only. This is nonisolated solely so it can
    /// serve as a default argument; all callers run on the main actor.
    nonisolated static func spellCheckerKnowsWord(_ word: String) -> Bool {
        let checker = NSSpellChecker.shared
        let missRange = checker.checkSpelling(of: word, startingAt: 0)
        return missRange.location == NSNotFound
    }

    nonisolated static func scheduleMainRunLoopTimer(
        after delay: TimeInterval,
        _ handler: @escaping @MainActor () -> Void
    ) -> () -> Void {
        let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            MainActor.assumeIsolated {
                handler()
            }
        }
        return { timer.invalidate() }
    }
}
