import Foundation

enum ASRModelFamily: String, Codable {
    case nemoTransducer
    case moonshine
    case senseVoice
    case whisper
}

enum ASRModelID: String, Codable, CaseIterable, Identifiable {
    case parakeetV3
    case moonshineBase
    case senseVoice
    case whisperLargeV3

    var id: String {
        rawValue
    }
}

enum ASRModelBadge: String, Codable, Hashable {
    case recommended = "Recommended"
    case fast = "Fast"
    case balanced = "Balanced"
    case bestQuality = "Best quality"
    case multilingual = "Multilingual"
}

struct ASRModelRemoteFile: Equatable {
    let remoteURL: URL
    let destinationRelativePath: String
    let expectedSizeBytes: Int64?
}

enum ASRModelDownloadSource: Equatable {
    case archive(URL)
    case remoteFiles([ASRModelRemoteFile])
}

struct ASRModelFileManifest: Equatable {
    let tokens: String
    let encoder: String?
    let decoder: String?
    let joiner: String?
    let preprocessor: String?
    let uncachedDecoder: String?
    let cachedDecoder: String?
    let model: String?

    init(
        tokens: String,
        encoder: String? = nil,
        decoder: String? = nil,
        joiner: String? = nil,
        preprocessor: String? = nil,
        uncachedDecoder: String? = nil,
        cachedDecoder: String? = nil,
        model: String? = nil
    ) {
        self.tokens = tokens
        self.encoder = encoder
        self.decoder = decoder
        self.joiner = joiner
        self.preprocessor = preprocessor
        self.uncachedDecoder = uncachedDecoder
        self.cachedDecoder = cachedDecoder
        self.model = model
    }

    var requiredRelativePaths: [String] {
        [tokens, encoder, decoder, joiner, preprocessor, uncachedDecoder, cachedDecoder, model]
            .compactMap { $0 }
    }
}

struct ASRModelCatalogEntry: Identifiable, Equatable {
    let id: ASRModelID
    let displayName: String
    let description: String
    let family: ASRModelFamily
    let badges: [ASRModelBadge]
    let languageSummary: String
    let speedLabel: String
    let qualityLabel: String
    let estimatedSizeBytes: Int64
    let downloadSource: ASRModelDownloadSource
    let directoryName: String
    let recognizerModelType: String
    let languageHint: String
    let taskHint: String
    let useInverseTextNormalization: Bool
    let manifest: ASRModelFileManifest

    var estimatedSizeText: String {
        "~" + ByteCountFormatter.string(fromByteCount: estimatedSizeBytes, countStyle: .file)
    }
}

enum ASRModelCatalog {
    static let fallbackOrder: [ASRModelID] = [
        .parakeetV3,
        .senseVoice,
        .moonshineBase,
        .whisperLargeV3
    ]

    static let entries: [ASRModelCatalogEntry] = [
        ASRModelCatalogEntry(
            id: .parakeetV3,
            displayName: "Parakeet TDT 0.6B v3",
            description: "Balanced local dictation for everyday multilingual use.",
            family: .nemoTransducer,
            badges: [.recommended, .balanced],
            languageSummary: "25 European languages",
            speedLabel: "Balanced",
            qualityLabel: "Best",
            estimatedSizeBytes: 680_000_000,
            downloadSource: .archive(URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8.tar.bz2")!),
            directoryName: "sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8",
            recognizerModelType: "nemo_transducer",
            languageHint: "",
            taskHint: "transcribe",
            useInverseTextNormalization: false,
            manifest: ASRModelFileManifest(
                tokens: "tokens.txt",
                encoder: "encoder.int8.onnx",
                decoder: "decoder.int8.onnx",
                joiner: "joiner.int8.onnx"
            )
        ),
        ASRModelCatalogEntry(
            id: .moonshineBase,
            displayName: "Moonshine Base",
            description: "Fast English dictation with a smaller local footprint.",
            family: .moonshine,
            badges: [.fast],
            languageSummary: "English",
            speedLabel: "Fast",
            qualityLabel: "Good",
            estimatedSizeBytes: 285_000_000,
            downloadSource: .archive(URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-moonshine-base-en-int8.tar.bz2")!),
            directoryName: "sherpa-onnx-moonshine-base-en-int8",
            recognizerModelType: "",
            languageHint: "",
            taskHint: "transcribe",
            useInverseTextNormalization: false,
            manifest: ASRModelFileManifest(
                tokens: "tokens.txt",
                encoder: "encode.int8.onnx",
                preprocessor: "preprocess.onnx",
                uncachedDecoder: "uncached_decode.int8.onnx",
                cachedDecoder: "cached_decode.int8.onnx"
            )
        ),
        ASRModelCatalogEntry(
            id: .senseVoice,
            displayName: "SenseVoice",
            description: "Multilingual dictation tuned for Chinese, Japanese, Korean, English, and Cantonese.",
            family: .senseVoice,
            badges: [.multilingual],
            languageSummary: "Chinese, English, Japanese, Korean, Cantonese",
            speedLabel: "Balanced",
            qualityLabel: "Better",
            estimatedSizeBytes: 240_000_000,
            downloadSource: .archive(URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2")!),
            directoryName: "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17",
            recognizerModelType: "",
            languageHint: "auto",
            taskHint: "transcribe",
            useInverseTextNormalization: true,
            manifest: ASRModelFileManifest(
                tokens: "tokens.txt",
                model: "model.int8.onnx"
            )
        ),
        ASRModelCatalogEntry(
            id: .whisperLargeV3,
            displayName: "Whisper Large v3",
            description: "Broad multilingual coverage when you want the highest-quality fallback.",
            family: .whisper,
            badges: [.bestQuality],
            languageSummary: "Multilingual",
            speedLabel: "Slower",
            qualityLabel: "Best",
            estimatedSizeBytes: 1_700_000_000,
            downloadSource: .remoteFiles([
                ASRModelRemoteFile(
                    remoteURL: URL(string: "https://huggingface.co/csukuangfj/sherpa-onnx-whisper-large-v3/resolve/main/large-v3-encoder.int8.onnx?download=true")!,
                    destinationRelativePath: "large-v3-encoder.int8.onnx",
                    expectedSizeBytes: 732_000_000
                ),
                ASRModelRemoteFile(
                    remoteURL: URL(string: "https://huggingface.co/csukuangfj/sherpa-onnx-whisper-large-v3/resolve/main/large-v3-decoder.int8.onnx?download=true")!,
                    destinationRelativePath: "large-v3-decoder.int8.onnx",
                    expectedSizeBytes: 962_000_000
                ),
                ASRModelRemoteFile(
                    remoteURL: URL(string: "https://huggingface.co/csukuangfj/sherpa-onnx-whisper-large-v3/resolve/main/large-v3-tokens.txt?download=true")!,
                    destinationRelativePath: "large-v3-tokens.txt",
                    expectedSizeBytes: 798_000
                )
            ]),
            directoryName: "sherpa-onnx-whisper-large-v3",
            recognizerModelType: "",
            languageHint: "",
            taskHint: "transcribe",
            useInverseTextNormalization: false,
            manifest: ASRModelFileManifest(
                tokens: "large-v3-tokens.txt",
                encoder: "large-v3-encoder.int8.onnx",
                decoder: "large-v3-decoder.int8.onnx"
            )
        )
    ]

    static func entry(for id: ASRModelID) -> ASRModelCatalogEntry {
        guard let entry = entries.first(where: { $0.id == id }) else {
            preconditionFailure("Missing ASR model catalog entry for \(id.rawValue)")
        }
        return entry
    }
}
