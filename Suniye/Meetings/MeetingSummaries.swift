import Foundation
import SuniyeAnalytics

/// Writes the summaries of finished meetings, one at a time and only while no
/// dictation runs: a dictation stops the summary in progress, and it goes on
/// where it stopped once the dictation ends.
@MainActor
final class MeetingSummaries {
    private var writing: UUID?

    private let store: MeetingStore
    private let templates: MeetingTemplateStore
    private let availability: () -> MeetingSummaryAvailability
    private let makeModel: (MeetingSummaryEngine) -> MeetingSummaryModel?
    private let analytics: Analytics
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
        availability: @escaping () -> MeetingSummaryAvailability,
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
        if writing == id {
            task?.cancel()
        }
    }

    func hold(_ held: Bool) {
        self.held = held
        if held {
            task?.cancel()
        } else {
            runNext()
        }
    }

    /// Call when a model becomes ready or goes away, for example when the
    /// local model's download ends.
    func availabilityChanged() {
        runNext()
    }

    private func runNext() {
        guard task == nil, !held, let id = queue.first,
              case let .ready(engine) = availability(),
              let writer = writer(for: id, engine: engine) else { return }
        task = Task { [weak self] in
            await self?.summarize(id, with: writer, engine: engine)
        }
    }

    private func summarize(_ id: UUID, with writer: MeetingSummaryWriter, engine: MeetingSummaryEngine) async {
        writing = id
        defer {
            writing = nil
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
        var parts: Int?
        do {
            let summary = try await writer.write(input)
            try await store.saveSummary(summary.body, for: id)
            change = {
                $0.adoptGeneratedTitle(summary.title)
                $0.status = .done
                $0.summaryFailure = nil
            }
            outcome = .done
            parts = summary.parts
        } catch is CancellationError {
            return
        } catch MeetingSummaryError.tooLittleSpeech {
            change = { $0.status = .noSpeech }
            outcome = .noSpeech
        } catch {
            AppLogger.shared.log(.error, "meeting summary failed id=\(id.uuidString) engine=\(engine.rawValue) error=\(error.localizedDescription)")
            let cause = error.localizedDescription
            change = {
                $0.status = .summaryFailed
                $0.summaryFailure = cause
            }
            outcome = .failed
        }
        analytics.track(.meetingSummarized(
            provider: engine,
            outcome: outcome,
            parts: parts,
            durationMs: Int((ContinuousClock.now - started) / .milliseconds(1))
        ))
        queue.removeAll { $0 == id }
        do {
            onFinished?(try await store.update(id, change))
        } catch {
            AppLogger.shared.log(.error, "meeting summary state not saved id=\(id.uuidString) error=\(error.localizedDescription)")
        }
    }

    /// One writer per meeting and model, so a stopped summary reuses the
    /// answers that it already has.
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
