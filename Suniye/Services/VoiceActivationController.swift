import Foundation

/// Owns the always-listening pipeline: listen tap -> wake word -> turn capture
/// -> endpointing -> transcription -> Computer Use submission. State legality
/// lives in `VoiceActivationStateMachine`; this type performs the effects.
///
/// Threading: frames arrive on the audio service's internal queue and are
/// processed on `pipelineQueue` (resample, wake decode, VAD, turn buffer).
/// State-machine events and all callbacks run on the main actor.
@MainActor
final class VoiceActivationController {
    struct Configuration {
        /// UX plan: the captured transcript flashes briefly before submission.
        var transcriptFlashSeconds: TimeInterval = 1.2
        /// UX plan: follow-up window length (experimental setting).
        var followUpWindowSeconds: TimeInterval = 6
        /// UX plan privacy copy: the rolling turn buffer holds at most 35 s.
        var maximumTurnBufferSeconds: TimeInterval = 35
    }

    private(set) var state: VoiceActivationState = .off {
        didSet {
            if oldValue != state {
                onStateChange?(state)
            }
        }
    }

    var onStateChange: ((VoiceActivationState) -> Void)?
    /// Fires with the transcript during the pre-submission flash.
    var onTranscriptFlash: ((String) -> Void)?
    var onSubmissionOutcome: ((ComputerUseVoiceTaskSubmission) -> Void)?

    private var machine: VoiceActivationStateMachine
    private let configuration: Configuration
    private let audioCaptureService: AudioCaptureServiceProtocol
    private let transcriptionService: TranscriptionServiceProtocol
    private let submitVoiceTask: @MainActor (String) -> ComputerUseVoiceTaskSubmission
    private let isRunActive: @MainActor () -> Bool
    private let playWakeCue: @MainActor () -> Void
    private let preferredInputDeviceID: @MainActor () -> String?
    private let echoCancellationEnabled: @MainActor () -> Bool
    private let makeWakeDetector: () throws -> WakeWordDetecting
    private let makeSpeechDetector: () throws -> SpeechActivityDetecting

    private let pipelineQueue = DispatchQueue(label: "dev.suniye.voice.activation", qos: .userInitiated)
    private let pipeline = Pipeline()
    private(set) var tapSessionID: UUID?
    private var followUpExpiryTask: Task<Void, Never>?
    private var turnTask: Task<Void, Never>?

    init(
        audioCaptureService: AudioCaptureServiceProtocol,
        transcriptionService: TranscriptionServiceProtocol,
        submitVoiceTask: @escaping @MainActor (String) -> ComputerUseVoiceTaskSubmission,
        isRunActive: @escaping @MainActor () -> Bool,
        playWakeCue: @escaping @MainActor () -> Void,
        preferredInputDeviceID: @escaping @MainActor () -> String?,
        echoCancellationEnabled: @escaping @MainActor () -> Bool,
        makeWakeDetector: @escaping () throws -> WakeWordDetecting = { try SherpaWakeWordDetector() },
        makeSpeechDetector: @escaping () throws -> SpeechActivityDetecting = { try SileroSpeechActivityDetector() },
        configuration: Configuration = Configuration(),
        followUpWindowEnabled: Bool = false
    ) {
        self.audioCaptureService = audioCaptureService
        self.transcriptionService = transcriptionService
        self.submitVoiceTask = submitVoiceTask
        self.isRunActive = isRunActive
        self.playWakeCue = playWakeCue
        self.preferredInputDeviceID = preferredInputDeviceID
        self.echoCancellationEnabled = echoCancellationEnabled
        self.makeWakeDetector = makeWakeDetector
        self.makeSpeechDetector = makeSpeechDetector
        self.configuration = configuration
        machine = VoiceActivationStateMachine(
            configuration: .init(followUpWindowEnabled: followUpWindowEnabled)
        )
    }

    func setFollowUpWindowEnabled(_ enabled: Bool) {
        machine.configuration.followUpWindowEnabled = enabled
    }

    // MARK: Lifecycle

    func setEnabled(_ enabled: Bool) async {
        if enabled {
            dispatch(.enabled)
            await startTap()
        } else {
            dispatch(.disabled)
            await stopTap()
        }
    }

    /// A hold-to-talk capture is about to start; the tap yields (UX rule:
    /// never two microphone captures).
    func suspendForCaptureSession() async {
        guard state != .off else {
            return
        }
        dispatch(.tapSuspended)
        await stopTap()
    }

    func resumeAfterCaptureSession() async {
        guard state == .suspended else {
            return
        }
        await startTap()
        if tapSessionID != nil {
            dispatch(.tapRestored)
        }
    }

    func handleSystemSleep() async {
        guard state != .off else {
            return
        }
        dispatch(.systemSlept)
        await stopTap()
    }

    func handleSystemWake() async {
        guard state == .suspended else {
            return
        }
        await startTap()
        dispatch(.systemWoke(tapRestored: tapSessionID != nil))
    }

    /// Escape or the indicator's cancel control while listening.
    func cancelListening() {
        dispatch(.cancelRequested)
    }

    /// Coordinator phase changes drive the follow-up window (UX plan: the
    /// window opens only after Done, never after Stopped or a failure).
    func handleRunPhase(_ phase: ComputerUseCoordinatorPhase) {
        switch phase {
        case .completed:
            dispatch(.runCompleted(speechWillPlay: false))
        case .cancelled, .failed:
            dispatch(.runStoppedOrFailed)
        case .idle, .checkingPermissions, .requestingPermission, .ready, .running:
            break
        }
    }

    func ownsTapSession(_ sessionID: UUID) -> Bool {
        tapSessionID == sessionID
    }

    // MARK: Tap

    private func startTap() async {
        guard tapSessionID == nil else {
            return
        }
        do {
            try pipeline.prepare(
                wake: makeWakeDetector,
                speech: makeSpeechDetector,
                endpointer: VoiceTurnEndpointer(),
                maximumTurnBufferSeconds: configuration.maximumTurnBufferSeconds
            )
        } catch {
            AppLogger.shared.log(.error, "voice activation detectors unavailable: \(error)")
            dispatch(.tapSuspended)
            return
        }
        let sessionID = UUID()
        do {
            _ = try await audioCaptureService.startListenTap(
                sessionID: sessionID,
                preferredInputDeviceID: preferredInputDeviceID(),
                echoCancellationEnabled: echoCancellationEnabled()
            ) { [weak self] samples, sampleRate in
                self?.ingest(samples: samples, sampleRate: sampleRate)
            }
            tapSessionID = sessionID
        } catch {
            AppLogger.shared.log(.error, "voice activation tap start failed: \(error)")
            dispatch(.tapSuspended)
        }
    }

    private func stopTap() async {
        guard let sessionID = tapSessionID else {
            return
        }
        tapSessionID = nil
        await audioCaptureService.stopListenTap(sessionID: sessionID)
        pipelineQueue.async { [pipeline] in
            pipeline.resetAcousticState()
        }
    }

    // MARK: Frame pipeline

    nonisolated private func ingest(samples: [Float], sampleRate: Double) {
        pipelineQueue.async { [weak self, pipeline] in
            guard let self else {
                return
            }
            let events = pipeline.process(samples: samples, sampleRate: sampleRate)
            guard !events.isEmpty else {
                return
            }
            Task { @MainActor in
                for event in events {
                    switch event {
                    case .wakeDetected:
                        self.dispatch(.wakeDetected(runActive: self.isRunActive()))
                    case .speechBegan:
                        self.dispatch(.speechStarted)
                    case .speechEnded:
                        self.dispatch(.speechEnded)
                    case .noSpeechTimeout:
                        self.dispatch(.noSpeechTimeout)
                    }
                }
            }
        }
    }

    // MARK: State machine + effects

    private func dispatch(_ event: VoiceActivationEvent) {
        let effects = machine.handle(event)
        state = machine.state
        for effect in effects {
            perform(effect)
        }
    }

    private func perform(_ effect: VoiceActivationEffect) {
        switch effect {
        case .playWakeCue:
            playWakeCue()
        case .startTurnCapture:
            pipelineQueue.async { [pipeline] in
                pipeline.beginTurnCapture()
            }
        case .stopTurnCapture:
            pipelineQueue.async { [pipeline] in
                pipeline.endTurnCapture()
            }
        case .transcribeAndSubmit(let context):
            transcribeAndSubmit(context: context)
        case .armFollowUpWindow:
            pipelineQueue.async { [pipeline] in
                pipeline.beginTurnCapture()
            }
            followUpExpiryTask?.cancel()
            followUpExpiryTask = Task { [weak self] in
                try? await Task.sleep(
                    nanoseconds: UInt64((self?.configuration.followUpWindowSeconds ?? 6) * 1_000_000_000)
                )
                guard !Task.isCancelled else {
                    return
                }
                self?.dispatch(.followUpWindowExpired)
            }
        case .disarmFollowUpWindow:
            followUpExpiryTask?.cancel()
            followUpExpiryTask = nil
            pipelineQueue.async { [pipeline] in
                pipeline.endTurnCapture()
            }
        case .cancelFollowUpExpiryTimer:
            followUpExpiryTask?.cancel()
            followUpExpiryTask = nil
        }
    }

    private func transcribeAndSubmit(context: VoiceTurnContext) {
        turnTask = Task { [weak self] in
            guard let self else {
                return
            }
            let samples = await self.takeTurnSamples()
            var text = ""
            if !samples.isEmpty {
                do {
                    text = try await self.transcriptionService.transcribe(
                        samples: samples,
                        sampleRate: 16_000,
                        purpose: .final
                    ).trimmingCharacters(in: .whitespacesAndNewlines)
                } catch {
                    AppLogger.shared.log(.error, "voice activation transcription failed: \(error)")
                }
            }
            guard !text.isEmpty else {
                self.dispatch(.transcriptFailed)
                return
            }
            // UX plan: the transcript flashes so recognition mistakes are
            // visible before submission. Display-only in version 1.
            self.onTranscriptFlash?(text)
            let flash = self.configuration.transcriptFlashSeconds
            if flash > 0 {
                try? await Task.sleep(nanoseconds: UInt64(flash * 1_000_000_000))
            }
            let outcome = self.submitVoiceTask(text)
            self.onSubmissionOutcome?(outcome)
            switch outcome {
            case .started, .queued, .intervened:
                self.dispatch(.transcriptSubmitted)
            case .rejected:
                self.dispatch(.transcriptFailed)
            }
        }
    }

    private func takeTurnSamples() async -> [Float] {
        await withCheckedContinuation { continuation in
            pipelineQueue.async { [pipeline] in
                continuation.resume(returning: pipeline.takeTurnSamples())
            }
        }
    }
}

/// Compute-side state, confined to `pipelineQueue`.
private final class Pipeline: @unchecked Sendable {
    enum Event {
        case wakeDetected
        case speechBegan
        case speechEnded
        case noSpeechTimeout
    }

    private var wakeDetector: WakeWordDetecting?
    private var speechDetector: SpeechActivityDetecting?
    private var endpointer = VoiceTurnEndpointer()
    private var maximumTurnSamples = 16_000 * 35
    private var capturingTurn = false
    private var speechBeganEmitted = false
    private var turnSamples: [Float] = []
    private var processedSeconds: TimeInterval = 0
    private var lastDebugLoggedSecond = -1

    func prepare(
        wake: () throws -> WakeWordDetecting,
        speech: () throws -> SpeechActivityDetecting,
        endpointer: VoiceTurnEndpointer,
        maximumTurnBufferSeconds: TimeInterval
    ) throws {
        if wakeDetector == nil {
            wakeDetector = try wake()
        }
        if speechDetector == nil {
            speechDetector = try speech()
        }
        self.endpointer = endpointer
        maximumTurnSamples = Int(16_000 * maximumTurnBufferSeconds)
    }

    func beginTurnCapture() {
        capturingTurn = true
        speechBeganEmitted = false
        turnSamples.removeAll(keepingCapacity: true)
        endpointer.begin(at: processedSeconds)
    }

    func endTurnCapture() {
        capturingTurn = false
    }

    func takeTurnSamples() -> [Float] {
        let samples = turnSamples
        turnSamples = []
        capturingTurn = false
        return samples
    }

    func resetAcousticState() {
        wakeDetector?.reset()
        speechDetector?.reset()
        capturingTurn = false
        turnSamples = []
    }

    func process(samples: [Float], sampleRate: Double) -> [Event] {
        let resampled = AudioResampler.resample(samples, from: sampleRate, to: 16_000)
        guard !resampled.isEmpty else {
            return []
        }
        processedSeconds += Double(resampled.count) / 16_000
        if SherpaWakeWordDetector.debugTuning, Int(processedSeconds) > lastDebugLoggedSecond {
            lastDebugLoggedSecond = Int(processedSeconds)
            let rms = (resampled.reduce(Float(0)) { $0 + $1 * $1 } / Float(resampled.count)).squareRoot()
            AppLogger.shared.log(.info, "wake-debug audio t=\(Int(processedSeconds))s rate=\(sampleRate) rms=\(rms)")
        }
        var events: [Event] = []

        if capturingTurn {
            if turnSamples.count < maximumTurnSamples {
                turnSamples.append(contentsOf: resampled.prefix(maximumTurnSamples - turnSamples.count))
            }
            let isSpeech = speechDetector?.isSpeech(samples16k: resampled) ?? false
            switch endpointer.process(isSpeech: isSpeech, at: processedSeconds) {
            case .waiting:
                break
            case .speaking:
                if !speechBeganEmitted {
                    speechBeganEmitted = true
                    events.append(.speechBegan)
                }
            case .turnEnded, .maxTurnReached:
                capturingTurn = false
                events.append(.speechEnded)
            case .noSpeechTimeout:
                capturingTurn = false
                turnSamples = []
                events.append(.noSpeechTimeout)
            }
        } else if wakeDetector?.accept(samples: resampled, sampleRate: 16_000) == true {
            events.append(.wakeDetected)
        }
        return events
    }
}
