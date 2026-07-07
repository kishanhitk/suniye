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

/// Manages the on-device model asset for Apple's `SpeechTranscriber`: presence checks,
/// install-with-progress, and locale reservation.
///
/// Kept separate from the transcription actor so `ModelManager` can drive a real
/// download-progress UI for the first-run asset fetch. The OS shares the asset across
/// apps, so most users never download anything; when they do, an unreserved asset can be
/// reclaimed by the system, so we reserve it to avoid a surprise re-download later.
@available(macOS 26, *)
enum AppleSpeechAssetInstaller {
    static func resolveSupportedLocale(_ requested: Locale = Locale.current) async -> Locale? {
        await SpeechTranscriber.supportedLocale(equivalentTo: requested)
    }

    static func isInstalled(_ requested: Locale = Locale.current) async -> Bool {
        guard let supported = await resolveSupportedLocale(requested) else { return false }
        let target = supported.identifier(.bcp47)
        return await SpeechTranscriber.installedLocales.contains { $0.identifier(.bcp47) == target }
    }

    /// Ensures the asset for the resolved locale is installed (reporting progress through
    /// `progress`), then reserves it. Returns the resolved supported locale.
    @discardableResult
    static func ensureInstalled(
        _ requested: Locale = Locale.current,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> Locale {
        guard let supported = await resolveSupportedLocale(requested) else {
            throw AppleSpeechTranscriptionService.ServiceError.unsupportedLocale(requested.identifier(.bcp47))
        }
        let target = supported.identifier(.bcp47)

        if await SpeechTranscriber.installedLocales.contains(where: { $0.identifier(.bcp47) == target }) {
            progress(1)
        } else {
            let transcriber = SpeechTranscriber(
                locale: supported,
                transcriptionOptions: [],
                reportingOptions: [],
                attributeOptions: []
            )
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                AppLogger.shared.log(.info, "apple speech installing asset locale=\(target)")
                // Forward the OS download progress to the caller's UI while the install runs.
                let poller = Task {
                    while !Task.isCancelled {
                        progress(request.progress.fractionCompleted)
                        try? await Task.sleep(nanoseconds: 200_000_000)
                    }
                }
                defer { poller.cancel() }
                try await request.downloadAndInstall()
            }
            progress(1)
        }

        await reserve(supported)
        return supported
    }

    /// Reserves the locale so its installed asset isn't reclaimed by the OS. Best-effort:
    /// a failure or a full reservation slate must not fail the caller (the asset is already
    /// installed and usable).
    private static func reserve(_ locale: Locale) async {
        let target = locale.identifier(.bcp47)
        let reserved = await AssetInventory.reservedLocales
        guard !reserved.contains(where: { $0.identifier(.bcp47) == target }) else {
            return
        }

        if reserved.count >= AssetInventory.maximumReservedLocales, let evictable = reserved.last {
            _ = await AssetInventory.release(reservedLocale: evictable)
        }

        do {
            _ = try await AssetInventory.reserve(locale: locale)
            AppLogger.shared.log(.info, "apple speech reserved locale=\(target)")
        } catch {
            AppLogger.shared.log(.warning, "apple speech reserve failed locale=\(target) error=\(error.localizedDescription)")
        }
    }
}

/// Transcription backed by Apple's on-device `SpeechAnalyzer` + `SpeechTranscriber`.
///
/// Runs in *batch* mode to satisfy `TranscriptionServiceProtocol`: the full captured
/// buffer is fed at once and only finalized results are collected (no volatile partials).
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
    private var analyzerFormat: AVAudioFormat?

    func loadModel(config: RecognizerConfig) async throws {
        // Ensure the asset (no progress here — the progress-reporting fetch happens earlier
        // via ModelManager.downloadAndExtractModel when the user sets the model up; this is
        // a safety net) and reserve it.
        let supported = try await AppleSpeechAssetInstaller.ensureInstalled(Self.resolvedLocale(from: config))
        locale = supported
        // Preheat the model and cache the analyzer format so the first dictation isn't cold.
        analyzerFormat = await Self.preheat(locale: supported)
        AppLogger.shared.log(.info, "apple speech loaded locale=\(supported.identifier(.bcp47))")
    }

    // `purpose` is ignored: this engine reports finalized results only (no
    // volatile partials), and `appleSpeech` opts out of the live preview, so it
    // is never asked for a `.partial` decode.
    func transcribe(samples: [Float], sampleRate: Int, purpose: TranscriptionPurpose) async throws -> String {
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

        // The analyzer format is stable for a given locale/options, so reuse the one cached
        // at load; only recompute if it wasn't captured. A nil format means the module can't
        // advertise one (not ready / unsupported), so fail cleanly rather than gamble.
        let format: AVAudioFormat
        if let cached = analyzerFormat {
            format = cached
        } else if let fresh = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) {
            format = fresh
        } else {
            throw ServiceError.bufferPreparationFailed
        }

        let inputBuffer = try Self.makeInputBuffer(
            samples: samples,
            sampleRate: max(8_000, sampleRate),
            targetFormat: format
        )

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        continuation.yield(AnalyzerInput(buffer: inputBuffer))
        continuation.finish()

        // Structured child task: collects finalized segments while the analyzer runs, and
        // is automatically cancelled/awaited if this function throws. With no volatile
        // results each segment is final and carries its own spacing, so plain concatenation
        // is correct — do not insert separators.
        async let transcription = transcriber.results.reduce(into: AttributedString()) { $0.append($1.text) }

        // Documented one-shot batch path: analyze the finite input, then flush finalized
        // results through the last processed sample.
        if let lastSample = try await analyzer.analyzeSequence(stream) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
        }

        let attributed = try await transcription
        let text = String(attributed.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        AppLogger.shared.log(.info, "apple speech transcribe done chars=\(text.count)")
        return text
    }

    func unloadModel() async {
        locale = nil
        analyzerFormat = nil
    }

    // MARK: - Helpers

    private static func resolvedLocale(from config: RecognizerConfig) -> Locale {
        let hint = config.language.trimmingCharacters(in: .whitespaces)
        return hint.isEmpty ? Locale.current : Locale(identifier: hint)
    }

    /// Warms the model and returns the analyzer's preferred format so the first real
    /// transcription doesn't pay cold-start latency. Best-effort.
    private static func preheat(locale: Locale) async -> AVAudioFormat? {
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        if let format {
            try? await analyzer.prepareToAnalyze(in: format)
        }
        return format
    }

    /// Builds an `AVAudioPCMBuffer` from mono float samples, converting to the analyzer's
    /// preferred format when it differs from our native 16 kHz mono float.
    private static func makeInputBuffer(
        samples: [Float],
        sampleRate: Int,
        targetFormat: AVAudioFormat
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
        if targetFormat == sourceFormat {
            return sourceBuffer
        }

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw ServiceError.bufferPreparationFailed
        }

        // Capacity = resampled length + a ~100 ms margin covering the resampler's filter
        // delay, so the whole input converts in a single pass without dropping tail frames.
        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let margin = AVAudioFrameCount(targetFormat.sampleRate / 10) + 1
        let targetCapacity = AVAudioFrameCount((Double(samples.count) * ratio).rounded(.up)) + margin
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

        // The margin above guarantees a single pass reaches .endOfStream; only a hard
        // converter error is a real failure.
        if status == .error || conversionError != nil {
            throw ServiceError.bufferPreparationFailed
        }
        return targetBuffer
    }
}
