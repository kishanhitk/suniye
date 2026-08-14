import AVFoundation
import Foundation

/// Speaks agent responses at turn boundaries (UX plan: Done, Couldn't finish,
/// Needs input — never step statuses). Playback must be interruptible: a wake
/// hit, Escape, or a new turn stops it immediately.
@MainActor
protocol SpeechOutputServing: AnyObject {
    var isSpeaking: Bool { get }
    /// Fires after playback ends naturally (not on interruption). Drives the
    /// follow-up window's self-capture guard.
    var onPlaybackFinished: (() -> Void)? { get set }
    func speak(_ text: String) async
    func stopSpeaking()
}

/// Availability of the local speech helper (Apple Silicon + installed venv).
enum VoiceOutputAvailability: Equatable {
    case available
    case unsupportedHardware
    case helperNotInstalled
}

/// Locates the mlx-audio helper environment. Follows the llama-server
/// precedent: an env override for development, then the standard install
/// location created by `scripts/setup_voice_helper.sh`.
struct VoiceHelperRuntimeLocator {
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    static var isAppleSilicon: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    func availability() -> VoiceOutputAvailability {
        guard Self.isAppleSilicon else {
            return .unsupportedHardware
        }
        return pythonURL() == nil ? .helperNotInstalled : .available
    }

    /// The helper install root created by `scripts/setup_voice_helper.sh`.
    var helperDirectory: URL {
        applicationSupport.appendingPathComponent("Suniye/voice-helper")
    }

    /// The app's log directory (a sibling of the helper, not inside it).
    var logsDirectory: URL {
        applicationSupport.appendingPathComponent("Suniye/logs")
    }

    func pythonURL() -> URL? {
        if let override = ProcessInfo.processInfo.environment["SUNIYE_VOICE_HELPER_PYTHON"],
           !override.isEmpty {
            let url = URL(fileURLWithPath: override)
            if fileManager.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        let standard = helperDirectory.appendingPathComponent("venv/bin/python3")
        return fileManager.isExecutableFile(atPath: standard.path) ? standard : nil
    }

    private var applicationSupport: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }
}

/// Chatterbox Turbo through a local `mlx_audio.server` helper process
/// (OpenAI-compatible `/v1/audio/speech`). The helper starts lazily on the
/// first utterance and idles resident; RAM gating is the enablement gate in
/// Settings, not a per-utterance decision.
@MainActor
final class ChatterboxSpeechService: NSObject, SpeechOutputServing {
    static let modelID = "mlx-community/chatterbox-turbo-8bit"

    var isSpeaking: Bool { player != nil }
    var onPlaybackFinished: (() -> Void)?

    private let locator: VoiceHelperRuntimeLocator
    private let port: Int
    private var helperProcess: Process?
    private var player: AVAudioPlayer?
    private var speakTask: Task<Void, Never>?

    init(locator: VoiceHelperRuntimeLocator = VoiceHelperRuntimeLocator(), port: Int = 43_218) {
        self.locator = locator
        self.port = port
    }

    func speak(_ text: String) async {
        stopSpeaking()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        speakTask = Task { [weak self] in
            await self?.performSpeak(trimmed)
        }
        await speakTask?.value
    }

    func stopSpeaking() {
        speakTask?.cancel()
        speakTask = nil
        player?.stop()
        player = nil
    }

    func shutdownHelper() {
        stopSpeaking()
        helperProcess?.terminate()
        helperProcess = nil
    }

    private func performSpeak(_ text: String) async {
        do {
            try await ensureHelperRunning()
            var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/audio/speech")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            // A cold helper loads the model inside the first request (~20 s);
            // warm requests answer in about a second.
            request.timeoutInterval = 120
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": Self.modelID,
                "input": text,
                "response_format": "wav",
                "stream": false,
            ])
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty else {
                throw VoiceHelperError.speechRequestFailed
            }
            try Task.checkCancellation()
            try play(data)
        } catch is CancellationError {
            // Barge-in or a newer utterance; logged so a cancelled utterance
            // is distinguishable from one that never reached playback.
            AppLogger.shared.log(.info, "voice output cancelled before playback")
        } catch {
            // UX plan: speech is additive, never load-bearing. The visual
            // result is already on screen; skip speech for this turn.
            AppLogger.shared.log(.error, "voice output failed: \(error)")
            onPlaybackFinished?()
        }
    }

    private func play(_ data: Data) throws {
        let player = try AVAudioPlayer(data: data)
        player.delegate = self
        self.player = player
        guard player.play() else {
            self.player = nil
            throw VoiceHelperError.playbackStartFailed
        }
        AppLogger.shared.log(
            .info,
            "voice output playing bytes=\(data.count) duration=\(String(format: "%.1f", player.duration))s"
        )
    }

    private func ensureHelperRunning() async throws {
        // A running helper is never respawned: model loading blocks its event
        // loop, so an unresponsive-but-running helper means "busy", not
        // "dead". Respawning here binds the same port and silently dies.
        if helperProcess?.isRunning == true {
            return
        }
        // A helper from a previous app instance may still own the port; use it.
        if await helperResponds() {
            AppLogger.shared.log(.info, "voice helper reused on port=\(port)")
            return
        }
        guard let python = locator.pythonURL() else {
            throw VoiceHelperError.helperUnavailable
        }
        let process = Process()
        process.executableURL = python
        // The server mkdirs a RELATIVE 'logs' path at startup. An app-spawned
        // child inherits the app's working directory ("/", read-only) and
        // dies instantly, so give it a writable cwd and an explicit log dir.
        let helperLogsDir = locator.helperDirectory.appendingPathComponent("logs")
        try? FileManager.default.createDirectory(at: helperLogsDir, withIntermediateDirectories: true)
        process.currentDirectoryURL = locator.helperDirectory
        process.arguments = [
            "-m", "mlx_audio.server",
            "--host", "127.0.0.1",
            "--port", String(port),
            "--log-dir", helperLogsDir.path,
        ]
        let logURL = locator.logsDirectory.appendingPathComponent("voice-helper.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let logHandle = try? FileHandle(forWritingTo: logURL)
        process.standardOutput = logHandle ?? FileHandle.nullDevice
        process.standardError = logHandle ?? FileHandle.nullDevice
        try process.run()
        helperProcess = process
        AppLogger.shared.log(.info, "voice helper started port=\(port)")

        // Wait for the HTTP server to come up (imports + bind, a few seconds).
        // Model load happens inside the first request and is covered by the
        // request timeout, not this loop.
        for _ in 0..<60 {
            if await helperResponds() {
                return
            }
            guard process.isRunning else {
                throw VoiceHelperError.helperStartTimeout
            }
            try await Task.sleep(nanoseconds: 500_000_000)
            try Task.checkCancellation()
        }
        throw VoiceHelperError.helperStartTimeout
    }

    private func helperResponds() async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/docs") else {
            return false
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else {
            return false
        }
        return http.statusCode < 500
    }
}

extension ChatterboxSpeechService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else {
                return
            }
            self.player = nil
            AppLogger.shared.log(.info, "voice output playback finished success=\(flag)")
            self.onPlaybackFinished?()
        }
    }
}

enum VoiceHelperError: Error, Equatable {
    case helperUnavailable
    case helperStartTimeout
    case speechRequestFailed
    case playbackStartFailed
}
