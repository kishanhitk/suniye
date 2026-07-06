import AVFoundation
import Foundation
import Speech

/// OS-support gate for Apple's SpeechAnalyzer/SpeechTranscriber stack.
///
/// Safe to call on any macOS version: returns `false` below macOS 26 or on devices
/// where the transcriber isn't available (unsupported hardware/region). Used to hide
/// the Apple provider from the catalog when it can't be used.
enum AppleSpeechSupport {
    static var isAvailable: Bool {
        if #available(macOS 26, *) {
            return SpeechTranscriber.isAvailable
        }
        return false
    }
}

/// Transcription backed by Apple's on-device `SpeechAnalyzer` + `SpeechTranscriber`.
///
/// Runs in *batch* mode to satisfy `TranscriptionServiceProtocol`: the full captured
/// buffer is fed at once and only finalized results are collected (no volatile
/// partials). The model asset is owned by the OS; `loadModel` ensures it is installed
/// for the active locale, downloading on first use.
@available(macOS 26, *)
actor AppleSpeechTranscriptionService: TranscriptionServiceProtocol {
    enum ServiceError: LocalizedError {
        case notLoaded
        case emptyAudio
        case unsupportedLocale(String)
        case bufferPreparationFailed

        var errorDescription: String? {
            switch self {
            case .notLoaded:
                return "Apple Speech transcriber is not loaded"
            case .emptyAudio:
                return "No audio captured"
            case let .unsupportedLocale(identifier):
                return "Apple Speech does not support the language \(identifier)"
            case .bufferPreparationFailed:
                return "Failed to prepare audio for Apple Speech"
            }
        }
    }

    private var locale: Locale?

    func loadModel(config: RecognizerConfig) async throws {
        let requested = Self.resolvedLocale(from: config)
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: requested) else {
            throw ServiceError.unsupportedLocale(requested.identifier(.bcp47))
        }

        // Ensure the model asset for this locale is installed. No-op once present;
        // the OS shares the asset across apps, so most users never download anything.
        try await Self.ensureModelInstalled(for: supported)
        locale = supported
        AppLogger.shared.log(.info, "apple speech loaded locale=\(supported.identifier(.bcp47))")
    }

    func transcribe(samples: [Float], sampleRate: Int) async throws -> String {
        guard let locale else {
            throw ServiceError.notLoaded
        }
        guard !samples.isEmpty else {
            throw ServiceError.emptyAudio
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [], // finalized results only — no volatile partials
            attributeOptions: []
        )
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        let inputBuffer = try Self.makeInputBuffer(
            samples: samples,
            sampleRate: max(8_000, sampleRate),
            targetFormat: analyzerFormat
        )

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()

        // Collect finalized text concurrently with feeding audio. The results sequence
        // terminates once the analyzer finishes, ending this loop.
        let collector = Task {
            var text = AttributedString()
            for try await result in transcriber.results {
                text.append(result.text)
            }
            return String(text.characters)
        }

        do {
            try await analyzer.start(inputSequence: stream)
            continuation.yield(AnalyzerInput(buffer: inputBuffer))
            continuation.finish()
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            continuation.finish()
            collector.cancel()
            throw error
        }

        let text = try await collector.value.trimmingCharacters(in: .whitespacesAndNewlines)
        AppLogger.shared.log(.info, "apple speech transcribe done chars=\(text.count)")
        return text
    }

    func unloadModel() async {
        locale = nil
    }

    // MARK: - Helpers

    private static func resolvedLocale(from config: RecognizerConfig) -> Locale {
        let hint = config.language.trimmingCharacters(in: .whitespaces)
        return hint.isEmpty ? Locale.current : Locale(identifier: hint)
    }

    private static func ensureModelInstalled(for locale: Locale) async throws {
        let installed = await SpeechTranscriber.installedLocales
        let target = locale.identifier(.bcp47)
        if installed.contains(where: { $0.identifier(.bcp47) == target }) {
            return
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            AppLogger.shared.log(.info, "apple speech installing asset locale=\(target)")
            try await request.downloadAndInstall()
        }
    }

    /// Builds an `AVAudioPCMBuffer` from mono float samples, converting to the analyzer's
    /// preferred format when it differs from our native 16 kHz mono float.
    private static func makeInputBuffer(
        samples: [Float],
        sampleRate: Int,
        targetFormat: AVAudioFormat?
    ) throws -> AVAudioPCMBuffer {
        guard
            let sourceFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Double(sampleRate),
                channels: 1,
                interleaved: false
            ),
            let sourceBuffer = AVAudioPCMBuffer(
                pcmFormat: sourceFormat,
                frameCapacity: AVAudioFrameCount(samples.count)
            )
        else {
            throw ServiceError.bufferPreparationFailed
        }

        sourceBuffer.frameLength = AVAudioFrameCount(samples.count)
        if let channel = sourceBuffer.floatChannelData?[0] {
            samples.withUnsafeBufferPointer { pointer in
                if let base = pointer.baseAddress {
                    channel.update(from: base, count: samples.count)
                }
            }
        }

        // No conversion needed when the analyzer accepts our native format.
        guard let targetFormat, targetFormat != sourceFormat else {
            return sourceBuffer
        }

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw ServiceError.bufferPreparationFailed
        }

        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let targetCapacity = AVAudioFrameCount((Double(samples.count) * ratio).rounded(.up)) + 1
        guard let targetBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetCapacity) else {
            throw ServiceError.bufferPreparationFailed
        }

        var providedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: targetBuffer, error: &conversionError) { _, inputStatus in
            if providedInput {
                inputStatus.pointee = .endOfStream
                return nil
            }
            providedInput = true
            inputStatus.pointee = .haveData
            return sourceBuffer
        }

        if status == .error || conversionError != nil {
            throw ServiceError.bufferPreparationFailed
        }
        return targetBuffer
    }
}
