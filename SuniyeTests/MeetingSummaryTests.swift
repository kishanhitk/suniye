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

private func input(_ segments: [MeetingSegment], notes: String = "", labels: Bool = true, template: MeetingTemplate = .general) -> MeetingSummaryInput {
    MeetingSummaryInput(segments: segments, notes: notes, template: template, speakerLabels: labels)
}

/// A template with no "## " section: the model writes the whole summary.
private let freeTemplate = MeetingTemplate(id: "free", name: "Free", sections: "Write a short summary of the meeting.")

final class MeetingSummaryWriterTests: XCTestCase {
    func testAppleIntelligenceComesFirstThenTheInstalledLocalModel() {
        XCTAssertEqual(MeetingSummaryAvailability(apple: .available, localModel: .available), .ready(.appleIntelligence))
        XCTAssertEqual(MeetingSummaryAvailability(apple: .appleIntelligenceNotEnabled, localModel: .available), .ready(.localModel))
        XCTAssertEqual(MeetingSummaryAvailability(apple: .deviceNotEligible, localModel: .modelNotInstalled), .needsDownload)
        XCTAssertEqual(MeetingSummaryAvailability(apple: .deviceNotEligible, localModel: .unsupportedHardware), .unavailable)
    }

    func testAShortMeetingIsOnePartThenTheTitleAndOverview() async throws {
        let model = FakeSummaryModel(context: 4_096) { request in
            switch request.kind {
            case .part:
                return "**Decisions:** Ship on Friday; none\nAction items: Send the test steps; No action items.\nDates and numbers: Review on 3 December\nOpen questions: None noted."
            case .userNotes:
                return "Action items: Ask legal"
            case .overview:
                return "Title: \"Weekly sync.\"\nWe agreed to ship on Friday."
            case .summary, .join:
                return ""
            }
        }
        let writer = MeetingSummaryWriter(model: model)

        let summary = try await writer.write(input(conversation(turns: 4, words: 10), notes: "Ask legal"))
        let requests = await model.requests

        XCTAssertEqual(requests.map(\.kind), [.userNotes, .part(number: 1, count: 1), .overview])
        XCTAssertTrue(requests[0].input.contains("<notes>\nAsk legal\n</notes>"))
        XCTAssertTrue(requests[1].input.contains("You: word0"))
        XCTAssertTrue(requests[1].input.contains("Decisions:\nAction items:\nDates and numbers:\nOpen questions:"))
        XCTAssertEqual(summary.title, "Weekly sync")
        XCTAssertEqual(summary.body, """
        ## Overview
        We agreed to ship on Friday.

        ## Decisions
        - Ship on Friday

        ## Action items
        - Ask legal
        - Send the test steps

        ## Dates and numbers
        - Review on 3 December
        """, "the user's items come first")
    }

    func testALongMeetingJoinsTheItemsOfItsPartsInOrderAndOnce() async throws {
        let model = FakeSummaryModel(context: 2_000) { request in
            switch request.kind {
            case let .part(number, _):
                return "Decisions: Ship on Friday; Decision \(number)"
            case .overview:
                return "Title: Release plan\nThe team planned the release."
            case .userNotes, .summary, .join:
                return ""
            }
        }
        let writer = MeetingSummaryWriter(model: model)

        let summary = try await writer.write(input(conversation(turns: 60, words: 50)))
        let requests = await model.requests
        let parts = requests.filter(\.isPart)

        XCTAssertGreaterThanOrEqual(parts.count, 2)
        let room = Int(Double(2_000 - MeetingSummaryWriter.partOutputTokens) * MeetingSummaryWriter.fillFactor)
        for part in parts {
            let tokens = await model.tokenCount(part.text) ?? 0
            XCTAssertLessThanOrEqual(tokens, room)
        }
        let decisions = ["Ship on Friday"] + (1 ... parts.count).map { "Decision \($0)" }
        XCTAssertEqual(requests.last?.kind, .overview)
        XCTAssertTrue(requests.last?.input.contains("Decisions: " + decisions.joined(separator: "; ")) ?? false)
        XCTAssertEqual(summary.body, "## Overview\nThe team planned the release.\n\n## Decisions\n" + decisions.map { "- \($0)" }.joined(separator: "\n"))
        XCTAssertEqual(summary.parts, parts.count)
    }

    func testATemplateWithNoListSectionIsWrittenWholeAndItsPartNotesAreJoinedFirst() async throws {
        let longNotes = (0 ..< 120).map { "- fact\($0)" }.joined(separator: "\n")
        let model = FakeSummaryModel(context: 1_600) { request in
            switch request.kind {
            case .part:
                return longNotes
            case .join:
                return "- joined"
            case .summary:
                return "Release review\n## Overview\nShort."
            case .userNotes, .overview:
                return ""
            }
        }
        let writer = MeetingSummaryWriter(model: model)

        let summary = try await writer.write(input(conversation(turns: 60, words: 50), template: freeTemplate))
        let kinds = await model.requests.map(\.kind)

        XCTAssertTrue(kinds.contains(.join))
        XCTAssertEqual(kinds.last, .summary)
        XCTAssertLessThan(kinds.firstIndex(of: .join) ?? .max, kinds.count - 1)
        XCTAssertEqual(summary.title, "Release review")
    }

    func testATemplateThatLeavesTooLittleRoomForAPartIsWrittenWhole() async throws {
        let rules = (0 ..< 3_000).map { "rule\($0)" }.joined(separator: " ")
        let longTemplate = MeetingTemplate(id: "long", name: "Long", sections: "## Overview\n## Decisions\n\(rules)")
        let model = FakeSummaryModel(context: 8_192)

        _ = try await MeetingSummaryWriter(model: model).write(input(conversation(turns: 4, words: 10), template: longTemplate))
        let kinds = await model.requests.map(\.kind)

        XCTAssertEqual(kinds, [.summary])
    }

    func testAModelThatCannotCountIsPlannedAtTwoCharactersPerToken() async throws {
        let counting = FakeSummaryModel(context: 4_096)
        let estimating = FakeSummaryModel(context: 4_096, counts: false)
        let meeting = input(conversation(turns: 40, words: 30))

        _ = try await MeetingSummaryWriter(model: counting).write(meeting)
        _ = try await MeetingSummaryWriter(model: estimating).write(meeting)

        let counted = await counting.requests.filter(\.isPart).count
        let estimated = await estimating.requests.filter(\.isPart).count
        XCTAssertEqual(counted, 1, "counted by words, the meeting fits in one part")
        XCTAssertGreaterThan(estimated, 1, "at 2 characters per token, the same meeting does not fit")
    }

    func testItemsAreReadUnderTheirLabelsAndJoinedOnce() {
        let sections = ["Decisions", "Action items", "Open questions"]
        let answer = "Decisions:\n- Ship on Friday\n- None\nAction items: Priya writes the notes; no action items were discussed\nOther notes:\n- not a section\n## Open questions\n1. Budget?\n2) Venue?"

        let parsed = MeetingSummaryItems.parse(answer, sections: sections)
        let joined = MeetingSummaryItems.join(
            [["Decisions": ["Do not ship on Friday", "Alice interviews Bob"]], ["Decisions": ["do not ship on friday.", "Ship on Friday", "Bob interviews Alice"]]],
            sections: ["Decisions"]
        )

        XCTAssertEqual(parsed, ["Decisions": ["Ship on Friday"], "Action items": ["Priya writes the notes"], "Open questions": ["Budget?", "Venue?"]])
        XCTAssertEqual(joined["Decisions"], ["Do not ship on Friday", "Alice interviews Bob", "Ship on Friday", "Bob interviews Alice"], "only the same words in the same order are a repeat")
    }

    func testTheTemplateHeadingsAreTheSections() throws {
        let general = try XCTUnwrap(MeetingSummaryLayout(template: .general))

        XCTAssertEqual(general.sections, ["Overview", "Decisions", "Action items", "Dates and numbers", "Open questions"])
        XCTAssertEqual(general.paragraph, "Overview")
        XCTAssertEqual(general.lists, ["Decisions", "Action items", "Dates and numbers", "Open questions"])
        XCTAssertNil(MeetingSummaryLayout(template: freeTemplate))
        XCTAssertNil(MeetingSummaryLayout(template: MeetingTemplate(id: "o", name: "O", sections: "## Overview\nTwo sentences.")), "a paragraph alone has no list to join")
        XCTAssertNil(MeetingSummaryLayout(template: MeetingTemplate(id: "d", name: "D", sections: "## Tasks\n## Notes\n## tasks")), "code reads the items by section name")
    }

    func testLongNotesAreReadInPiecesBeforeTheTranscript() async throws {
        let notes = (0 ..< 60).map { "note\($0) " + String(repeating: "word ", count: 20) }.joined(separator: "\n")
        let model = FakeSummaryModel(context: 2_000) { request in
            switch request.kind {
            case .userNotes:
                let first = request.input.components(separatedBy: "\n").first { $0.hasPrefix("note") } ?? ""
                return "Decisions: " + (first.components(separatedBy: " ").first ?? "")
            case .part:
                return "Decisions: Ship on Friday"
            case .overview:
                return "Title: Notes\nThe team took notes."
            case .summary, .join:
                return ""
            }
        }

        let summary = try await MeetingSummaryWriter(model: model).write(input(conversation(turns: 4, words: 10), notes: notes))
        let requests = await model.requests
        let pieces = requests.filter { $0.kind == .userNotes }

        XCTAssertGreaterThan(pieces.count, 1)
        let room = Int(Double(2_000 - MeetingSummaryWriter.partOutputTokens) * MeetingSummaryWriter.fillFactor)
        for piece in pieces {
            let tokens = await model.tokenCount(piece.text) ?? 0
            XCTAssertLessThanOrEqual(tokens, room)
        }
        XCTAssertEqual(requests.prefix(pieces.count).map(\.kind), Array(repeating: .userNotes, count: pieces.count))
        XCTAssertTrue(summary.body.hasPrefix("## Overview\nThe team took notes.\n\n## Decisions\n- note0\n"))
        XCTAssertTrue(summary.body.hasSuffix("- Ship on Friday"))
    }

    func testAnOverviewThatCannotFitLeavesTheListsWithNoTitle() async throws {
        let long = (0 ..< 2_000).map { "word\($0)" }.joined(separator: " ")
        let model = FakeSummaryModel(context: 2_400) { request in
            switch request.kind {
            case .part:
                return "Decisions: \(long)"
            case .overview:
                return "Title: Never asked"
            case .userNotes, .summary, .join:
                return ""
            }
        }

        let summary = try await MeetingSummaryWriter(model: model).write(input(conversation(turns: 4, words: 10)))
        let kinds = await model.requests.map(\.kind)

        XCTAssertFalse(kinds.contains(.overview))
        XCTAssertNil(summary.title)
        XCTAssertEqual(summary.body, "## Decisions\n- \(long)")
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
        XCTAssertGreaterThan(requestsWithNotes, 0, "the user's notes are worth a summary")
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

    func testAFileThatCannotBeReadIsNotWrittenOver() async throws {
        try Data("{ not json".utf8).write(to: fileURL)
        let store = MeetingTemplateStore(fileURL: fileURL)

        let shown = await store.templates()
        do {
            try await store.replace(with: shown)
            XCTFail("saving over an unreadable file loses the templates in it")
        } catch {
            XCTAssertEqual(error as? MeetingTemplateStore.StoreError, .unreadable)
        }

        XCTAssertEqual(shown, MeetingTemplate.builtIn)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "{ not json")
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
            return "Decisions: decision on part \(number) of \(count)"
        case .userNotes:
            return "Action items: from the notes"
        case .overview:
            return "Title: Planning\nPlans."
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
