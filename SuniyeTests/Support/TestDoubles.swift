import AppKit
import Foundation
import SuniyeAnalytics
@testable import Suniye

/// Keeps the events the app tracks.
final class SpyAnalytics: Analytics, @unchecked Sendable {
    private(set) var trackedEvents: [AnalyticsEvent] = []

    func track(_ event: AnalyticsEvent) { trackedEvents.append(event) }
    func setEnabled(_ enabled: Bool) {}
    func flush() async {}
    func start() {}
    func stop() {}
    func recordSessionEnd(cleanExit: Bool) {}
    func endSession(cleanExit: Bool) async {}
}

/// A Keychain item in memory: no test reads or writes the login Keychain.
final class MemorySecretItem: SecretItem, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Data?

    var data: Data? {
        lock.withLock { stored }
    }

    func read() throws -> Data? {
        lock.withLock { stored }
    }

    func write(_ data: Data) throws {
        lock.withLock { stored = data }
    }

    func delete() throws {
        lock.withLock { stored = nil }
    }
}

/// Sparkle: it reports the update steps that a test gives it.
@MainActor
final class StubAppUpdateController: AppUpdateControllerProtocol {
    let isEnabled = true
    let canCheckForUpdates = true
    var automaticallyChecksForUpdates = false
    var updateChannel: UpdateChannel = .stable
    var onStateChange: (() -> Void)?
    var onEvent: ((AppUpdateEvent) -> Void)?
    private(set) var quietCheckCount = 0
    private(set) var windowCheckCount = 0
    private(set) var installUpdateAndRelaunchCallCount = 0

    func start() {}

    func checkForUpdates() {
        windowCheckCount += 1
    }

    func checkForUpdateInformation() -> Bool {
        quietCheckCount += 1
        return true
    }

    func installUpdateAndRelaunch() {
        installUpdateAndRelaunchCallCount += 1
    }

    func report(_ events: AppUpdateEvent...) {
        events.forEach { onEvent?($0) }
    }
}

/// A speech engine that hears what the test sets.
@MainActor
final class StubTranscriptionService: TranscriptionServiceProtocol {
    var transcribeResult: Result<String, Error> = .success("")
    private(set) var loadedConfigs: [RecognizerConfig] = []

    nonisolated init() {}

    func loadModel(config: RecognizerConfig) async throws {
        loadedConfigs.append(config)
    }

    func transcribe(
        samples: [Float],
        sampleRate: Int,
        purpose: TranscriptionPurpose,
        onProgress: @escaping @Sendable (TranscriptionProgress) -> Void
    ) async throws -> String {
        try transcribeResult.get()
    }

    func unloadModel() async {}
}

/// The microphone: it records what the test puts in `stopCaptureResult`,
/// a tenth of a second of sound unless the test sets other audio.
final class StubAudioCaptureService: AudioCaptureServiceProtocol {
    var onEvent: ((AudioCaptureEvent) -> Void)?
    var stopCaptureResult = CapturedAudio(samples: Array(repeating: 0.2, count: 4_800), sampleRate: 48_000)
    private(set) var startCaptureCallCount = 0
    private let route = AudioRouteSnapshot(
        preferredInputDeviceID: nil,
        effectiveInputDeviceID: "built-in",
        effectiveInputName: "MacBook Pro Microphone",
        inputTransport: .builtIn,
        outputTransport: .builtIn,
        inputSampleRate: 48_000,
        inputChannelCount: 1,
        requestedEchoCancellation: false,
        effectiveEchoCancellation: false,
        backend: .inputOnlyHAL,
        fallbackReason: nil,
        standIn: nil
    )

    func startCapture(sessionID: UUID, preferredInputDeviceID: String?, echoCancellationEnabled: Bool) async throws -> AudioCaptureSession {
        startCaptureCallCount += 1
        return AudioCaptureSession(id: sessionID, route: route)
    }

    func stopCapture(sessionID: UUID) async -> CapturedAudio {
        stopCaptureResult
    }

    func snapshotSamples(sessionID: UUID, maxDurationSeconds: Double) async -> AudioSampleSnapshot? {
        nil
    }

    func cancelCapture(sessionID: UUID, reason: AudioCaptureInterruption?) async {}

    func availableInputDevices() -> [AudioInputDevice] {
        []
    }

    func routeSnapshot(preferredInputDeviceID: String?, echoCancellationEnabled: Bool) throws -> AudioRouteSnapshot {
        route
    }

    func handleSystemSleep() async {}
    func handleSystemWake() {}
}

/// The global shortcut taps: a test presses and releases through the callbacks.
final class StubHotkeyService: HotkeyServiceProtocol {
    var onHotkeyDown: (() -> Void)?
    var onHotkeyUp: (() -> Void)?
    var onHotkeyChord: (() -> Void)?
    var onEditModeHotkeyDown: (() -> Void)?
    var onEditModeHotkeyUp: (() -> Void)?
    var onPasteLastTranscript: (() -> Void)?
    var onCancel: (() -> Void)?
    private(set) var isCancelShortcutEnabled = false

    func startMonitoring(
        configuration: HotkeyConfiguration,
        editModeConfiguration: HotkeyConfiguration?,
        pasteLastTranscriptConfiguration: HotkeyConfiguration
    ) {}

    func stopMonitoring() {}

    func setCancelShortcutEnabled(_ enabled: Bool) {
        isCancelShortcutEnabled = enabled
    }
}

final class SilentSpeaker: SoundFeedbackServiceProtocol {
    func play(_ event: SoundFeedbackEvent) {}
}

final class StubLaunchAtLoginService: LaunchAtLoginServiceProtocol {
    func currentStatus() -> LaunchAtLoginStatus {
        .disabled
    }

    func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginStatus {
        enabled ? .enabled : .disabled
    }
}

/// The toast window and the System Settings overlay show nothing in tests.
@MainActor
final class HiddenWindows: LearningToastPresenting, AccessibilityOnboardingPresenting {
    let isPresenting = false

    func showLearnedTerms(_ terms: [String], onUndo: @escaping () -> Void) {}
    func show(message: String, detail: String?, actionTitle: String?, action: (() -> Void)?) {}
    func present(onGranted: @escaping () -> Void, onEnded: @escaping (AccessibilityOnboardingEnd) -> Void) {}
    func dismiss() {}
}

struct FakeError: LocalizedError, Equatable {
    let message: String

    var errorDescription: String? {
        message
    }
}

/// Meetings in `root`, with no audio source and no call app, so an app in a
/// flow test never reads, recovers or records the real meetings.
@MainActor
func makeTestMeetingCoordinator(engine: TranscriptionServiceProtocol, root: URL, defaults: UserDefaults) -> MeetingCoordinator {
    MeetingCoordinator(
        store: MeetingStore(rootDirectory: root.appendingPathComponent("meetings", isDirectory: true)),
        templates: MeetingTemplateStore(fileURL: root.appendingPathComponent("templates.json")),
        settingsStore: MeetingSettingsStore(userDefaults: defaults),
        engine: engine,
        makeTranscriptEngine: { _ in engine },
        environment: MeetingEnvironment(
            canRecordCallAudio: false,
            makeSources: { _ in [:] },
            freeDiskBytes: { nil },
            callPlaysOnSpeakers: { false },
            makeMicrophoneUsers: { FakeMicrophoneUsers() },
            now: Date.init
        ),
        summaryAvailability: { _ in .unavailable },
        makeSummaryModel: { _ in nil },
        analytics: SpyAnalytics()
    )
}

/// The apps that hold the microphone, as Core Audio reports them.
@MainActor
final class FakeMicrophoneUsers: MicrophoneUserReading {
    var anyInputRunning = false
    var users: [MicrophoneUser] = []
    var onInputActivityChanged: (() -> Void)?

    func startListening() {}
    func stopListening() {}

    func read() -> [MicrophoneUser] {
        users
    }

    func showsMeeting(_ browser: MeetingCallApp) -> Bool {
        false
    }

    /// What a Core Audio listener does when an input device starts or stops.
    func inputActivityChanged() {
        onInputActivityChanged?()
    }
}

/// The meeting audio player, which plays nothing.
@MainActor
final class SilentMeetingAudioPlayer: MeetingAudioPlayer {
    let duration: TimeInterval
    private(set) var currentTime: TimeInterval = 0
    private(set) var isPlaying = false
    var onEnd: () -> Void = {}

    init(duration: TimeInterval) {
        self.duration = duration
    }

    func play(from time: TimeInterval) -> Bool {
        currentTime = time
        isPlaying = true
        return true
    }

    func pause() {
        isPlaying = false
    }
}
