import XCTest
@testable import Suniye

private let rate = MeetingAudioFormat.sampleRate

/// Segments of `words` words each, alternating "You" and "Them" 5 s apart.
private func conversation(turns: Int, words: Int, track: (Int) -> MeetingTrack = { $0.isMultiple(of: 2) ? .you : .them }) -> [MeetingSegment] {
    (0 ..< turns).map { index in
        let text = (0 ..< words).map { "word\($0)" }.joined(separator: " ") + "."
        return MeetingSegment(id: UUID(), track: track(index), audioStart: index * 5 * rate, audioEnd: (index * 5 + 4) * rate, text: text)
    }
}

private func input(_ segments: [MeetingSegment], notes: String = "", labels: Bool = true) -> MeetingSummaryInput {
    MeetingSummaryInput(segments: segments, notes: notes, template: .general, speakerLabels: labels)
}

final class MeetingSummaryWriterTests: XCTestCase {
    func testAppleIntelligenceComesFirstThenTheInstalledLocalModel() {
        XCTAssertEqual(MeetingSummaryAvailability(apple: .available, localModel: .available), .ready(.appleIntelligence))
        XCTAssertEqual(MeetingSummaryAvailability(apple: .appleIntelligenceNotEnabled, localModel: .available), .ready(.localModel))
        XCTAssertEqual(MeetingSummaryAvailability(apple: .deviceNotEligible, localModel: .modelNotInstalled), .needsDownload)
        XCTAssertEqual(MeetingSummaryAvailability(apple: .deviceNotEligible, localModel: .unsupportedHardware), .unavailable)
    }

    func testAShortMeetingIsOneRequestAndTheAnswerIsCleaned() async throws {
        let model = FakeSummaryModel(context: 4_096) { _ in
            """
            # Weekly sync.
            ## Overview
            We agreed to **ship** on Friday.

            ## Decisions
            * Ship on Friday.
            - None

            ## Action items
            - None noted.

            ## Open questions
            - No open questions.
            """
        }
        let writer = MeetingSummaryWriter(model: model)

        let summary = try await writer.write(input(conversation(turns: 4, words: 10), notes: "Ship Friday"))
        let requests = await model.requests

        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(requests[0].input.contains("You: word0"))
        XCTAssertTrue(requests[0].input.contains("<notes>\nShip Friday\n</notes>"))
        XCTAssertTrue(requests[0].input.contains(MeetingTemplate.general.sections))
        XCTAssertEqual(summary.title, "Weekly sync")
        XCTAssertEqual(summary.body, "## Overview\nWe agreed to ship on Friday.\n\n## Decisions\n- Ship on Friday.")
    }

    func testALongMeetingIsSummarizedFromNotesOnItsParts() async throws {
        let model = FakeSummaryModel(context: 2_000)
        let writer = MeetingSummaryWriter(model: model)

        _ = try await writer.write(input(conversation(turns: 60, words: 50)))
        let requests = await model.requests
        let parts = requests.filter(\.isPart)

        XCTAssertGreaterThanOrEqual(parts.count, 2)
        let room = Int(Double(2_000 - MeetingSummaryWriter.partOutputTokens) * MeetingSummaryWriter.fillFactor)
        for part in parts {
            let tokens = await model.tokenCount(part.text) ?? 0
            XCTAssertLessThanOrEqual(tokens, room)
        }
        let last = try XCTUnwrap(requests.last)
        XCTAssertEqual(last.kind, .summary)
        XCTAssertTrue(last.input.contains("Part 1:\n- notes on part 1 of \(parts.count)"))
        XCTAssertTrue(last.input.contains("Part \(parts.count):"))
    }

    func testNotesOnPartsThatDoNotFitAreJoinedFirst() async throws {
        let longNotes = (0 ..< 120).map { "- fact\($0)" }.joined(separator: "\n")
        let model = FakeSummaryModel(context: 1_600) { request in
            switch request.kind {
            case .part:
                return longNotes
            case .join:
                return "- joined"
            case .summary:
                return "Release review\n## Overview\nShort."
            }
        }
        let writer = MeetingSummaryWriter(model: model)

        let summary = try await writer.write(input(conversation(turns: 60, words: 50)))
        let kinds = await model.requests.map(\.kind)

        XCTAssertTrue(kinds.contains(.join))
        XCTAssertEqual(kinds.last, .summary)
        XCTAssertLessThan(kinds.firstIndex(of: .join) ?? .max, kinds.count - 1)
        XCTAssertEqual(summary.title, "Release review")
    }

    func testAModelThatCannotCountIsPlannedAtTwoCharactersPerToken() async throws {
        let counting = FakeSummaryModel(context: 4_096)
        let estimating = FakeSummaryModel(context: 4_096, counts: false)
        let meeting = input(conversation(turns: 40, words: 30))

        _ = try await MeetingSummaryWriter(model: counting).write(meeting)
        _ = try await MeetingSummaryWriter(model: estimating).write(meeting)

        let counted = await counting.requests.count
        let estimated = await estimating.requests.count
        XCTAssertEqual(counted, 1, "counted by words, the meeting fits in one request")
        XCTAssertGreaterThan(estimated, 1, "at 2 characters per token, the same meeting does not fit")
    }

    func testACutShortAnswerFailsWithItsCause() async {
        let model = FakeSummaryModel(context: 4_096) { _ in throw LLMPostProcessorError.outputTruncated }
        let writer = MeetingSummaryWriter(model: model)

        do {
            _ = try await writer.write(input(conversation(turns: 4, words: 10)))
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? MeetingSummaryError, .failed("The model stopped before it finished."))
        }
        let emptyWriter = MeetingSummaryWriter(model: FakeSummaryModel(context: 4_096) { _ in "Title: Sync\n## Decisions\n- None" })
        do {
            _ = try await emptyWriter.write(input(conversation(turns: 4, words: 10)))
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? MeetingSummaryError, .failed("The model wrote nothing."), "a summary with nothing in it is no summary")
        }
    }

    func testTooLittleSpeechAndNoNotesIsNeverSent() async throws {
        let model = FakeSummaryModel(context: 4_096)
        let writer = MeetingSummaryWriter(model: model)
        let fewWords = conversation(turns: 2, words: 5)

        do {
            _ = try await writer.write(input(fewWords))
            XCTFail("expected too little speech")
        } catch {
            XCTAssertEqual(error as? MeetingSummaryError, .tooLittleSpeech)
        }
        let requestsWithoutNotes = await model.requests.count
        _ = try await writer.write(input(fewWords, notes: "Budget approved."))

        XCTAssertEqual(requestsWithoutNotes, 0)
        let requestsWithNotes = await model.requests.count
        XCTAssertEqual(requestsWithNotes, 1, "the user's notes are worth a summary")
    }

    func testAStoppedSummaryGoesOnFromThePartsThatFinished() async throws {
        let model = FakeSummaryModel(context: 2_000)
        await model.waitForCancellation(onRequest: 3)
        let writer = MeetingSummaryWriter(model: model)
        let meeting = input(conversation(turns: 60, words: 50))

        let first = Task { try await writer.write(meeting) }
        let reachedThirdRequest = await model.waitUntil(requests: 3)
        first.cancel()
        let firstResult = await first.result
        await model.waitForCancellation(onRequest: nil)
        let before = await model.requests.count
        _ = try await writer.write(meeting)
        let resumed = await model.requests.dropFirst(before)

        XCTAssertTrue(reachedThirdRequest)
        XCTAssertThrowsError(try firstResult.get()) { XCTAssertTrue($0 is CancellationError, "\($0)") }
        XCTAssertFalse(resumed.contains { $0.partNumber == 1 || $0.partNumber == 2 })
        XCTAssertTrue(resumed.contains { $0.partNumber == 3 })
    }

    func testTheTitleIsCleanedAndASentenceIsNotATitle() {
        XCTAssertEqual(MeetingSummaryText.parse("Title: \"Q3 planning.\"\n## Overview\nPlans.").title, "Q3 planning")
        XCTAssertNil(MeetingSummaryText.parse("## Overview\nPlans.").title)

        let sentence = "The team went over the launch plan, the open bugs and the date for the next review in depth."
        let parsed = MeetingSummaryText.parse("\(sentence)\n## Decisions\n- Launch Monday.")
        XCTAssertNil(parsed.title)
        XCTAssertEqual(parsed.body, "\(sentence)\n\n## Decisions\n- Launch Monday.")
    }

    func testAGeneratedTitleReplacesOnlyThePlaceholder() {
        var placeholder = MeetingRecord(title: "Zoom call", startedAt: Date(), tracks: [.you, .them], templateID: "general")
        var named = placeholder
        named.title = "Hiring sync"
        named.titleSource = .user

        placeholder.adoptGeneratedTitle("Release review")
        named.adoptGeneratedTitle("Release review")

        XCTAssertEqual(placeholder.title, "Release review")
        XCTAssertEqual(placeholder.titleSource, .generated)
        XCTAssertEqual(named.title, "Hiring sync")
    }
}

final class LocalGemmaMeetingSummaryModelTests: XCTestCase {
    func testAnAnswerIsCleanedAndACutShortOneIsRefused() async throws {
        let client = FakeGemmaClient(result: ChatCompletionResult(text: "Weekly sync\n## Overview\nShip.<end_of_turn>", timings: nil, finishReason: "stop"))
        let model = LocalGemmaMeetingSummaryModel(client: client)
        let request = MeetingSummaryRequest(kind: .summary, instructions: "Rules.", input: "<transcript>\nYou: Ship.\n</transcript>")

        let answer = try await model.generate(request)
        client.result = ChatCompletionResult(text: "Weekly sync\n## Over", timings: nil, finishReason: ChatCompletionResult.lengthStop)

        XCTAssertEqual(answer, "Weekly sync\n## Overview\nShip.")
        XCTAssertEqual(client.lastCall?.maxTokens, MeetingSummaryWriter.summaryOutputTokens)
        XCTAssertEqual(client.lastCall?.sampling, .greedyWithoutRepeats, "greedy decoding alone can repeat a line until the limit")
        XCTAssertEqual(client.lastCall?.instructions, "Rules.")
        do {
            _ = try await model.generate(request)
            XCTFail("expected a refused answer")
        } catch LLMPostProcessorError.outputTruncated {
        } catch {
            XCTFail("unexpected \(error)")
        }
    }
}

final class MeetingTemplateStoreTests: XCTestCase {
    private var fileURL: URL!

    override func setUp() {
        super.setUp()
        fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("meeting-templates-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fileURL)
        super.tearDown()
    }

    func testEditsAndAdditionsPersistAndABuiltInTemplateRestores() async throws {
        let store = MeetingTemplateStore(fileURL: fileURL)
        var edited = await store.templates()
        edited[0].sections = "## Overview\nOne sentence."
        edited.append(MeetingTemplate(id: "retro", name: "Retro", sections: "## Went well\nOne line each."))

        try await store.replace(with: edited)
        let reloaded = await MeetingTemplateStore(fileURL: fileURL).templates()
        edited[0] = .general
        try await store.replace(with: edited)
        let restored = await store.template(id: "general")

        XCTAssertEqual(reloaded.map(\.id), ["general", "one-on-one", "stand-up", "interview", "retro"])
        XCTAssertEqual(reloaded.first?.sections, "## Overview\nOne sentence.")
        XCTAssertEqual(restored, .general)
    }

    func testATemplateLeftOutOfTheListGoesUnlessItIsBuiltIn() async throws {
        let store = MeetingTemplateStore(fileURL: fileURL)
        try await store.replace(with: MeetingTemplate.builtIn + [MeetingTemplate(id: "retro", name: "Retro", sections: "## Went well")])

        try await store.replace(with: [.general])
        let after = await store.templates()
        let retro = await store.template(id: "retro")

        XCTAssertEqual(after, MeetingTemplate.builtIn)
        XCTAssertEqual(retro, .general, "a deleted template falls back to General")
    }
}

// MARK: - Fakes

/// Counts one token per word. Answers notes for parts and joins, and a
/// summary otherwise, unless `answer` says something else.
private actor FakeSummaryModel: MeetingSummaryModel {
    private let context: Int
    private let counts: Bool
    private let answer: ((MeetingSummaryRequest) throws -> String)?
    private(set) var requests: [MeetingSummaryRequest] = []
    private var cancellationRequest: Int?

    init(context: Int, counts: Bool = true, answer: ((MeetingSummaryRequest) throws -> String)? = nil) {
        self.context = context
        self.counts = counts
        self.answer = answer
    }

    /// Request `number` then waits until its task is canceled.
    func waitForCancellation(onRequest number: Int?) {
        cancellationRequest = number
    }

    func waitUntil(requests count: Int) async -> Bool {
        for _ in 0 ..< 400 where requests.count < count {
            try? await Task.sleep(for: .milliseconds(5))
        }
        return requests.count >= count
    }

    func contextTokens() async -> Int {
        context
    }

    func tokenCount(_ text: String) async -> Int? {
        counts ? text.split(whereSeparator: \.isWhitespace).count : nil
    }

    func generate(_ request: MeetingSummaryRequest) async throws -> String {
        requests.append(request)
        if requests.count == cancellationRequest {
            while true {
                try await Task.sleep(for: .milliseconds(5))
            }
        }
        if let answer {
            return try answer(request)
        }
        switch request.kind {
        case let .part(number, count):
            return "- notes on part \(number) of \(count)"
        case .join:
            return "- joined notes"
        case .summary:
            return "Planning\n## Overview\nPlans."
        }
    }
}

private final class FakeGemmaClient: LocalGemmaClient {
    struct Call {
        let instructions: String
        let prompt: String
        let maxTokens: Int?
        let sampling: LocalGemmaSampling
    }

    var result: ChatCompletionResult
    private(set) var lastCall: Call?

    init(result: ChatCompletionResult) {
        self.result = result
    }

    var availability: LocalGemmaAvailability {
        .available
    }

    func generate(
        instructions: String,
        prompt: String,
        maxTokens: Int?,
        sampling: LocalGemmaSampling,
        startupTimeoutSeconds: Double,
        idleTimeoutSeconds: Double,
        timeoutSeconds: Double
    ) async throws -> ChatCompletionResult {
        lastCall = Call(instructions: instructions, prompt: prompt, maxTokens: maxTokens, sampling: sampling)
        return result
    }
}

private extension MeetingSummaryRequest {
    var partNumber: Int? {
        if case let .part(number, _) = kind {
            return number
        }
        return nil
    }

    var isPart: Bool {
        partNumber != nil
    }
}
