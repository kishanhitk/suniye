import AVFoundation
#if canImport(FoundationModels)
import FoundationModels
#endif
import XCTest
@testable import Suniye

/// Opt-in end-to-end checks of the meeting pipeline with the real models: a
/// synthesized two-voice call through the segmenter, Parakeet v3 and the echo
/// filter, and long meetings through the local model's summary. Skipped
/// unless enabled, so CI (which has no models) and routine runs stay fast.
///
/// Run it:
///   TEST_RUNNER_SUNIYE_RUN_MEETING_TESTS=1 \
///   [TEST_RUNNER_SUNIYE_LLAMA_SERVER_PATH=/path/to/llama-server] \
///   xcodebuild test -project Suniye.xcodeproj -scheme Suniye \
///     -destination 'platform=macOS,arch=arm64' -derivedDataPath .derivedData \
///     -only-testing:SuniyeTests/MeetingPipelineRealModelTests
final class MeetingPipelineRealModelTests: XCTestCase {
    private static let rate = MeetingAudioFormat.sampleRate

    /// Each turn and a word that only its transcript line should hold.
    private static let call: [(track: MeetingTrack, text: String, word: String)] = [
        (.them, "Good morning. Let us start with the release plan for this week.", "release"),
        (.you, "The new build is ready, and the testers have it since yesterday.", "testers"),
        (.them, "Quality assurance found one crash in the settings screen.", "crash"),
        (.you, "I will fix that today and send a new build tomorrow morning.", "tomorrow"),
        (.them, "Then we ship on Friday, and Priya writes the release notes.", "friday"),
        (.you, "Agreed. I will tell the support team about the date.", "support"),
    ]

    private struct Fact {
        let line: String
        let found: (String) -> Bool
    }

    /// Facts planted in a long meeting; the summary should keep each one.
    private static let facts: [Fact] = [
        Fact(line: "We decided to ship version 2.4 on Friday.") { $0.contains("friday") },
        Fact(line: "Priya will write the release notes.") { $0.contains("priya") },
        Fact(line: "The budget for the pilot is forty thousand dollars.") {
            $0.contains("40,000") || $0.contains("40000") || $0.contains("40k") || $0.contains("forty thousand")
        },
        Fact(line: "Marco owns the database migration and finishes it by Wednesday.") { $0.contains("marco") },
        Fact(line: "We dropped the Android widget from this release.") { $0.contains("widget") },
        Fact(line: "The next review is on the third of December.") { $0.contains("december") },
    ]

    private var root: URL!

    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["SUNIYE_RUN_MEETING_TESTS"] == "1",
            "Set SUNIYE_RUN_MEETING_TESTS=1 to run the meeting real-model tests"
        )
        root = FileManager.default.temporaryDirectory.appendingPathComponent("MeetingPipeline-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
    }

    // MARK: - Transcript

    func testATwoVoiceCallBecomesOrderedLinesOnTheRightTracks() async throws {
        let transcript = try await transcribeCall(echo: false)

        try assertCallLines(transcript)
    }

    func testOnSpeakersTheEchoOfTheCallLeavesTheMicrophoneTrack() async throws {
        let transcript = try await transcribeCall(echo: true)

        try assertCallLines(transcript)
        for turn in Self.call where turn.track == .them {
            let echoes = transcript.filter { $0.track == .you && $0.text.lowercased().contains(turn.word) }
            XCTAssertTrue(echoes.isEmpty, "echo of \"\(turn.text)\" stayed on the microphone track: \(echoes.map(\.text))")
        }
    }

    private func assertCallLines(_ transcript: [MeetingSegment]) throws {
        var lastStart = -1
        for turn in Self.call {
            let line = try XCTUnwrap(
                transcript.first { $0.track == turn.track && $0.text.lowercased().contains(turn.word) },
                "no \(turn.track.rawValue) line with \"\(turn.word)\" in \(transcript.map { "\($0.track.rawValue): \($0.text)" })"
            )
            XCTAssertGreaterThan(line.audioStart, lastStart, "\"\(turn.word)\" is out of order")
            lastStart = line.audioStart
        }
    }

    /// Feeds the call to a transcriber in 100 ms blocks per track, the way the
    /// recorder does, and returns the final transcript.
    private func transcribeCall(echo: Bool) async throws -> [MeetingSegment] {
        let manager = ModelManager()
        try XCTSkipUnless(manager.isInstalled(.parakeetV3), "Parakeet v3 is not installed")
        let engine = TranscriptionService()
        try await engine.loadModel(config: manager.makeRecognizerConfig(for: .parakeetV3))

        let tracks = try await Self.synthesizeCall(echo: echo)
        let store = MeetingStore(rootDirectory: root)
        let record = MeetingRecord(title: "Call", startedAt: Date(), tracks: [.you, .them], templateID: MeetingTemplate.general.id, callPlayedOnSpeakers: echo)
        try await store.create(record)
        for track in MeetingTrack.allCases {
            let writer = try MeetingAudioFileWriter(url: store.audioURL(track, for: record.id))
            try writer.append(tracks[track]!)
            try writer.close()
        }
        let transcriber = MeetingTranscriber(
            meetingID: record.id,
            tracks: MeetingTrack.allCases,
            store: store,
            engine: engine,
            mayDecode: { true },
            onEvent: { _ in }
        )
        await transcriber.start()
        let block = Self.rate / 10
        for start in stride(from: 0, to: tracks[.you]!.count, by: block) {
            for track in MeetingTrack.allCases {
                let samples = tracks[track]!
                transcriber.enqueue(.samples(track, Array(samples[start ..< min(start + block, samples.count)]), position: start))
            }
        }
        let started = ContinuousClock.now
        let transcript = try await transcriber.finish()
        let seconds = (ContinuousClock.now - started) / .seconds(1)
        print("meeting call echo=\(echo): \(String(format: "%.1f", Double(tracks[.you]!.count) / Double(Self.rate)))s per track, finish \(String(format: "%.1f", seconds))s")
        for line in transcript {
            print("  \(line.track.rawValue) \(String(format: "%5.1f", Double(line.audioStart) / Double(Self.rate))): \(line.text)")
        }
        return transcript
    }

    /// Two voices take turns with 0.8 s between turns. With `echo`, the
    /// microphone also hears the call at a third of its level, 30 ms late.
    private static func synthesizeCall(echo: Bool) async throws -> [MeetingTrack: [Float]] {
        let english = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        let them = english.first
        let you = english.first { $0.identifier != them?.identifier }
        try XCTSkipUnless(them != nil && you != nil, "Two English voices are needed")

        var lanes: [MeetingTrack: [Float]] = [.you: [], .them: []]
        let gap = [Float](repeating: 0, count: rate * 8 / 10)
        for turn in call {
            let speech = await SpeechTestAudio.synthesizeSpeech(turn.text, sampleRate: Double(rate), voice: turn.track == .you ? you : them)
            try XCTSkipUnless(speech.count > rate, "Speech synthesis unavailable")
            let other: MeetingTrack = turn.track == .you ? .them : .you
            lanes[turn.track]! += speech + gap
            lanes[other]! += [Float](repeating: 0, count: speech.count + gap.count)
        }
        if echo {
            let delay = rate * 3 / 100
            let callAudio = lanes[.them]!
            var microphone = lanes[.you]!
            for index in delay ..< microphone.count {
                microphone[index] += callAudio[index - delay] / 3
            }
            lanes[.you] = microphone
        }
        return lanes
    }

    // MARK: - Summary

    /// Two sets of long meetings. In each, six facts are said once in talk
    /// that decides nothing: a harder test than a real meeting, where a
    /// decision is usually said more than once. Each run prints the facts in
    /// the notes on the parts and the facts in the summary; the check is that
    /// the summary finishes, has a title and keeps each fact that the notes
    /// on the parts have. Decoding is greedy, so a second
    /// run of one meeting gives the same text: `SUNIYE_EVAL_VARIANTS` sets how
    /// many meetings of each length and set run, each with the talk and the
    /// facts in other places.
    func testTheLocalModelSummarizesLongMeetings() async throws {
        let client = LocalGemmaLlamaCppClient()
        try XCTSkipUnless(client.availability == .available, "The local model or llama-server is not available")
        addTeardownBlock { await client.stopRuntime() }
        try await runSummaryEvals(engine: "local") { LocalGemmaMeetingSummaryModel(client: client) }
    }

    func testAppleIntelligenceSummarizesLongMeetings() async throws {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else { throw XCTSkip("Apple Intelligence needs macOS 26") }
        try XCTSkipUnless(SystemLanguageModel.default.availability == .available, "Apple Intelligence is not available")
        try await runSummaryEvals(engine: "apple") { AppleMeetingSummaryModel() }
        #else
        throw XCTSkip("No FoundationModels")
        #endif
    }

    private struct EvalSet {
        let name: String
        let facts: [Fact]
        let meeting: (_ minutes: Int, _ variant: Int) -> [MeetingSegment]
    }

    private static let evalSets = [
        EvalSet(name: "A", facts: facts, meeting: meeting(minutes:variant:)),
        EvalSet(name: "B", facts: planningFacts, meeting: planningMeeting(minutes:variant:)),
    ]

    private func runSummaryEvals(engine: String, model: () -> MeetingSummaryModel) async throws {
        let variants = Int(ProcessInfo.processInfo.environment["SUNIYE_EVAL_VARIANTS"] ?? "") ?? 1
        var failures = 0
        for set in Self.evalSets {
            for minutes in [45, 120] {
                for variant in 0 ..< variants {
                    let recorder = RecordingSummaryModel(model())
                    let segments = set.meeting(minutes, variant)
                    let input = MeetingSummaryInput(segments: segments, notes: "", template: .general, speakerLabels: true)
                    let label = "EVAL engine=\(engine) set=\(set.name) minutes=\(minutes) variant=\(variant)"
                    let started = ContinuousClock.now
                    do {
                        let summary = try await MeetingSummaryWriter(model: recorder).write(input)
                        let seconds = (ContinuousClock.now - started) / .seconds(1)
                        let text = ((summary.title ?? "") + "\n" + summary.body).lowercased()
                        let notes = await recorder.partAnswers.joined(separator: "\n").lowercased()
                        let notesScore = notes.isEmpty ? "-" : "\(set.facts.filter { $0.found(notes) }.count)/\(set.facts.count)"
                        let kept = set.facts.filter { $0.found(text) }
                        let missing = set.facts.filter { !$0.found(text) }.map(\.line)
                        let lost = set.facts.filter { $0.found(notes) && !$0.found(text) }.map(\.line)
                        print("\(label) parts=\(summary.parts) seconds=\(Int(seconds)) title=\(summary.title != nil) notes=\(notesScore) summary=\(kept.count)/\(set.facts.count) missing=\(missing)")
                        print(summary.title ?? "(no title)")
                        print(summary.body)
                        XCTAssertNotNil(summary.title, label)
                        XCTAssertEqual(lost, [], "\(label): facts in the notes on the parts that the summary lost")
                    } catch {
                        failures += 1
                        print("\(label) failed: \(error.localizedDescription)")
                    }
                }
            }
        }
        XCTAssertEqual(failures, 0, "summaries that failed")
    }

    /// About 150 words a minute of two people talking, with the facts spread
    /// over the meeting. The talk around them is discussion with no decision,
    /// task, date or number, from fixed lists, so each run gets the same
    /// transcript and the facts are the only things to keep. Each variant
    /// starts the lists at another place and moves the facts.
    private static func meeting(minutes: Int, variant: Int) -> [MeetingSegment] {
        let subjects = ["the onboarding flow", "the billing page", "the search results", "the sync service", "the import screen", "the error reports", "the help center", "the sign-in page", "the export feature", "the team settings", "the dark theme", "the empty states"]
        let findings = [
            "feels slow on a weak connection",
            "still shows the old wording on the second step",
            "got mixed reactions in the interviews",
            "behaves better since the last change",
            "confuses people who are new to the product",
            "looks fine on a large screen but cramped on a small one",
            "gets fewer complaints than it used to",
            "is hard to find from the main menu",
            "reads well, but the labels are long",
            "works, although nobody loves it",
        ]
        let openers = ["I think", "From what I saw,", "In the recordings,", "In the data,", "To be honest,", "As far as I know,", "My feeling is that", "People told us that"]
        let replies = ["That matches what I heard.", "I am not sure about that.", "Interesting, I saw the same thing.", "Hm, that surprises me.", "Right, that makes sense."]
        let wordsTarget = minutes * 150
        var lines: [String] = []
        var words = 0
        var step = variant * 13
        while words < wordsTarget {
            let subject = subjects[step % subjects.count]
            let finding = findings[(step * 7 + step / subjects.count) % findings.count]
            let opener = openers[(step * 5) % openers.count]
            let line = step.isMultiple(of: 4)
                ? replies[(step / 4) % replies.count]
                : "\(opener) \(subject) \(finding)."
            lines.append(line)
            words += MeetingTranscript.words(in: line).count
            step += 1
        }
        for (index, fact) in facts.enumerated() {
            let position = (lines.count * (2 * index + 1) / (2 * facts.count) + variant * 17) % lines.count
            lines.insert(fact.line, at: position)
        }
        return segments(lines)
    }

    /// Facts for the second set: a planning meeting where each fact sits in
    /// the middle of a longer turn.
    private static let planningFacts: [Fact] = [
        Fact(line: "We agreed to hold the launch event in Lisbon.") { $0.contains("lisbon") },
        Fact(line: "Amara sends the vendor contract to legal by the fourteenth.") { $0.contains("amara") },
        Fact(line: "We expect about 2,500 sign-ups in the first week.") {
            $0.contains("2,500") || $0.contains("2500") || $0.contains("2.5k") || $0.contains("two thousand five hundred")
        },
        Fact(line: "Nobody knows yet whether the data team can join the pilot.") { $0.contains("data team") },
        Fact(line: "We cancelled the referral bonus for now.") { $0.contains("referral") },
        Fact(line: "The board meeting moved to the ninth of March.") { $0.contains("march") },
    ]

    /// Turns of three sentences: a topic, a middle sentence and a close. A
    /// fact takes the place of the middle sentence of one turn.
    private static func planningMeeting(minutes: Int, variant: Int) -> [MeetingSegment] {
        let topics = ["the venue shortlist", "the speaker lineup", "the hiring plan", "the onboarding guide", "the partner newsletter", "the travel policy", "the office move", "the support rota", "the press kit"]
        let states = ["needs another pass", "is still being discussed", "came up in the last call", "has a few open threads", "looks reasonable so far", "depends on a few people", "was mentioned by the team"]
        let openers = ["Quick update on", "Thinking about", "Coming back to", "A word on", "About"]
        let middles = [
            "Some people liked the direction and some did not.",
            "We heard a few different views on it this week.",
            "It is too early to say much more than that.",
            "A couple of people asked questions about it.",
            "The feedback so far has been fairly quiet.",
            "It keeps coming up in side conversations.",
        ]
        let closers = ["Let us keep an eye on it.", "We can talk about it later.", "Nothing to change today.", "I will share more when I know more.", "That is all from me on that."]
        let wordsTarget = minutes * 150
        var turns: [String] = []
        var words = 0
        var step = variant * 11
        while words < wordsTarget {
            let opener = openers[step % openers.count]
            let topic = topics[(step * 4 + step / topics.count) % topics.count]
            let state = states[(step * 3) % states.count]
            let middle = middles[(step * 5) % middles.count]
            let closer = closers[(step * 2 + step / closers.count) % closers.count]
            let turn = "\(opener) \(topic), it \(state). \(middle) \(closer)"
            turns.append(turn)
            words += MeetingTranscript.words(in: turn).count
            step += 1
        }
        for (index, fact) in planningFacts.enumerated() {
            let position = (turns.count * (2 * index + 1) / (2 * planningFacts.count) + variant * 23) % turns.count
            let sentences = turns[position].components(separatedBy: ". ")
            turns[position] = sentences[0] + ". " + fact.line + " " + (sentences.last ?? "")
        }
        return segments(turns)
    }

    /// One segment per line, the speakers taking turns, at 150 words a minute.
    private static func segments(_ lines: [String]) -> [MeetingSegment] {
        let samplesPerWord = rate * 60 / 150
        var position = 0
        return lines.enumerated().map { index, text in
            let length = MeetingTranscript.words(in: text).count * samplesPerWord
            defer { position += length }
            return MeetingSegment(
                id: UUID(),
                track: index.isMultiple(of: 2) ? .them : .you,
                audioStart: position,
                audioEnd: position + length,
                text: text
            )
        }
    }
}

/// Keeps the answers to the part requests, so an eval can count the facts in
/// the notes before the last step.
private actor RecordingSummaryModel: MeetingSummaryModel {
    private let base: MeetingSummaryModel
    private(set) var partAnswers: [String] = []

    init(_ base: MeetingSummaryModel) {
        self.base = base
    }

    func contextTokens() async -> Int {
        await base.contextTokens()
    }

    func tokenCount(_ text: String) async -> Int? {
        await base.tokenCount(text)
    }

    func generate(_ request: MeetingSummaryRequest) async throws -> String {
        let answer = try await base.generate(request)
        if case .part = request.kind {
            partAnswers.append(answer)
        }
        return answer
    }
}
