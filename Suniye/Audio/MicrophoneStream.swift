import AudioToolbox
import CoreAudio
import Foundation

/// Calls arrive on the stream's queue.
protocol MicrophoneStreamDelegate: AnyObject {
    /// Return false to stop reading the ring for now.
    func microphoneStream(_ stream: MicrophoneStream, didRead samples: UnsafeBufferPointer<Float>) -> Bool
    /// One drain ended: the ring is empty, or `didRead` returned false.
    func microphoneStreamDidDrain(_ stream: MicrophoneStream)
    func microphoneStream(_ stream: MicrophoneStream, willFallBack cause: MicrophoneStream.FallbackCause)
    /// A throw stops the backend that just started and fails that step.
    func microphoneStream(
        _ stream: MicrophoneStream,
        didStart plan: AudioCapturePlan,
        format: AudioCaptureFormat,
        fallback cause: MicrophoneStream.FallbackCause?
    ) throws
    func microphoneStreamConfigurationChanged(_ stream: MicrophoneStream)
    /// The standard engine gave no first frame (`nil`), or could not start
    /// after the primary backend gave none.
    func microphoneStream(_ stream: MicrophoneStream, deliveredNoAudio standardEngineError: Error?)
}

/// One open of one microphone on the owner's serial queue. The backend ladder:
/// the primary backend, then the standard engine when the primary cannot start
/// or delivers no first frame before the deadline. The stream does not reopen
/// on device changes; that policy belongs to the owner.
final class MicrophoneStream {
    enum FallbackCause {
        case startFailed(Error)
        case noFirstFrame
    }

    weak var delegate: MicrophoneStreamDelegate?
    private(set) var inputDeviceID: AudioObjectID
    private(set) var deviceRoute: AudioDeviceRoute
    private(set) var plan: AudioCapturePlan
    private(set) var hasReceivedFrame = false

    private let queue: DispatchQueue
    private let driverFactory: AudioCaptureDriverFactoryProtocol
    private let echoCancellationEnabled: Bool
    private let firstFrameDeadline: DispatchTimeInterval
    /// When set, the standard engine opens the device this returns, not the
    /// device of the first attempt: the meeting microphone resolves its choice
    /// again, as a microphone may have gone away during the first attempt.
    private let resolveFallbackDevice: (() throws -> CoreAudioRouteResolution)?
    private let ringDrain: AudioRingDrain
    private var driver: AudioCaptureDriver?
    private var watchesFirstFrame = true
    private var firstFrameDeadlineGeneration = 0

    init(
        queue: DispatchQueue,
        driverFactory: AudioCaptureDriverFactoryProtocol,
        resolution: CoreAudioRouteResolution,
        echoCancellationEnabled: Bool,
        firstFrameDeadline: DispatchTimeInterval,
        resolveFallbackDevice: (() throws -> CoreAudioRouteResolution)? = nil
    ) throws {
        ringDrain = try AudioRingDrain(queue: queue)
        self.queue = queue
        self.driverFactory = driverFactory
        self.echoCancellationEnabled = echoCancellationEnabled
        self.firstFrameDeadline = firstFrameDeadline
        self.resolveFallbackDevice = resolveFallbackDevice
        inputDeviceID = resolution.inputDeviceID
        deviceRoute = resolution.route
        plan = AudioCapturePolicy.primaryPlan(for: resolution.route, echoCancellationEnabled: echoCancellationEnabled)
    }

    deinit {
        driver?.stop()
    }

    var droppedSampleCount: UInt64 {
        ringDrain.droppedSampleCount
    }

    /// Starts the primary backend, or the standard engine when the primary
    /// cannot start. The owner calls `watchForFirstFrame()` when its own start
    /// work is done.
    func start() throws {
        ringDrain.startTimer { [weak self] in self?.drain() }
        let primary = plan
        let started: AudioCaptureDriverStart
        do {
            started = try startDriver(primary)
        } catch {
            try fallBackToStandardEngine(because: .startFailed(error))
            return
        }
        try adopt(started, plan: primary, fallback: nil)
    }

    /// Starts the first-frame deadline of the backend that `start()` opened.
    func watchForFirstFrame() {
        armFirstFrameDeadline()
    }

    /// Starts the current backend again on the same ring. Until a first frame
    /// arrives, the ring is cleared and the deadline starts again.
    func restart() throws {
        stopDriver()
        if !hasReceivedFrame {
            ringDrain.reset()
        }
        try adopt(try startDriver(plan), plan: plan, fallback: nil)
        if !hasReceivedFrame {
            armFirstFrameDeadline()
        }
    }

    /// The ring keeps what the driver wrote; `drain()` still reads it.
    func stop() {
        stopDriver()
        ringDrain.stopTimer()
        watchesFirstFrame = false
    }

    /// A missing first frame no longer changes the backend or reports no audio.
    func stopWatchingFirstFrame() {
        watchesFirstFrame = false
    }

    func drain() {
        ringDrain.read { block in
            hasReceivedFrame = true
            return delegate?.microphoneStream(self, didRead: block) ?? false
        }
        delegate?.microphoneStreamDidDrain(self)
    }

    private func fallBackToStandardEngine(because cause: FallbackCause) throws {
        delegate?.microphoneStream(self, willFallBack: cause)
        stopDriver()
        ringDrain.reset()
        if let resolveFallbackDevice {
            let resolution = try resolveFallbackDevice()
            inputDeviceID = resolution.inputDeviceID
            deviceRoute = resolution.route
        }
        let fallback = AudioCapturePolicy.fallbackPlan(
            for: deviceRoute,
            echoCancellationEnabled: echoCancellationEnabled,
            reason: .backendStartFailed
        )
        try adopt(try startDriver(fallback), plan: fallback, fallback: cause)
    }

    private func startDriver(_ plan: AudioCapturePlan) throws -> AudioCaptureDriverStart {
        try driverFactory.startDriver(for: plan, inputDeviceID: inputDeviceID, ring: ringDrain.ring) { [weak self] in
            self?.queue.async {
                guard let self, self.driver != nil else { return }
                self.delegate?.microphoneStreamConfigurationChanged(self)
            }
        }
    }

    private func adopt(_ started: AudioCaptureDriverStart, plan: AudioCapturePlan, fallback cause: FallbackCause?) throws {
        driver = started.driver
        self.plan = plan
        do {
            try delegate?.microphoneStream(self, didStart: plan, format: started.format, fallback: cause)
        } catch {
            stopDriver()
            throw error
        }
    }

    private func stopDriver() {
        driver?.stop()
        driver = nil
    }

    /// A restart arms the deadline again; the generation keeps a deadline from
    /// before the restart from firing against the new driver.
    private func armFirstFrameDeadline() {
        guard watchesFirstFrame else { return }
        firstFrameDeadlineGeneration += 1
        let generation = firstFrameDeadlineGeneration
        queue.asyncAfter(deadline: .now() + firstFrameDeadline) { [weak self] in
            guard let self,
                  self.driver != nil,
                  self.watchesFirstFrame,
                  !self.hasReceivedFrame,
                  self.firstFrameDeadlineGeneration == generation else {
                return
            }
            self.firstFrameDeadlinePassed()
        }
    }

    private func firstFrameDeadlinePassed() {
        guard plan.backend != .standardEngine else {
            delegate?.microphoneStream(self, deliveredNoAudio: nil)
            return
        }
        do {
            try fallBackToStandardEngine(because: .noFirstFrame)
            armFirstFrameDeadline()
        } catch {
            delegate?.microphoneStream(self, deliveredNoAudio: error)
        }
    }
}
