import Foundation

/// Model-free half of the Qwen3-ASR engine: helper arguments, the request, and
/// the reply format. Mirrors the reference `qwen-asr` toolkit so output matches
/// its pipeline.
enum Qwen3ASR {
    static let sampleRate = 16_000
    static let contextSize = 4_096
    /// The audio encoder emits ~13 tokens per second, so 90 s of audio plus the
    /// longest plausible reply stays inside `contextSize`.
    static let chunker = AudioChunker(maxChunkSamples: 90 * sampleRate)
    /// The reference pads shorter clips with silence to this length.
    static let minimumSamples = sampleRate / 2
    /// Loading 2.5 GB of weights from a cold disk can take a while.
    static let startupTimeoutSeconds = 120.0
    static let warmupAudio = [Float](repeating: 0, count: sampleRate)

    private static let replyTag = "<asr_text>"
    private static let languagePrefix = "language "
    private static let noSpaceLanguages: Set<String> = ["Chinese", "Japanese", "Cantonese", "Thai"]

    /// One decoded chunk: the language the model detected (nil when it reports
    /// none) and the transcript.
    struct Reply: Equatable {
        let language: String?
        let text: String
    }

    static func serverArguments(modelPath: String, projectorPath: String) -> [String] {
        [
            "--model", modelPath,
            "--mmproj", projectorPath,
            "--ctx-size", "\(contextSize)",
            "--parallel", "1",
            // Each request carries different audio, so a saved prompt state is never
            // reused; by default every request would add ~110 KiB per token to RAM.
            "--cache-ram", "0",
        ]
    }

    /// Room for fast speech in any language (Hindi runs ~12 tokens per second),
    /// small enough that a decode stuck in a loop stops early.
    static func maxTokens(sampleCount: Int) -> Int {
        Int((Double(sampleCount) / Double(sampleRate) * 20).rounded(.up)) + 32
    }

    /// Generous for one chunk on the slowest Apple Silicon; a hung helper still fails.
    static func timeoutSeconds(sampleCount: Int) -> Double {
        30 + Double(sampleCount) / Double(sampleRate)
    }

    /// The reference prompt: an empty system turn, then a user turn holding only the audio.
    static func makePayload(samples: [Float], modelName: String) -> ChatCompletionPayload {
        var audio = samples
        if audio.count < minimumSamples {
            audio += [Float](repeating: 0, count: minimumSamples - audio.count)
        }
        return ChatCompletionPayload(
            model: modelName,
            messages: [
                ChatCompletionMessage(role: "system", content: ""),
                ChatCompletionMessage(role: "user", parts: [
                    .inputAudio(base64: wavData(samples: audio).base64EncodedString(), format: "wav")
                ])
            ],
            temperature: 0,
            maxTokens: maxTokens(sampleCount: audio.count),
            stream: false
        )
    }

    /// 16-bit PCM mono WAV at `sampleRate`.
    static func wavData(samples: [Float]) -> Data {
        let pcm = samples.map { Int16((max(-1, min(1, $0)) * Float(Int16.max)).rounded()).littleEndian }
        let dataBytes = UInt32(pcm.count * MemoryLayout<Int16>.size)
        var data = Data(capacity: 44 + Int(dataBytes))
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36) + dataBytes)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16)) // fmt chunk size
        append(UInt16(1)) // PCM
        append(UInt16(1)) // mono
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * MemoryLayout<Int16>.size)) // byte rate
        append(UInt16(MemoryLayout<Int16>.size)) // block align
        append(UInt16(16)) // bits per sample
        data.append(contentsOf: Array("data".utf8))
        append(dataBytes)
        pcm.withUnsafeBytes { data.append(contentsOf: $0) }
        return data
    }

    /// Parses `language <Name><asr_text><transcript>`. A reply without the tag is
    /// all transcript; `language None` means the model heard no speech.
    static func parseReply(_ raw: String) -> Reply {
        let reply = collapsingRepetitions(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let tag = reply.range(of: replyTag) else {
            return Reply(language: nil, text: reply)
        }
        let text = String(reply[tag.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let language = reply[..<tag.lowerBound]
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.lowercased().hasPrefix(languagePrefix) }
            .map { String($0.dropFirst(languagePrefix.count)).trimmingCharacters(in: .whitespaces) }
        guard let language, !language.isEmpty, language.lowercased() != "none" else {
            return Reply(language: nil, text: text)
        }
        return Reply(language: language.prefix(1).uppercased() + language.dropFirst().lowercased(), text: text)
    }

    /// Joins chunk transcripts with a space, or with nothing before a chunk in a
    /// language written without spaces. Empty chunks drop out.
    static func joinReplies(_ replies: [Reply]) -> String {
        var joined = ""
        for reply in replies where !reply.text.isEmpty {
            if !joined.isEmpty, !noSpaceLanguages.contains(reply.language ?? "") {
                joined += " "
            }
            joined += reply.text
        }
        return joined
    }

    /// The reference `detect_and_fix_repetitions`: a character repeated more than
    /// `threshold` times, or a pattern of up to 20 characters repeated `threshold`
    /// or more times, collapses to one occurrence. That is the shape of a decode
    /// stuck in a loop, never of speech.
    static func collapsingRepetitions(_ text: String, threshold: Int = 20) -> String {
        let characters = collapsingCharacterRuns(Array(text), threshold: threshold)
        return String(collapsingPatternRuns(characters[...], threshold: threshold))
    }

    private static func collapsingCharacterRuns(_ characters: [Character], threshold: Int) -> [Character] {
        var result: [Character] = []
        var index = 0
        while index < characters.count {
            var run = 1
            while index + run < characters.count, characters[index + run] == characters[index] {
                run += 1
            }
            if run > threshold {
                result.append(characters[index])
            } else {
                result.append(contentsOf: characters[index ..< index + run])
            }
            index += run
        }
        return result
    }

    private static func collapsingPatternRuns(
        _ characters: ArraySlice<Character>,
        threshold: Int,
        maxPatternLength: Int = 20
    ) -> [Character] {
        guard characters.count >= threshold * 2 else {
            return Array(characters)
        }

        var result: [Character] = []
        var index = characters.startIndex
        while index <= characters.endIndex - threshold * 2 {
            for length in 1 ... maxPatternLength {
                guard index + length * threshold <= characters.endIndex else {
                    break
                }
                let pattern = characters[index ..< index + length]
                let repeats = (1 ..< threshold).allSatisfy { repetition in
                    let start = index + repetition * length
                    return characters[start ..< start + length].elementsEqual(pattern)
                }
                guard repeats else {
                    continue
                }
                var end = index + threshold * length
                while end + length <= characters.endIndex, characters[end ..< end + length].elementsEqual(pattern) {
                    end += length
                }
                result.append(contentsOf: pattern)
                result.append(contentsOf: collapsingPatternRuns(characters[end...], threshold: threshold, maxPatternLength: maxPatternLength))
                return result
            }
            result.append(characters[index])
            index += 1
        }
        result.append(contentsOf: characters[index...])
        return result
    }
}
