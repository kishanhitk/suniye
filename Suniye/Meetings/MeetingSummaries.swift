import Foundation
import SuniyeAnalytics

/// Writes the summaries of finished meetings, one at a time and only while no
/// dictation runs: a dictation stops the summary in progress, and it goes on
/// where it stopped once the dictation ends.
@MainActor
@Observable
final class MeetingSummaries {
    @ObservationIgnored private var writing: UUID?

    @ObservationIgnored private let store: MeetingStore
    @ObservationIgnored private let templates: MeetingTemplateStore
    @ObservationIgnored private let availability: () -> MeetingSummaryAvailability
    @ObservationIgnored private let makeModel: (MeetingSummaryProvider) -> MeetingSummaryModel?
    @ObservationIgnored private let analytics: Analytics
    /// Gets the record once its summary state is final.
    @ObservationIgnored var onFinished: ((MeetingRecord) -> Void)?
    /// Runs after each run of the model, so that Magic Format can load its
    /// own prompt into the model's cache again.
    @ObservationIgnored var onModelIdle: (() -> Void)?
    @ObservationIgnored private var queue: [UUID] = []
    @ObservationIgnored private var writers: [UUID: (provider: MeetingSummaryProvider, writer: MeetingSummaryWriter)] = [:]
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var held = false

    init(
        store: MeetingStore,
        templates: MeetingTemplateStore,
        availability: @escaping () -> MeetingSummaryAvailability,
        makeModel: @escaping (MeetingSummaryProvider) -> MeetingSummaryModel?,
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
              case let .ready(provider) = availability(),
              let writer = writer(for: id, provider: provider) else { return }
        task = Task { [weak self] in
            await self?.summarize(id, with: writer, provider: provider)
        }
    }

    private func summarize(_ id: UUID, with writer: MeetingSummaryWriter, provider: MeetingSummaryProvider) async {
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
            notes: await store.notes(of: id),
            template: await templates.template(id: record.templateID),
            speakerLabels: segments.contains { $0.track == .them }
        )
        let change: (inout MeetingRecord) -> Void
        let outcome: MeetingSummaryOutcome
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
            AppLogger.shared.log(.error, "meeting summary failed id=\(id.uuidString) provider=\(provider.rawValue) error=\(error.localizedDescription)")
            let cause = error.localizedDescription
            change = {
                $0.status = .summaryFailed
                $0.summaryFailure = cause
            }
            outcome = .failed
        }
        analytics.track(.meetingSummarized(
            provider: provider.analyticsEngine,
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
    private func writer(for id: UUID, provider: MeetingSummaryProvider) -> MeetingSummaryWriter? {
        if let existing = writers[id], existing.provider == provider {
            return existing.writer
        }
        guard let model = makeModel(provider) else { return nil }
        let writer = MeetingSummaryWriter(model: model)
        writers[id] = (provider, writer)
        return writer
    }
}
