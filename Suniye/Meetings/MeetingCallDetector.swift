import Foundation

/// Reads which call apps and browsers hold the microphone.
@MainActor
protocol MicrophoneUserReading: AnyObject {
    /// True while any input device runs, for any process.
    var anyInputRunning: Bool { get }
    /// Called when an input device starts or stops running.
    var onInputActivityChanged: (() -> Void)? { get set }
    func startListening()
    func stopListening()
    func read() -> [MicrophoneUser]
    /// True when a window title of the browser names a call service.
    func showsMeeting(_ browser: MeetingCallApp) -> Bool
}

/// Runs `MeetingCallWatch` on reads of the apps that hold the microphone.
///
/// It reads nothing while no input device runs and no app holds the
/// microphone, and nothing during a Suniye dictation. It reads when
/// an input device starts or stops, every second while an app's use of the
/// microphone waits for its delay, and every 5 s otherwise.
@MainActor
final class MeetingCallDetector {
    static let timingReadInterval: Duration = .seconds(1)
    static let readInterval: Duration = .seconds(5)

    var onEvent: ((MeetingCallWatch.Event) -> Void)?

    private let reader: MicrophoneUserReading
    private let uptime: () -> TimeInterval
    private var watch = MeetingCallWatch()
    private var loop: Task<Void, Never>?
    private var isRunning = false
    private var isDictating = false

    init(reader: MicrophoneUserReading, uptime: @escaping () -> TimeInterval) {
        self.reader = reader
        self.uptime = uptime
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        reader.onInputActivityChanged = { [weak self] in self?.readIfNeeded() }
        reader.startListening()
        readIfNeeded()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        reader.stopListening()
        reader.onInputActivityChanged = nil
        stopLoop()
        watch.forgetHolders()
    }

    func recordingStarted(call: MeetingCallApp?) {
        send(watch.recordingStarted(call: call))
    }

    func recordingStopped() {
        watch.recordingStopped()
    }

    /// A dictation's capture can hide a call app that takes the microphone
    /// while it records, so the detector reads again when it ends.
    func dictationChanged(active: Bool) {
        isDictating = active
        readIfNeeded()
    }

    private var shouldRead: Bool {
        isRunning && !isDictating && (reader.anyInputRunning || watch.isWatching)
    }

    private var interval: Duration {
        watch.isTiming ? Self.timingReadInterval : Self.readInterval
    }

    /// Reads now, and starts the reads that follow again from now.
    private func readIfNeeded() {
        stopLoop()
        guard shouldRead else { return }
        read()
        loop = Task { [weak self] in
            while let interval = self?.interval {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
                guard self.shouldRead else {
                    self.loop = nil
                    return
                }
                self.read()
            }
        }
    }

    private func stopLoop() {
        loop?.cancel()
        loop = nil
    }

    private func read() {
        send(watch.update(reader.read(), at: uptime(), showsMeeting: reader.showsMeeting))
    }

    private func send(_ events: [MeetingCallWatch.Event]) {
        for event in events {
            onEvent?(event)
        }
    }
}
