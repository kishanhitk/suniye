import Foundation

enum ASRModelFamily: String, Codable {
    case nemoTransducer
    case moonshine
    case senseVoice
    case whisper
    // Apple's on-device SpeechAnalyzer/SpeechTranscriber stack (macOS 26+). Not a
    // sherpa-onnx model family — it is routed to a separate engine and its model
    // asset is managed by the OS rather than downloaded/extracted by us.
    case appleSpeech
    // Cohere Transcribe (Fast-Conformer encoder + autoregressive decoder). sherpa-onnx
    // cannot run this architecture, so it is routed to our own ONNX Runtime engine.
    case cohereTranscribe

    /// Whether repeated partial decodes for the live transcription preview are
    /// affordable. Whisper decodes a fixed 30s mel window regardless of input
    /// length, so every ~700ms partial tick would cost a full-window decode and
    /// delay the final decode behind an in-flight partial; the other families
    /// decode roughly proportional to the snapshot length. Apple's stack routes
    /// to a separate engine our partial scheduler doesn't drive, so it opts out.
    /// Cohere decodes at roughly real time, so a partial would never finish
    /// before the next tick.
    var supportsLivePreview: Bool {
        switch self {
        case .nemoTransducer, .moonshine, .senseVoice:
            return true
        case .whisper, .appleSpeech, .cohereTranscribe:
            return false
        }
    }
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
    case appleSpeech
    case cohereTranscribe

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
    /// Lowercase hex SHA-256 the downloaded file must match; `nil` skips the check.
    let sha256: String?

    init(remoteURL: URL, destinationRelativePath: String, expectedSizeBytes: Int64?, sha256: String? = nil) {
        self.remoteURL = remoteURL
        self.destinationRelativePath = destinationRelativePath
        self.expectedSizeBytes = expectedSizeBytes
        self.sha256 = sha256
    }
}

enum ASRModelDownloadSource: Equatable {
    case archive(URL)
    case remoteFiles([ASRModelRemoteFile])
    // The model asset is provided and managed by the operating system (e.g. Apple
    // SpeechTranscriber). There is nothing for us to download or extract.
    case systemManaged
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
    /// Files the graphs load themselves (ONNX external-data sidecars); never
    /// passed to a recognizer, but an install without them is broken.
    let sidecars: [String]

    init(
        tokens: String,
        encoder: String? = nil,
        decoder: String? = nil,
        joiner: String? = nil,
        preprocessor: String? = nil,
        uncachedDecoder: String? = nil,
        cachedDecoder: String? = nil,
        model: String? = nil,
        sidecars: [String] = []
    ) {
        self.tokens = tokens
        self.encoder = encoder
        self.decoder = decoder
        self.joiner = joiner
        self.preprocessor = preprocessor
        self.uncachedDecoder = uncachedDecoder
        self.cachedDecoder = cachedDecoder
        self.model = model
        self.sidecars = sidecars
    }

    var requiredRelativePaths: [String] {
        [tokens, encoder, decoder, joiner, preprocessor, uncachedDecoder, cachedDecoder, model]
            .compactMap { $0 } + sidecars
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

    /// Human-facing size label for the model library. System-managed models have no
    /// download footprint, so they show that they ship with the OS instead of a size.
    var sizeDisplayText: String {
        isSystemManaged ? "Built into macOS" : estimatedSizeText
    }

    /// System-managed entries (Apple SpeechTranscriber) are not downloaded, extracted,
    /// stored on disk, or deletable by us — the OS owns the model asset.
    var isSystemManaged: Bool {
        family == .appleSpeech
    }

    /// Whether this entry can be used on the current device. Sherpa models are always
    /// available; system-managed entries require the OS to support them.
    var isAvailableOnThisDevice: Bool {
        guard isSystemManaged else { return true }
        return AppleSpeechSupport.isAvailable
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
        .whisperTinyEnglish,
        .cohereTranscribe
    ]

    /// Catalog entries usable on the current device. System-managed entries (Apple
    /// SpeechTranscriber) are filtered out when the OS doesn't support them, which
    /// cascades through installed-model discovery, fallback, and the UI — so the
    /// Apple option is hidden entirely on macOS < 26.
    static var availableEntries: [ASRModelCatalogEntry] {
        entries.filter(\.isAvailableOnThisDevice)
    }

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
        ASRModelCatalogEntry(
            id: .appleSpeech,
            displayName: "Apple Speech",
            description: "Apple's built-in on-device transcription. Fast, private, and needs no download — the model ships with macOS 26.",
            family: .appleSpeech,
            badges: [.fast, .multilingual],
            languageSummary: "Follows your system language",
            speedLabel: "Fast",
            qualityLabel: "Better",
            estimatedSizeBytes: 0,
            downloadSource: .systemManaged,
            directoryName: "apple-speech",
            recognizerModelType: "",
            languageHint: "",
            taskHint: "transcribe",
            useInverseTextNormalization: false,
            // Never read: system-managed entries bypass the manifest-based install/config path.
            manifest: ASRModelFileManifest(tokens: "system-managed")
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
        ),
        ASRModelCatalogEntry(
            id: .cohereTranscribe,
            displayName: "Cohere Transcribe",
            description: "Cohere's 2-billion-parameter model: the most accurate option here, and the heaviest — about 4× slower than Parakeet and ~4 GB of memory while loaded. Choose it when accuracy matters more than speed.",
            family: .cohereTranscribe,
            badges: [.bestQuality, .multilingual],
            languageSummary: "14 languages, follows your system language",
            speedLabel: "Slower",
            qualityLabel: "Highest",
            estimatedSizeBytes: 2_889_280_010,
            downloadSource: .remoteFiles([
                cohereFile("tokens.txt", bytes: 223_821, sha256: "5e74bb2f65da624256b9d97fef197a282ce7d14811e2f7b1b97c25c89b93dfcb"),
                cohereFile("cohere-encoder.int8.onnx", bytes: 3_118_156, sha256: "58386cad715aa0ab30aaa118a479e43115380c114bd180178a0d110434991a54"),
                cohereFile("cohere-decoder.int8.onnx", bytes: 153_250_705, sha256: "8372ca6c8ff4db8b916ca3592f5c757a715e691b9edec751ba19b29fc854baf9"),
                cohereFile("cohere-encoder.int8.onnx.data", bytes: 2_732_687_328, sha256: "c115cacd07bef2c5d6bbfa800bb38e6f025ecbfbd220b81b711f0eef8cc28578")
            ]),
            directoryName: "cohere-transcribe-03-2026-onnx-int8",
            recognizerModelType: "",
            languageHint: "",
            taskHint: "transcribe",
            useInverseTextNormalization: false,
            manifest: ASRModelFileManifest(
                tokens: "tokens.txt",
                encoder: "cohere-encoder.int8.onnx",
                decoder: "cohere-decoder.int8.onnx",
                sidecars: ["cohere-encoder.int8.onnx.data"]
            )
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

    /// Community INT8 ONNX export of CohereLabs/cohere-transcribe-03-2026, pinned to a
    /// commit so the files behind the hashes cannot move under us.
    private static func cohereFile(_ name: String, bytes: Int64, sha256: String) -> ASRModelRemoteFile {
        ASRModelRemoteFile(
            remoteURL: URL(string: "https://huggingface.co/tristanripke/cohere-transcribe-onnx-int8/resolve/9ecc3a5e64b132ab094bada232650e49e4340ad2/\(name)")!,
            destinationRelativePath: name,
            expectedSizeBytes: bytes,
            sha256: sha256
        )
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
