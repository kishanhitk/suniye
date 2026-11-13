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
        let record = MeetingRecord(title: "Call", startedAt: Date(), templateID: MeetingTemplate.general.id, callPlayedOnSpeakers: echo)
        try await store.create(record)
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

    /// Each fact is said once, in 7,000 to 18,000 words of talk that decides
    /// nothing: a harder test than a real meeting, where a decision is
    /// usually said more than once. The score is printed; the check is that
    /// the summary finishes, has a title and keeps at least two facts.
    func testTheLocalModelSummarizesLongMeetings() async throws {
        let client = LocalGemmaLlamaCppClient()
        try XCTSkipUnless(client.availability == .available, "The local model or llama-server is not available")
        addTeardownBlock { await client.stopRuntime() }
        for minutes in [45, 120] {
            try await summarize(minutes: minutes, with: LocalGemmaMeetingSummaryModel(client: client))
        }
    }

    func testAppleIntelligenceSummarizesLongMeetings() async throws {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else { throw XCTSkip("Apple Intelligence needs macOS 26") }
        try XCTSkipUnless(SystemLanguageModel.default.availability == .available, "Apple Intelligence is not available")
        for minutes in [45, 120] {
            try await summarize(minutes: minutes, with: AppleMeetingSummaryModel())
        }
        #else
        throw XCTSkip("No FoundationModels")
        #endif
    }

    private func summarize(minutes: Int, with model: MeetingSummaryModel) async throws {
        let segments = Self.meeting(minutes: minutes)
        let input = MeetingSummaryInput(segments: segments, notes: "", template: .general, speakerLabels: true)

        let started = ContinuousClock.now
        let summary = try await MeetingSummaryWriter(model: model).write(input)
        let seconds = (ContinuousClock.now - started) / .seconds(1)

        let text = ((summary.title ?? "") + "\n" + summary.body).lowercased()
        let kept = Self.facts.filter { $0.found(text) }
        let words = segments.reduce(0) { $0 + MeetingTranscript.words(in: $1.text).count }
        print("meeting summary \(type(of: model)) \(minutes) min: \(words) words, parts \(summary.parts), \(String(format: "%.0f", seconds)) s, facts \(kept.count)/\(Self.facts.count), missing \(Self.facts.filter { !$0.found(text) }.map(\.line))")
        print(summary.title ?? "(no title)")
        print(summary.body)
        XCTAssertNotNil(summary.title)
        XCTAssertGreaterThanOrEqual(kept.count, 2)
    }

    /// About 150 words a minute of two people talking, with the facts spread
    /// over the meeting. The talk around them is discussion with no decision,
    /// task, date or number, from fixed lists, so each run gets the same
    /// transcript and the facts are the only things to keep.
    private static func meeting(minutes: Int) -> [MeetingSegment] {
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
        var step = 0
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
            let position = lines.count * (2 * index + 1) / (2 * facts.count)
            lines.insert(fact.line, at: position)
        }
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
