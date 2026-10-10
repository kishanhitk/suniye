import XCTest
@testable import Suniye

final class CohereTranscribeDecodingTests: XCTestCase {
    // MARK: - Language

    func testResolveLanguagePrefersSupportedHint() {
        XCTAssertEqual(CohereTranscribe.resolveLanguage(hint: "de", locale: Locale(identifier: "fr_FR")), "de")
        XCTAssertEqual(CohereTranscribe.resolveLanguage(hint: " ja ", locale: Locale(identifier: "en_US")), "ja")
    }

    func testResolveLanguageFallsBackToLocaleThenEnglish() {
        XCTAssertEqual(CohereTranscribe.resolveLanguage(hint: "", locale: Locale(identifier: "fr_FR")), "fr")
        XCTAssertEqual(CohereTranscribe.resolveLanguage(hint: "xx", locale: Locale(identifier: "zh-Hans_CN")), "zh")
        XCTAssertEqual(CohereTranscribe.resolveLanguage(hint: "", locale: Locale(identifier: "hi_IN")), "en")
        XCTAssertEqual(CohereTranscribe.resolveLanguage(hint: "auto", locale: Locale(identifier: "sv_SE")), "en")
    }

    func testSupportedLanguagesMatchTheModelCard() {
        XCTAssertEqual(CohereTranscribe.supportedLanguages.count, 14)
    }

    // MARK: - Chunk joining

    func testJoinChunkTextsUsesSpaceAndDropsEmptyChunks() {
        XCTAssertEqual(
            CohereTranscribe.joinChunkTexts([" Hello there. ", "", "   ", "General Kenobi."], language: "en"),
            "Hello there. General Kenobi."
        )
    }

    func testJoinChunkTextsUsesNoSeparatorForJapaneseAndChinese() {
        XCTAssertEqual(CohereTranscribe.joinChunkTexts(["你好", "世界"], language: "zh"), "你好世界")
        XCTAssertEqual(CohereTranscribe.joinChunkTexts(["こんにちは", "世界"], language: "ja"), "こんにちは世界")
        XCTAssertEqual(CohereTranscribe.joinChunkTexts(["안녕", "세계"], language: "ko"), "안녕 세계")
    }

    // MARK: - Vocabulary

    private static let vocabularyText = """
    <unk> 0
    <|nospeech|> 1
    <pad> 2
    <|endoftext|> 3
    <|startoftranscript|> 4
    <|pnc|> 5
    <|startofcontext|> 7
    <|noitn|> 9
    <|notimestamp|> 11
    <|nodiarize|> 13
    <|emo:undefined|> 16
    <|en|> 50
    <|de|> 51
    ▁hello 100
    ▁world 101
    ' 102
    s 103
    <0xE4> 104
    <0xBD> 105
    <0xA0> 106
    . 107
    """

    func testVocabularyParsesPieceIDLines() throws {
        let vocabulary = try CohereVocabulary(text: Self.vocabularyText)

        XCTAssertEqual(vocabulary.endOfTextID, 3)
        XCTAssertEqual(vocabulary.pieces.count, 108)
        XCTAssertEqual(vocabulary.pieces[100], "▁hello")
        XCTAssertEqual(vocabulary.pieces[6], "", "unassigned ids stay empty")
    }

    func testVocabularyRejectsFilesWithoutEndOfText() {
        XCTAssertThrowsError(try CohereVocabulary(text: "a 0\nb 1\n")) { error in
            XCTAssertEqual(error.localizedDescription, "Invalid Cohere vocabulary: missing <|endoftext|>")
        }
        XCTAssertThrowsError(try CohereVocabulary(text: "no ids here\n")) { error in
            XCTAssertEqual(error.localizedDescription, "Invalid Cohere vocabulary: no `piece id` lines")
        }
    }

    func testVocabularyLoadsFromDisk() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cohere-tokens-\(UUID().uuidString).txt")
        try Self.vocabularyText.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(try CohereVocabulary(contentsOf: url.path).endOfTextID, 3)
    }

    func testPromptIDsFollowTheReferenceLayout() throws {
        let vocabulary = try CohereVocabulary(text: Self.vocabularyText)

        XCTAssertEqual(try vocabulary.promptIDs(language: "en"), [7, 4, 16, 50, 50, 5, 9, 11, 13])
        XCTAssertEqual(try vocabulary.promptIDs(language: "de"), [7, 4, 16, 51, 51, 5, 9, 11, 13])
        XCTAssertThrowsError(try vocabulary.promptIDs(language: "fr"))
    }

    func testTextDecodingHandlesWordBoundariesSpecialsAndByteFallback() throws {
        let vocabulary = try CohereVocabulary(text: Self.vocabularyText)

        XCTAssertEqual(vocabulary.text(for: [100, 101, 102, 103, 107]), "hello world's.")
        XCTAssertEqual(vocabulary.text(for: [1, 100, 0, 2, 50, 107]), "hello.")
        XCTAssertEqual(vocabulary.text(for: [104, 105, 106]), "你")
        XCTAssertEqual(vocabulary.text(for: [-1, 999, 100]), "hello", "out-of-range ids are ignored")
        XCTAssertEqual(vocabulary.text(for: []), "")
    }

    // MARK: - Greedy decoder

    private func pick(_ decoder: inout CohereGreedyDecoder, _ logits: [Float]) -> Int64? {
        logits.withUnsafeBufferPointer { decoder.next(logits: $0) }
    }

    func testGreedyDecoderPicksArgmaxAndStopsAtEndOfText() {
        var decoder = CohereGreedyDecoder(endOfTextID: 2)

        XCTAssertEqual(pick(&decoder, [0, 5, 1, 3]), 1)
        XCTAssertEqual(pick(&decoder, [9]), 0)
        XCTAssertNil(pick(&decoder, [-1, -3, -0.5]), "argmax is the end-of-text id")
    }

    func testGreedyDecoderStopsAfterTooManyRepeats() {
        var decoder = CohereGreedyDecoder(endOfTextID: 99)
        decoder.maxConsecutiveRepeats = 3
        let same: [Float] = [0, 10, 0]

        XCTAssertEqual(pick(&decoder, same), 1)
        XCTAssertEqual(pick(&decoder, same), 1)
        XCTAssertEqual(pick(&decoder, same), 1)
        XCTAssertNil(pick(&decoder, same))
    }

    func testGreedyDecoderRepeatCountResetsOnDifferentToken() {
        var decoder = CohereGreedyDecoder(endOfTextID: 99)
        decoder.maxConsecutiveRepeats = 2

        XCTAssertEqual(pick(&decoder, [0, 10, 0]), 1)
        XCTAssertEqual(pick(&decoder, [0, 10, 0]), 1)
        XCTAssertEqual(pick(&decoder, [10, 0, 0]), 0)
        XCTAssertEqual(pick(&decoder, [0, 10, 0]), 1)
        XCTAssertEqual(pick(&decoder, [0, 10, 0]), 1)
        XCTAssertNil(pick(&decoder, [0, 10, 0]))
    }

    // MARK: - Chunker

    func testChunkerTakesAtMostThirtyFiveSecondsPerCall() {
        XCTAssertEqual(CohereTranscribe.chunker.maxChunkSamples, 35 * CohereTranscribe.sampleRate)
    }
}
