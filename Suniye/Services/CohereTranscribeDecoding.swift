import Foundation

/// Model-free half of the Cohere Transcribe engine: vocabulary, decoder prompt,
/// long-audio chunking, greedy token selection, and text assembly. Mirrors the
/// `transformers` `cohere_asr` processor so output matches the reference pipeline.
enum CohereTranscribe {
    static let sampleRate = 16_000
    static let supportedLanguages: Set<String> = [
        "ar", "de", "el", "en", "es", "fr", "it", "ja", "ko", "nl", "pl", "pt", "vi", "zh"
    ]
    private static let noSpaceLanguages: Set<String> = ["ja", "zh"]

    /// Picks the prompt language: an explicit supported hint wins, then the
    /// system language, then English. The model has no language detection.
    static func resolveLanguage(hint: String, locale: Locale = .current) -> String {
        let trimmed = hint.trimmingCharacters(in: .whitespaces)
        if supportedLanguages.contains(trimmed) {
            return trimmed
        }
        if let code = locale.language.languageCode?.identifier, supportedLanguages.contains(code) {
            return code
        }
        return "en"
    }

    /// Joins per-chunk transcripts the way the reference processor does: drop
    /// empty chunks, single space between chunks, no separator for ja/zh.
    static func joinChunkTexts(_ texts: [String], language: String) -> String {
        let separator = noSpaceLanguages.contains(language) ? "" : " "
        return texts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: separator)
    }
}

/// `tokens.txt`: one `piece id` per line, SentencePiece pieces with `▁` word
/// boundaries and `<0xNN>` byte fallbacks.
struct CohereVocabulary {
    struct ParseError: LocalizedError {
        let reason: String

        var errorDescription: String? {
            "Invalid Cohere vocabulary: \(reason)"
        }
    }

    let pieces: [String]
    let endOfTextID: Int64
    private let ids: [String: Int64]

    private static let endOfText = "<|endoftext|>"
    private static let wordBoundary: Character = "\u{2581}"

    init(contentsOf path: String) throws {
        try self.init(text: String(contentsOfFile: path, encoding: .utf8))
    }

    init(text: String) throws {
        var entries: [(String, Int)] = []
        var maxID = -1
        for line in text.split(whereSeparator: \.isNewline) {
            guard let space = line.lastIndex(of: " "), let id = Int(line[line.index(after: space)...]), id >= 0 else {
                continue
            }
            entries.append((String(line[..<space]), id))
            maxID = max(maxID, id)
        }
        guard maxID >= 0 else {
            throw ParseError(reason: "no `piece id` lines")
        }

        var pieces = [String](repeating: "", count: maxID + 1)
        var ids: [String: Int64] = [:]
        for (piece, id) in entries {
            pieces[id] = piece
            ids[piece] = Int64(id)
        }
        guard let endOfTextID = ids[Self.endOfText] else {
            throw ParseError(reason: "missing \(Self.endOfText)")
        }

        self.pieces = pieces
        self.ids = ids
        self.endOfTextID = endOfTextID
    }

    /// Decoder prompt for plain punctuated transcription (no ITN, timestamps,
    /// or diarization); the language token appears twice: source, then target.
    func promptIDs(language: String) throws -> [Int64] {
        let tokens = [
            "<|startofcontext|>",
            "<|startoftranscript|>",
            "<|emo:undefined|>",
            "<|\(language)|>",
            "<|\(language)|>",
            "<|pnc|>",
            "<|noitn|>",
            "<|notimestamp|>",
            "<|nodiarize|>"
        ]
        return try tokens.map { token in
            guard let id = ids[token] else {
                throw ParseError(reason: "missing prompt token \(token)")
            }
            return id
        }
    }

    /// Turns generated token IDs into text: special/control tokens are dropped,
    /// byte-fallback tokens are reassembled into UTF-8, `▁` becomes a space.
    func text(for tokenIDs: [Int64]) -> String {
        var bytes: [UInt8] = []
        for id in tokenIDs {
            guard id >= 0, id < pieces.count else {
                continue
            }
            let piece = pieces[Int(id)]
            if piece.hasPrefix("<|") || piece == "<unk>" || piece == "<pad>" || piece.isEmpty {
                continue
            }
            if let byte = Self.byteFallback(piece) {
                bytes.append(byte)
                continue
            }
            for scalar in piece.unicodeScalars {
                if Character(scalar) == Self.wordBoundary {
                    bytes.append(UInt8(ascii: " "))
                } else {
                    bytes.append(contentsOf: Array(String(scalar).utf8))
                }
            }
        }
        return String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func byteFallback(_ piece: String) -> UInt8? {
        guard piece.count == 6, piece.hasPrefix("<0x"), piece.hasSuffix(">") else {
            return nil
        }
        let hex = piece.dropFirst(3).dropLast()
        return UInt8(hex, radix: 16)
    }
}

/// Splits audio the encoder cannot take in one call (≤ 35 s) into chunks cut
/// at the quietest 100 ms inside the last 5 s before each boundary, matching
/// the reference feature extractor. Chunks do not overlap.
enum CohereAudioChunker {
    static let maxChunkSamples = 35 * CohereTranscribe.sampleRate
    static let boundarySearchSamples = 5 * CohereTranscribe.sampleRate
    static let energyWindowSamples = 1_600

    static func split(sampleCount: Int, energy: (Range<Int>) -> Float) -> [Range<Int>] {
        guard sampleCount > maxChunkSamples else {
            return sampleCount > 0 ? [0 ..< sampleCount] : []
        }

        var chunks: [Range<Int>] = []
        var start = 0
        while start < sampleCount {
            if start + maxChunkSamples >= sampleCount {
                chunks.append(start ..< sampleCount)
                break
            }
            let boundary = start + maxChunkSamples
            let end = quietestPoint(in: boundary - boundarySearchSamples ..< boundary, energy: energy)
            chunks.append(start ..< end)
            start = end
        }
        return chunks
    }

    static func split(_ samples: [Float]) -> [Range<Int>] {
        split(sampleCount: samples.count) { window in
            var sum: Float = 0
            for sample in samples[window] {
                sum += sample * sample
            }
            return (sum / Float(window.count)).squareRoot()
        }
    }

    private static func quietestPoint(in range: Range<Int>, energy: (Range<Int>) -> Float) -> Int {
        var quietest = range.lowerBound
        var minimum = Float.infinity
        for offset in stride(from: 0, to: range.count - energyWindowSamples, by: energyWindowSamples) {
            let window = (range.lowerBound + offset) ..< (range.lowerBound + offset + energyWindowSamples)
            let value = energy(window)
            if value < minimum {
                minimum = value
                quietest = window.lowerBound
            }
        }
        return quietest
    }
}

/// Argmax token selection with the two stop conditions: end-of-text, or the
/// same token repeating past `maxConsecutiveRepeats` (a degenerate loop the
/// model can fall into on noise; cheaper to cut than to run to the cap).
struct CohereGreedyDecoder {
    let endOfTextID: Int64
    var maxConsecutiveRepeats = 8
    private var lastToken: Int64 = -1
    private var consecutive = 0

    init(endOfTextID: Int64) {
        self.endOfTextID = endOfTextID
    }

    /// Returns the next token, or `nil` when decoding should stop.
    mutating func next(logits: UnsafeBufferPointer<Float>) -> Int64? {
        var best = 0
        var bestValue = -Float.infinity
        for (index, value) in logits.enumerated() where value > bestValue {
            best = index
            bestValue = value
        }
        let token = Int64(best)
        if token == endOfTextID {
            return nil
        }
        if token == lastToken {
            consecutive += 1
            if consecutive > maxConsecutiveRepeats {
                return nil
            }
        } else {
            consecutive = 1
            lastToken = token
        }
        return token
    }
}
