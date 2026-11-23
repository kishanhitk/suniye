import Foundation
import SuniyeAnalytics

/// Writes the summaries of finished meetings, one at a time. An on-device
/// summary runs only while no dictation runs: a dictation stops it, and it
/// goes on where it stopped once the dictation ends. A hosted summary uses
/// nothing that a dictation needs, so it goes on.
@MainActor
final class MeetingSummaries {
    private var running: (id: UUID, engine: MeetingSummaryEngine)?

    private let store: MeetingStore
    private let templates: MeetingTemplateStore
    private let availability: (MeetingSummaryModelChoice) -> MeetingSummaryAvailability
    private let makeModel: (MeetingSummaryEngine) -> MeetingSummaryModel?
    private let analytics: Analytics
    /// The summary model for one meeting. Until the owner sets it, every
    /// meeting stays on the Mac.
    var choice: (UUID) -> MeetingSummaryModelChoice = { _ in .automatic }
    /// Gets the record once its summary state is final.
    var onFinished: ((MeetingRecord) -> Void)?
    /// Runs after each summary, so that Magic Format can load its own prompt
    /// into the model's cache again.
    var onModelIdle: (() -> Void)?
    private var queue: [UUID] = []
    private var writers: [UUID: (engine: MeetingSummaryEngine, writer: MeetingSummaryWriter)] = [:]
    private var task: Task<Void, Never>?
    private var held = false

    init(
        store: MeetingStore,
        templates: MeetingTemplateStore,
        availability: @escaping (MeetingSummaryModelChoice) -> MeetingSummaryAvailability,
        makeModel: @escaping (MeetingSummaryEngine) -> MeetingSummaryModel?,
        analytics: Analytics
    ) {
        self.store = store
        self.templates = templates
        self.availability = availability
        self.makeModel = makeModel
        self.analytics = analytics
    }

    func enqueue(_ id: UUID) {
        if !queue.contains(id) {
            queue.append(id)
        }
        runNext()
    }

    /// For a deleted meeting.
    func remove(_ id: UUID) {
        queue.removeAll { $0 == id }
        writers[id] = nil
        if running?.id == id {
            task?.cancel()
        }
    }

    func hold(_ held: Bool) {
        self.held = held
        if held {
            if running?.engine.isOnDevice == true {
                task?.cancel()
            }
        } else {
            runNext()
        }
    }

    /// Stops the summary in progress when `engine` writes it. The meeting
    /// stays in the queue and runs again with the model of its choice.
    func cancelRunning(engine: MeetingSummaryEngine) {
        if running?.engine == engine {
            task?.cancel()
        }
    }

    /// Call when a model becomes ready or goes away, or when the choice of a
    /// meeting changes.
    func availabilityChanged() {
        runNext()
    }

    /// Starts the first meeting whose model can run now. A meeting that
    /// waits for the local model or for the end of a dictation does not
    /// block a hosted one behind it.
    private func runNext() {
        guard task == nil else { return }
        for id in queue {
            guard case let .ready(engine) = availability(choice(id)),
                  !(held && engine.isOnDevice),
                  let writer = writer(for: id, engine: engine) else { continue }
            running = (id, engine)
            task = Task { [weak self] in
                await self?.summarize(id, with: writer, engine: engine)
            }
            return
        }
    }

    private func summarize(_ id: UUID, with writer: MeetingSummaryWriter, engine: MeetingSummaryEngine) async {
        defer {
            running = nil
            task = nil
            onModelIdle?()
            runNext()
        }
        guard let record = await store.record(id) else {
            queue.removeAll { $0 == id }
            return
        }
        let started = ContinuousClock.now
        let segments = await store.segments(of: id)
        let input = MeetingSummaryInput(
            segments: segments,
            notes: await store.notes(of: id) ?? "",
            template: await templates.template(id: record.templateID),
            speakerLabels: record.hasCallTrack
        )
        let change: (inout MeetingRecord) -> Void
        let outcome: MeetingOutcome
        var failure: MeetingSummaryFailure?
        var parts: Int?
        do {
            let summary = try await writer.write(input)
            try await store.saveSummary(summary.body, for: id)
            change = {
                $0.adoptGeneratedTitle(summary.title)
                $0.status = .done
                $0.summaryFailure = nil
                $0.summaryEditedAt = nil
            }
            outcome = .done
            parts = summary.parts
        } catch is CancellationError {
            return
        } catch MeetingSummaryError.tooLittleSpeech {
            change = { $0.status = .noSpeech }
            outcome = .noSpeech
        } catch {
            // Only the kind: app.log goes into diagnostic reports.
            let kind: MeetingSummaryFailure
            if case let MeetingSummaryError.failed(failed) = error {
                kind = failed
            } else {
                kind = .modelError
            }
            AppLogger.shared.log(.error, "meeting summary failed id=\(id.uuidString) engine=\(engine.rawValue) failure=\(kind.rawValue)")
            change = {
                $0.status = .summaryFailed
                $0.summaryFailure = kind
            }
            outcome = .failed
            failure = kind
        }
        // Only a stopped run keeps its answers: the next run of a finished
        // one must ask the model again.
        writers[id] = nil
        analytics.track(.meetingSummarized(
            provider: engine,
            outcome: outcome,
            reason: failure,
            parts: parts,
            durationMs: Int((ContinuousClock.now - started) / .milliseconds(1))
        ))
        queue.removeAll { $0 == id }
        do {
            onFinished?(try await store.update(id) {
                change(&$0)
                $0.summaryEngine = engine
                $0.summaryOnThisMac = false
            })
        } catch {
            AppLogger.shared.log(.error, "meeting summary state not saved id=\(id.uuidString) error=\(error.localizedDescription)")
        }
    }

    /// One writer per meeting and model until its summary ends, so a stopped
    /// summary reuses the answers that it already has.
    private func writer(for id: UUID, engine: MeetingSummaryEngine) -> MeetingSummaryWriter? {
        if let existing = writers[id], existing.engine == engine {
            return existing.writer
        }
        guard let model = makeModel(engine) else { return nil }
        let writer = MeetingSummaryWriter(model: model)
        writers[id] = (engine, writer)
        return writer
    }
}
