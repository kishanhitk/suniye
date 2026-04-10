import Foundation

enum ASRModelFamily: String, Codable {
    case nemoTransducer
    case moonshine
    case senseVoice
    case whisper
}

enum ASRModelID: String, Codable, CaseIterable, Identifiable {
    case parakeetV3
    case parakeetV2English
    case moonshineBase
    case senseVoice
    case whisperTinyEnglish
    case whisperBaseEnglish
    case whisperSmallEnglish
    case whisperLargeV3Turbo
    case whisperDistilLargeV3
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
        .parakeetV2English,
        .senseVoice,
        .moonshineBase,
        .whisperLargeV3Turbo,
        .whisperDistilLargeV3,
        .whisperLargeV3,
        .whisperSmallEnglish,
        .whisperBaseEnglish,
        .whisperTinyEnglish
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
            downloadSource: .archive(archiveURL("sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8.tar.bz2")),
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
            id: .parakeetV2English,
            displayName: "Parakeet TDT 0.6B v2",
            description: "Strong English-focused dictation with a smaller footprint than v3.",
            family: .nemoTransducer,
            badges: [.balanced],
            languageSummary: "English",
            speedLabel: "Balanced",
            qualityLabel: "Better",
            estimatedSizeBytes: 482_468_385,
            downloadSource: .archive(archiveURL("sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8.tar.bz2")),
            directoryName: "sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8",
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
            downloadSource: .archive(archiveURL("sherpa-onnx-moonshine-base-en-int8.tar.bz2")),
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
            downloadSource: .archive(archiveURL("sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2")),
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
        whisperEntry(
            id: .whisperTinyEnglish,
            displayName: "Whisper Tiny (English)",
            description: "The smallest Whisper option for quick local English dictation.",
            badges: [.fast],
            languageSummary: "English",
            speedLabel: "Fast",
            qualityLabel: "Basic",
            estimatedSizeBytes: 118_071_777,
            archiveAssetName: "sherpa-onnx-whisper-tiny.en.tar.bz2",
            directoryName: "sherpa-onnx-whisper-tiny.en",
            filePrefix: "tiny.en"
        ),
        whisperEntry(
            id: .whisperBaseEnglish,
            displayName: "Whisper Base (English)",
            description: "A lightweight English Whisper model with a little more headroom than Tiny.",
            badges: [.fast],
            languageSummary: "English",
            speedLabel: "Fast",
            qualityLabel: "Good",
            estimatedSizeBytes: 208_576_005,
            archiveAssetName: "sherpa-onnx-whisper-base.en.tar.bz2",
            directoryName: "sherpa-onnx-whisper-base.en",
            filePrefix: "base.en"
        ),
        whisperEntry(
            id: .whisperSmallEnglish,
            displayName: "Whisper Small (English)",
            description: "A more accurate English Whisper model for longer-form local dictation.",
            badges: [.balanced],
            languageSummary: "English",
            speedLabel: "Balanced",
            qualityLabel: "Better",
            estimatedSizeBytes: 635_693_775,
            archiveAssetName: "sherpa-onnx-whisper-small.en.tar.bz2",
            directoryName: "sherpa-onnx-whisper-small.en",
            filePrefix: "small.en"
        ),
        whisperEntry(
            id: .whisperLargeV3Turbo,
            displayName: "Whisper Large v3 Turbo",
            description: "A faster large Whisper model when you want strong multilingual quality with less wait.",
            badges: [.fast, .bestQuality],
            languageSummary: "Multilingual",
            speedLabel: "Fast",
            qualityLabel: "Best",
            estimatedSizeBytes: 563_790_207,
            archiveAssetName: "sherpa-onnx-whisper-turbo.tar.bz2",
            directoryName: "sherpa-onnx-whisper-turbo",
            filePrefix: "turbo"
        ),
        whisperEntry(
            id: .whisperDistilLargeV3,
            displayName: "Whisper Distil Large v3",
            description: "A distilled large Whisper model that stays accurate while reducing local load time.",
            badges: [.balanced],
            languageSummary: "Multilingual",
            speedLabel: "Balanced",
            qualityLabel: "Best",
            estimatedSizeBytes: 529_350_808,
            archiveAssetName: "sherpa-onnx-whisper-distil-large-v3.tar.bz2",
            directoryName: "sherpa-onnx-whisper-distil-large-v3",
            filePrefix: "distil-large-v3"
        ),
        whisperEntry(
            id: .whisperLargeV3,
            displayName: "Whisper Large v3",
            description: "Broad multilingual coverage when you want the highest-quality fallback.",
            badges: [.bestQuality],
            languageSummary: "Multilingual",
            speedLabel: "Slower",
            qualityLabel: "Best",
            estimatedSizeBytes: 1_700_000_000,
            archiveAssetName: "sherpa-onnx-whisper-large-v3.tar.bz2",
            directoryName: "sherpa-onnx-whisper-large-v3",
            filePrefix: "large-v3"
        )
    ]

    static func entry(for id: ASRModelID) -> ASRModelCatalogEntry {
        guard let entry = entries.first(where: { $0.id == id }) else {
            preconditionFailure("Missing ASR model catalog entry for \(id.rawValue)")
        }
        return entry
    }

    private static func archiveURL(_ assetName: String) -> URL {
        URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/\(assetName)")!
    }

    private static func whisperEntry(
        id: ASRModelID,
        displayName: String,
        description: String,
        badges: [ASRModelBadge],
        languageSummary: String,
        speedLabel: String,
        qualityLabel: String,
        estimatedSizeBytes: Int64,
        archiveAssetName: String,
        directoryName: String,
        filePrefix: String
    ) -> ASRModelCatalogEntry {
        ASRModelCatalogEntry(
            id: id,
            displayName: displayName,
            description: description,
            family: .whisper,
            badges: badges,
            languageSummary: languageSummary,
            speedLabel: speedLabel,
            qualityLabel: qualityLabel,
            estimatedSizeBytes: estimatedSizeBytes,
            downloadSource: .archive(archiveURL(archiveAssetName)),
            directoryName: directoryName,
            recognizerModelType: "",
            languageHint: "",
            taskHint: "transcribe",
            useInverseTextNormalization: false,
            manifest: ASRModelFileManifest(
                tokens: "\(filePrefix)-tokens.txt",
                encoder: "\(filePrefix)-encoder.int8.onnx",
                decoder: "\(filePrefix)-decoder.int8.onnx"
            )
        )
    }
}
