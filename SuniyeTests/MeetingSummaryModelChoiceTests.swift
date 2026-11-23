import SuniyeAnalytics
import XCTest
@testable import Suniye

/// 30 words: enough speech for a summary.
private let talk = (1 ... 30).map { "word\($0)" }.joined(separator: " ") + "."

@MainActor
private func eventually(_ condition: @MainActor () async -> Bool) async -> Bool {
    for _ in 0 ..< 400 {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return await condition()
}

/// A summary model that counts its requests, can wait at a gate, and can
/// fail or answer with fixed text.
private actor ScriptedSummaryModel: MeetingSummaryModel {
    nonisolated let writesWholeSummary: Bool
    private let context: Int
    private(set) var requests: [MeetingSummaryRequest] = []
    private(set) var waiting = false
    private var isOpen = true
    private var failure: MeetingSummaryFailure?
    private var answer = "Title: Planning\n## Decisions\n- Ship on Friday"

    init(writesWholeSummary: Bool, context: Int = 128_000) {
        self.writesWholeSummary = writesWholeSummary
        self.context = context
    }

    func close() { isOpen = false }
    func open() { isOpen = true }
    func fail(with failure: MeetingSummaryFailure?) { self.failure = failure }
    func answer(with text: String) { answer = text }

    func contextTokens() async -> Int { context }
    func tokenCount(_ text: String) async -> Int? { nil }

    func generate(_ request: MeetingSummaryRequest) async throws -> String {
        requests.append(request)
        waiting = true
        defer { waiting = false }
        while !isOpen {
            try await Task.sleep(for: .milliseconds(5))
        }
        if let failure {
            throw MeetingSummaryError.failed(failure)
        }
        switch request.kind {
        case .part, .userNotes:
            return "Decisions: Ship on Friday"
        case .overview:
            return "Title: Planning\nThe team agreed."
        case .summary, .join:
            return answer
        }
    }
}

@MainActor
final class MeetingSummaryQueueTests: XCTestCase {
    private var root: URL!
    private var store: MeetingStore!
    private var local: ScriptedSummaryModel!
    private var hosted: ScriptedSummaryModel!
    private var analytics: SpyAnalytics!
    private var onDevice = MeetingSummaryAvailability.ready(.localModel)
    private var choices: [UUID: MeetingSummaryModelChoice] = [:]
    private var finished: [UUID: MeetingRecord] = [:]
    private var summaries: MeetingSummaries!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("MeetingSummaryQueueTests-\(UUID().uuidString)", isDirectory: true)
        store = MeetingStore(rootDirectory: root.appendingPathComponent("meetings", isDirectory: true))
        local = ScriptedSummaryModel(writesWholeSummary: false, context: 4_096)
        hosted = ScriptedSummaryModel(writesWholeSummary: true)
        analytics = SpyAnalytics()
        summaries = MeetingSummaries(
            store: store,
            templates: MeetingTemplateStore(fileURL: root.appendingPathComponent("templates.json")),
            availability: { [unowned self] choice in
                switch choice {
                case .automatic: onDevice
                case .chatGPT: .ready(.chatgpt)
                case .apiEndpoint: .ready(.apiEndpoint)
                }
            },
            makeModel: { [unowned self] engine in engine.isOnDevice ? local : hosted },
            analytics: analytics
        )
        summaries.choice = { [unowned self] id in choices[id] ?? .automatic }
        summaries.onFinished = { [unowned self] record in finished[record.id] = record }
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func addMeeting(_ choice: MeetingSummaryModelChoice) async throws -> UUID {
        let record = MeetingRecord(title: "Call", startedAt: Date(timeIntervalSince1970: 1_800_000_000), tracks: [.you], status: .summarizing, templateID: MeetingTemplate.general.id)
        try await store.create(record)
        try await store.replaceSegments([MeetingSegment(id: UUID(), track: .you, audioStart: 0, audioEnd: 16_000, text: talk)], of: record.id)
        choices[record.id] = choice
        return record.id
    }

    func testAHostedSummaryDoesNotWaitBehindAnOnDeviceOneThatCannotRunYet() async throws {
        onDevice = .needsDownload
        let waitsForDownload = try await addMeeting(.automatic)
        let hostedMeeting = try await addMeeting(.apiEndpoint)

        summaries.enqueue(waitsForDownload)
        summaries.enqueue(hostedMeeting)
        let done = await eventually { self.finished[hostedMeeting]?.status == .done }

        XCTAssertTrue(done)
        XCTAssertEqual(finished[hostedMeeting]?.summaryEngine, .apiEndpoint)
        XCTAssertNil(finished[waitsForDownload])
        let localRequests = await local.requests.count
        XCTAssertEqual(localRequests, 0)

        onDevice = .ready(.localModel)
        summaries.availabilityChanged()
        let other = await eventually { self.finished[waitsForDownload]?.status == .done }
        XCTAssertTrue(other, "the meeting that waited runs when its model is ready")
        XCTAssertEqual(finished[waitsForDownload]?.summaryEngine, .localModel)
    }

    func testADictationStopsOnlyAnOnDeviceSummary() async throws {
        await hosted.close()
        let hostedMeeting = try await addMeeting(.apiEndpoint)
        let localMeeting = try await addMeeting(.automatic)
        summaries.enqueue(hostedMeeting)
        _ = await eventually { await self.hosted.waiting }

        summaries.hold(true)
        summaries.enqueue(localMeeting)
        try await Task.sleep(for: .milliseconds(60))
        let stillRuns = await hosted.waiting
        await hosted.open()
        let done = await eventually { self.finished[hostedMeeting]?.status == .done }
        let hostedRequests = await hosted.requests.count
        let localRequests = await local.requests.count

        XCTAssertTrue(stillRuns)
        XCTAssertTrue(done)
        XCTAssertEqual(hostedRequests, 1, "the transcript is sent once")
        XCTAssertEqual(localRequests, 0, "an on-device summary waits for the end of the dictation")

        summaries.hold(false)
        let localDone = await eventually { self.finished[localMeeting]?.status == .done }
        XCTAssertTrue(localDone)
    }

    func testAFailureKeepsItsKindAndItsModelAndTheNextRunAsksTheModelAgain() async throws {
        await hosted.answer(with: "Title: Sync\n## Decisions\n- None")
        let id = try await addMeeting(.apiEndpoint)

        summaries.enqueue(id)
        let failed = await eventually { self.finished[id]?.status == .summaryFailed }

        XCTAssertTrue(failed)
        XCTAssertEqual(finished[id]?.summaryFailure, .empty)
        XCTAssertEqual(finished[id]?.summaryEngine, .apiEndpoint)
        let event = analytics.trackedEvents.last { $0.name == "meeting_summarized" }?.props
        XCTAssertEqual(event?["provider"], .label("api_endpoint"))
        XCTAssertEqual(event?["reason"], .label("empty"))

        await hosted.answer(with: "Title: Sync\n## Decisions\n- Ship on Friday")
        summaries.enqueue(id)
        let done = await eventually { self.finished[id]?.status == .done }
        let requests = await hosted.requests.count

        XCTAssertTrue(done)
        XCTAssertEqual(requests, 2, "a finished run keeps no answer for the next one")
        XCTAssertNil(finished[id]?.summaryFailure)
    }

    func testAStoppedChatGPTSummaryRunsAgainWithTheModelOfItsNewChoice() async throws {
        await hosted.close()
        let id = try await addMeeting(.chatGPT)
        summaries.enqueue(id)
        _ = await eventually { await self.hosted.waiting }

        choices[id] = .automatic
        summaries.cancelRunning(engine: .apiEndpoint)
        try await Task.sleep(for: .milliseconds(30))
        let otherEngineLeftItAlone = await hosted.waiting
        summaries.cancelRunning(engine: .chatgpt)
        let done = await eventually { self.finished[id]?.status == .done }
        let hostedRequests = await hosted.requests.count

        XCTAssertTrue(otherEngineLeftItAlone)
        XCTAssertTrue(done)
        XCTAssertEqual(finished[id]?.summaryEngine, .localModel)
        XCTAssertEqual(hostedRequests, 1, "no new request to ChatGPT after the disconnect")
    }

    func testAHostedFailureReachesTheRecordWithItsKind() async throws {
        await hosted.fail(with: .keyRejected)
        let id = try await addMeeting(.apiEndpoint)

        summaries.enqueue(id)
        let failed = await eventually { self.finished[id]?.status == .summaryFailed }

        XCTAssertTrue(failed)
        XCTAssertEqual(finished[id]?.summaryFailure, .keyRejected)
    }
}

final class MeetingSummaryModelChoiceTests: XCTestCase {
    func testAutomaticNeverGivesAHostedModel() {
        let apple: [AppleFoundationModelsAvailability] = [.available, .deviceNotEligible, .appleIntelligenceNotEnabled]
        let local: [LocalGemmaAvailability] = [.available, .modelNotInstalled, .unsupportedHardware]
        for apple in apple {
            for local in local {
                let automatic = MeetingSummaryAvailability(choice: .automatic, apple: apple, localModel: local)
                XCTAssertEqual(automatic, MeetingSummaryAvailability(apple: apple, localModel: local))
                if case let .ready(engine) = automatic {
                    XCTAssertTrue(engine.isOnDevice)
                }
                XCTAssertEqual(MeetingSummaryAvailability(choice: .apiEndpoint, apple: apple, localModel: local), .ready(.apiEndpoint))
                XCTAssertEqual(MeetingSummaryAvailability(choice: .chatGPT, apple: apple, localModel: local), .ready(.chatgpt))
            }
        }
    }

    func testASummaryModelChoiceThatThisBuildDoesNotKnowIsAutomatic() throws {
        let suite = "MeetingSummaryModelChoiceTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data(#"{"summaryModel":"someLaterService","apiSummaryModelID":"gpt-6.1-sol"}"#.utf8), forKey: "settings")
        let store = MeetingSettingsStore(userDefaults: defaults, key: "settings")

        var loaded = store.load()
        XCTAssertEqual(loaded.summaryModel, .automatic)
        XCTAssertEqual(loaded.apiSummaryModelID, "gpt-6.1-sol")

        loaded.summaryModel = .apiEndpoint
        loaded.apiSummaryAgreedHost = "openrouter.ai"
        store.save(loaded)
        XCTAssertEqual(store.load(), loaded)
    }

    func testAWholeSummaryModelGetsOneRequestAndALongerMeetingGoesToNotesOnParts() async throws {
        let segment = MeetingSegment(id: UUID(), track: .you, audioStart: 0, audioEnd: 16_000, text: talk)
        let short = MeetingSummaryInput(segments: [segment], notes: "", template: .general, speakerLabels: false)
        let model = ScriptedSummaryModel(writesWholeSummary: true)

        let summary = try await MeetingSummaryWriter(model: model).write(short)
        let requests = await model.requests

        XCTAssertEqual(requests.map(\.kind), [.summary], "no notes on 4,000-token parts for a list template")
        XCTAssertEqual(summary.body, "## Decisions\n- Ship on Friday")

        let small = ScriptedSummaryModel(writesWholeSummary: true, context: 2_000)
        let long = MeetingSummaryInput(
            segments: (0 ..< 40).map { MeetingSegment(id: UUID(), track: .you, audioStart: $0 * 16_000, audioEnd: ($0 + 1) * 16_000, text: talk) },
            notes: "",
            template: .general,
            speakerLabels: false
        )
        let longSummary = try await MeetingSummaryWriter(model: small).write(long)
        let kinds = await small.requests.map(\.kind)

        XCTAssertGreaterThan(longSummary.parts, 1)
        XCTAssertEqual(kinds.last, .summary)
        XCTAssertTrue(kinds.dropLast().allSatisfy { if case .part = $0 { return true } else { return $0 == .join } })
    }

    func testAFailedSummaryOffersWhatCanEndTheFailure() {
        var record = MeetingRecord(title: "Call", startedAt: Date(), tracks: [.you], status: .summaryFailed, templateID: "general")
        record.summaryEngine = .apiEndpoint

        record.summaryFailure = .network
        XCTAssertEqual(record.summaryFailureActions(canSummarizeOnThisMac: true), [.tryAgain, .summarizeOnThisMac])
        XCTAssertEqual(record.summaryFailureActions(canSummarizeOnThisMac: false), [.tryAgain])
        record.summaryFailure = .keyRejected
        XCTAssertEqual(record.summaryFailureActions(canSummarizeOnThisMac: true), [.meetingSettings, .summarizeOnThisMac])
        record.summaryFailure = .notSetUp
        XCTAssertEqual(record.summaryFailureActions(canSummarizeOnThisMac: true), [.meetingSettings, .summarizeOnThisMac])
        record.summaryEngine = .chatgpt
        record.summaryFailure = .planLimit
        XCTAssertEqual(record.summaryFailureActions(canSummarizeOnThisMac: true), [.manageUsage, .tryAgain, .summarizeOnThisMac])
        record.summaryFailure = .signInEnded
        XCTAssertEqual(record.summaryFailureActions(canSummarizeOnThisMac: true), [.meetingSettings, .summarizeOnThisMac])
        record.summaryFailure = .planNotAllowed
        XCTAssertEqual(record.summaryFailureActions(canSummarizeOnThisMac: true), [.meetingSettings, .summarizeOnThisMac])
        record.summaryEngine = .apiEndpoint
        XCTAssertEqual(MeetingSummaryFailure.timeout.cause(hosted: true), "The summary service took too long.")

        record.summaryEngine = .localModel
        record.summaryFailure = .timeout
        XCTAssertEqual(record.summaryFailureActions(canSummarizeOnThisMac: true), [.tryAgain], "an on-device failure has no other model to offer")
        XCTAssertEqual(MeetingSummaryFailure.timeout.cause(hosted: false), "The model took too long.")
    }
}

final class APIEndpointMeetingSummaryModelTests: XCTestCase {
    private let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    private let request = MeetingSummaryRequest(kind: .summary, instructions: "You write the summary.", input: "<transcript>\nYou: Ship on Friday.\n</transcript>")

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func settings(agreedHost: String? = "openrouter.ai", modelID: String = "openai/gpt-6.1-sol") -> MeetingSettings {
        var settings = MeetingSettings()
        settings.summaryModel = .apiEndpoint
        settings.apiSummaryModelID = modelID
        settings.apiSummaryAgreedHost = agreedHost
        return settings
    }

    private func model(_ settings: MeetingSettings, apiKey: String? = "sk-test") -> APIEndpointMeetingSummaryModel {
        APIEndpointMeetingSummaryModel(client: ChatCompletionClient(session: URLSession(configuration: StubURLProtocol.sessionConfiguration()))) { [endpoint] in
            APIEndpointSummarySetup(settings: settings, endpointURL: endpoint, apiKey: apiKey)
        }
    }

    private func answer(status: Int = 200, body: String) {
        StubURLProtocol.serve([endpoint: .init(statusCode: status, body: Data(body.utf8))])
    }

    private func failure(_ run: () async throws -> String) async -> MeetingSummaryFailure? {
        do {
            _ = try await run()
            return nil
        } catch MeetingSummaryError.failed(let kind) {
            return kind
        } catch {
            return nil
        }
    }

    func testTheRequestHasTheModelAndTheTextAndNoSamplingOrOutputLimit() async throws {
        var body: [String: Any]?
        var authorization: String?
        StubURLProtocol.handler = { [endpoint] request in
            body = StubURLProtocol.requestBody(of: request).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            authorization = request.value(forHTTPHeaderField: "Authorization")
            let answer = #"{"choices":[{"message":{"content":" Title: Plan\n## Decisions\n- Ship on Friday \n"},"finish_reason":"stop"}]}"#
            return (HTTPURLResponse(url: endpoint, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(answer.utf8))
        }

        let text = try await model(settings()).generate(request)

        XCTAssertEqual(text, "Title: Plan\n## Decisions\n- Ship on Friday")
        XCTAssertEqual(authorization, "Bearer sk-test")
        XCTAssertEqual(body?["model"] as? String, "openai/gpt-6.1-sol")
        XCTAssertEqual(Set(body?.keys.map { $0 } ?? []), ["model", "messages"], "no temperature and no max_tokens")
        let messages = body?["messages"] as? [[String: String]]
        XCTAssertEqual(messages?.map { $0["role"] }, ["system", "user"])
        XCTAssertEqual(messages?.last?["content"], request.input)
    }

    func testEachProviderAnswerGivesItsFailureKind() async {
        answer(status: 401, body: "{}")
        let rejected = await failure { try await self.model(self.settings()).generate(self.request) }
        answer(status: 500, body: "{}")
        let serviceError = await failure { try await self.model(self.settings()).generate(self.request) }
        answer(body: #"{"choices":[{"message":{"content":"Title: Plan"},"finish_reason":"length"}]}"#)
        let truncated = await failure { try await self.model(self.settings()).generate(self.request) }
        answer(body: #"{"choices":[{"message":{"content":"  \n"},"finish_reason":"stop"}]}"#)
        let empty = await failure { try await self.model(self.settings()).generate(self.request) }
        StubURLProtocol.serve([endpoint: .init(error: URLError(.notConnectedToInternet))])
        let network = await failure { try await self.model(self.settings()).generate(self.request) }

        XCTAssertEqual(rejected, .keyRejected)
        XCTAssertEqual(serviceError, .serviceError)
        XCTAssertEqual(truncated, .truncated)
        XCTAssertEqual(empty, .empty)
        XCTAssertEqual(network, .network)
    }

    func testWithoutAKeyAModelIDOrTheAgreedHostNothingIsSent() async {
        var sent = 0
        StubURLProtocol.handler = { _ in
            sent += 1
            throw URLError(.badServerResponse)
        }

        let noKey = await failure { try await self.model(self.settings(), apiKey: nil).generate(self.request) }
        let noModel = await failure { try await self.model(self.settings(modelID: " ")).generate(self.request) }
        let noAgreement = await failure { try await self.model(self.settings(agreedHost: nil)).generate(self.request) }
        let otherHost = await failure { try await self.model(self.settings(agreedHost: "api.openai.com")).generate(self.request) }

        XCTAssertEqual([noKey, noModel, noAgreement, otherHost], [.notSetUp, .notSetUp, .notSetUp, .notSetUp])
        XCTAssertEqual(sent, 0)
    }
}
