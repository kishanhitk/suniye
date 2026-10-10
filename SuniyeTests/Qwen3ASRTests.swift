import XCTest
@testable import Suniye

/// The model-free half of the Qwen3-ASR engine. Parser and repetition vectors
/// come from running the reference `qwen-asr` toolkit's `parse_asr_output`.
final class Qwen3ASRTests: XCTestCase {
    // MARK: - Helper and request

    func testServerArgumentsLoadTheProjectorAndDisableThePromptCache() {
        XCTAssertEqual(Qwen3ASR.serverArguments(modelPath: "/m/model.gguf", projectorPath: "/m/mmproj.gguf"), [
            "--model", "/m/model.gguf",
            "--mmproj", "/m/mmproj.gguf",
            "--ctx-size", "4096",
            "--parallel", "1",
            "--cache-ram", "0",
        ])
    }

    func testChunksFitTheContextWindow() {
        XCTAssertEqual(Qwen3ASR.chunker.maxChunkSamples, 90 * Qwen3ASR.sampleRate)
        // ~13 audio tokens per second, plus the largest reply budget, stays inside the context.
        let longestChunk = Qwen3ASR.chunker.maxChunkSamples
        XCTAssertLessThan(90 * 14 + Qwen3ASR.maxTokens(sampleCount: longestChunk), Qwen3ASR.contextSize)
    }

    func testTokenBudgetAndTimeoutScaleWithAudioLength() {
        XCTAssertEqual(Qwen3ASR.maxTokens(sampleCount: 0), 32)
        XCTAssertEqual(Qwen3ASR.maxTokens(sampleCount: 16_000), 52)
        XCTAssertEqual(Qwen3ASR.maxTokens(sampleCount: 8_000), 42)
        XCTAssertEqual(Qwen3ASR.timeoutSeconds(sampleCount: 0), 30)
        XCTAssertEqual(Qwen3ASR.timeoutSeconds(sampleCount: 90 * 16_000), 120)
    }

    func testPayloadIsAnEmptySystemTurnThenAUserTurnHoldingOnlyTheWav() throws {
        let samples = [Float](repeating: 0.25, count: 16_000)

        let body = try encode(Qwen3ASR.makePayload(samples: samples, modelName: "Qwen3-ASR 1.7B"))

        XCTAssertEqual(body["model"] as? String, "Qwen3-ASR 1.7B")
        XCTAssertEqual(body["temperature"] as? Int, 0)
        XCTAssertEqual(body["max_tokens"] as? Int, Qwen3ASR.maxTokens(sampleCount: 16_000))
        XCTAssertEqual(body["stream"] as? Bool, false)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"] as? String, "system")
        XCTAssertEqual(messages[0]["content"] as? String, "")
        XCTAssertEqual(messages[1]["role"] as? String, "user")
        let parts = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(parts[0]["type"] as? String, "input_audio")
        let audio = try XCTUnwrap(parts[0]["input_audio"] as? [String: String])
        XCTAssertEqual(audio["format"], "wav")
        XCTAssertEqual(Data(base64Encoded: try XCTUnwrap(audio["data"])), Qwen3ASR.wavData(samples: samples))
    }

    func testPayloadPadsClipsShorterThanHalfASecond() throws {
        let body = try encode(Qwen3ASR.makePayload(samples: [0.5, 0.5], modelName: "m"))

        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let parts = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])
        let audio = try XCTUnwrap(parts[0]["input_audio"] as? [String: String])
        let wav = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(audio["data"])))
        XCTAssertEqual(wav.count, 44 + Qwen3ASR.minimumSamples * 2)
        XCTAssertEqual(body["max_tokens"] as? Int, Qwen3ASR.maxTokens(sampleCount: Qwen3ASR.minimumSamples))
    }

    func testWavDataIsSixteenBitMonoPCMAtSixteenKilohertz() {
        let wav = Qwen3ASR.wavData(samples: [0, 1, -1, 2, -2, 0.5])
        let bytes = [UInt8](wav)

        XCTAssertEqual(String(decoding: bytes[0 ..< 4], as: UTF8.self), "RIFF")
        XCTAssertEqual(uint32(bytes, at: 4), 36 + 12)
        XCTAssertEqual(String(decoding: bytes[8 ..< 16], as: UTF8.self), "WAVEfmt ")
        XCTAssertEqual(uint32(bytes, at: 16), 16)
        XCTAssertEqual(uint16(bytes, at: 20), 1, "PCM")
        XCTAssertEqual(uint16(bytes, at: 22), 1, "mono")
        XCTAssertEqual(uint32(bytes, at: 24), 16_000)
        XCTAssertEqual(uint32(bytes, at: 28), 32_000)
        XCTAssertEqual(uint16(bytes, at: 32), 2)
        XCTAssertEqual(uint16(bytes, at: 34), 16)
        XCTAssertEqual(String(decoding: bytes[36 ..< 40], as: UTF8.self), "data")
        XCTAssertEqual(uint32(bytes, at: 40), 12)
        let pcm = (0 ..< 6).map { Int16(bitPattern: uint16(bytes, at: 44 + $0 * 2)) }
        XCTAssertEqual(pcm, [0, 32_767, -32_767, 32_767, -32_767, 16_384], "out-of-range samples clip")
    }

    // MARK: - Reply

    func testParseReplySplitsTheLanguageFromTheTranscript() {
        XCTAssertEqual(Qwen3ASR.parseReply("language English<asr_text>Hello there."), .init(language: "English", text: "Hello there."))
        XCTAssertEqual(Qwen3ASR.parseReply("  language French<asr_text>  Bonjour  "), .init(language: "French", text: "Bonjour"))
        XCTAssertEqual(Qwen3ASR.parseReply("language cHINese\n<asr_text>你好"), .init(language: "Chinese", text: "你好"))
    }

    func testParseReplyTreatsLanguageNoneAsNoLanguage() {
        XCTAssertEqual(Qwen3ASR.parseReply("language None<asr_text>"), .init(language: nil, text: ""))
        XCTAssertEqual(Qwen3ASR.parseReply("language None<asr_text>嗯"), .init(language: nil, text: "嗯"))
        XCTAssertEqual(Qwen3ASR.parseReply("<asr_text>no header"), .init(language: nil, text: "no header"))
    }

    func testParseReplyWithoutTheTagIsAllTranscript() {
        XCTAssertEqual(Qwen3ASR.parseReply("Plain text without tag"), .init(language: nil, text: "Plain text without tag"))
        XCTAssertEqual(Qwen3ASR.parseReply(""), .init(language: nil, text: ""))
    }

    func testParseReplyCollapsesALoopingDecode() {
        let looping = "language English<asr_text>" + String(repeating: "no ", count: 30)

        XCTAssertEqual(Qwen3ASR.parseReply(looping), .init(language: "English", text: "no no"))
    }

    func testCollapsingRepetitionsMatchesTheReference() {
        let vectors: [(String, String)] = [
            (String(repeating: "a", count: 25), "a"),
            (String(repeating: "x", count: 20), String(repeating: "x", count: 20)),
            (String(repeating: "ha", count: 25) + " done", "ha done"),
            (String(repeating: "abc ", count: 21) + "end", "abc end"),
            (String(repeating: "abc ", count: 19) + "end", String(repeating: "abc ", count: 19) + "end"),
            ("hello world", "hello world"),
            (String(repeating: "我", count: 30) + "们", "我们"),
            ("ok " + String(repeating: "la", count: 30) + " fine " + String(repeating: "z", count: 22), "ok la fine z"),
            (String(repeating: "the ", count: 23) + "cat", "the cat"),
        ]

        for (input, expected) in vectors {
            XCTAssertEqual(Qwen3ASR.collapsingRepetitions(input), expected, input)
        }
    }

    func testJoinRepliesSpacesChunksExceptInLanguagesWrittenWithoutSpaces() {
        XCTAssertEqual(Qwen3ASR.joinReplies([]), "")
        XCTAssertEqual(
            Qwen3ASR.joinReplies([.init(language: "English", text: "First part."), .init(language: nil, text: ""), .init(language: "English", text: "Second part.")]),
            "First part. Second part."
        )
        XCTAssertEqual(
            Qwen3ASR.joinReplies([.init(language: "Chinese", text: "明天下午"), .init(language: "Chinese", text: "三点开会。")]),
            "明天下午三点开会。"
        )
    }

    // MARK: - Helpers

    private func encode(_ payload: ChatCompletionPayload) throws -> [String: Any] {
        let data = try JSONEncoder().encode(payload)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func uint16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    private func uint32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(uint16(bytes, at: offset)) | UInt32(uint16(bytes, at: offset + 2)) << 16
    }
}
