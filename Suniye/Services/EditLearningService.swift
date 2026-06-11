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
            MainActor.assumeIsolated {
                self?.finalizeActiveSession()
            }
        }
        activeSession = active

        let lastDelay = Self.checkpointDelays.last
        for delay in Self.checkpointDelays {
            let isTerminal = delay == lastDelay
            let cancel = scheduleTimer(delay) { [weak self] in
                self?.processRead(terminal: isTerminal)
            }
            activeSession?.cancelTimers.append(cancel)
        }
    }

    func finalizeActiveSession() {
        processRead(terminal: true)
    }

    private func processRead(terminal: Bool) {
        guard var active = activeSession else {
            return
        }
        defer {
            if terminal {
                tearDown(active)
                activeSession = nil
            } else {
                activeSession = active
            }
        }

        guard let currentValue = active.session.readCurrentFieldValue() else {
            return
        }

        guard let baseline = active.baseline else {
            // Clipboard paste lands asynchronously; adopt the first read that
            // contains the inserted text as the diff baseline.
            if currentValue.contains(active.session.insertedText) {
                active.baseline = currentValue
            }
            return
        }

        let substitutions = TranscriptionEditDiff.substitutions(
            insertedText: active.session.insertedText,
            baseline: baseline,
            current: currentValue
        )
        let remainingCapacity = CorrectionClassifier.maximumTermsPerSession - active.learnedTerms.count
        guard remainingCapacity > 0 else {
            return
        }
        let terms = CorrectionClassifier.learnableTerms(
            from: substitutions,
            existingVocabulary: active.session.existingVocabulary + active.learnedTerms,
            isKnownWord: isKnownWord,
            maxTerms: remainingCapacity
        )
        guard !terms.isEmpty else {
            return
        }
        active.learnedTerms.append(contentsOf: terms)
        onLearnedTerms?(terms)
    }

    private func tearDown(_ active: ActiveSession) {
        for cancel in active.cancelTimers {
            cancel()
        }
        if let observer = active.appActivationObserver {
            workspaceNotificationCenter.removeObserver(observer)
        }
    }

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
