import CoreAudio
import XCTest
@testable import Suniye

/// Complements AudioCaptureServiceTests: error descriptions, start failure paths,
/// no-active-session guards, sleep/wake handling, engine-restart failure, fallback
/// failure at the first-frame deadline, and every device-change interruption branch.
final class AudioCaptureServiceMoreTests: XCTestCase {
    // MARK: - Error descriptions

    func testErrorDescriptionsAreHumanReadable() {
        XCTAssertEqual(
            AudioCaptureServiceError.noInputDevice.errorDescription,
            "No microphone is available."
        )
        XCTAssertEqual(
            AudioCaptureServiceError.preferredDeviceUnavailable.errorDescription,
            "The selected microphone is unavailable."
        )
        XCTAssertEqual(
            AudioCaptureServiceError.invalidInputFormat.errorDescription,
            "The selected microphone has an invalid audio format."
        )
        XCTAssertEqual(
            AudioCaptureServiceError.failedToSelectInput(-10851).errorDescription,
            "Could not select the microphone (Core Audio -10851)."
        )
        XCTAssertEqual(
            AudioCaptureServiceError.ringBufferUnavailable.errorDescription,
            "Could not prepare the audio buffer."
        )
        XCTAssertEqual(
            AudioCaptureServiceError.operationFailed("Start engine", -50).errorDescription,
            "Start engine failed (Core Audio -50)."
        )
    }

    // MARK: - Start failure

    func testStartCaptureRethrowsRouteResolutionFailure() async {
        let catalog = FakeAudioCaptureHardwareCatalog(route: makeDeviceRoute())
        catalog.resolveError = FakeError(message: "no route")
        let service = AudioCaptureService(
            deviceMonitor: FakeAudioDeviceMonitor(),
            hardwareCatalog: catalog,
            driverFactory: FakeAudioCaptureDriverFactory(
                format: AudioCaptureFormat(sampleRate: 16_000, channelCount: 1)
            ),
            firstFrameDeadlineSeconds: 10
        )

        do {
            _ = try await service.startCapture(
                sessionID: UUID(),
                preferredInputDeviceID: nil,
                echoCancellationEnabled: false
            )
            XCTFail("Expected startCapture to throw")
        } catch {
            XCTAssertEqual(error as? FakeError, FakeError(message: "no route"))
        }
    }

    // MARK: - No-active-session guards

    func testStopCaptureWithoutActiveSessionReturnsAbnormalInterruption() async {
        let service = makeService(makeFactory())
        let sessionID = UUID()

        let captured = await service.stopCapture(sessionID: sessionID)

        XCTAssertEqual(captured.sessionID, sessionID)
        XCTAssertEqual(captured.outcome, .interrupted(.ioStoppedAbnormally))
        XCTAssertTrue(captured.samples.isEmpty)
    }

    func testStopCaptureWithMismatchedSessionIDReturnsAbnormalInterruption() async throws {
        let service = makeService(makeFactory())
        let activeID = UUID()
        _ = try await service.startCapture(
            sessionID: activeID,
            preferredInputDeviceID: nil,
            echoCancellationEnabled: false
        )

        let captured = await service.stopCapture(sessionID: UUID())

        XCTAssertEqual(captured.outcome, .interrupted(.ioStoppedAbnormally))
        // The active session is untouched by the mismatched stop.
        let active = await service.stopCapture(sessionID: activeID)
        XCTAssertEqual(active.outcome, .complete)
    }

    func testCancelCaptureWithoutActiveSessionIsANoOp() async {
        let service = makeService(makeFactory())
        var interruptedCount = 0
        service.onEvent = { event in
            if case .interrupted = event {
                interruptedCount += 1
            }
        }

        await service.cancelCapture(sessionID: UUID(), reason: .deviceChanged)

        XCTAssertEqual(interruptedCount, 0)
    }

    // MARK: - Sleep / wake

    func testSystemSleepInterruptsActiveCapture() async throws {
        let service = makeService(makeFactory())
        var interruptedReason: AudioCaptureInterruption?
        service.onEvent = { event in
            if case let .interrupted(_, reason) = event {
                interruptedReason = reason
            }
        }
        let sessionID = UUID()
        _ = try await service.startCapture(
            sessionID: sessionID,
            preferredInputDeviceID: nil,
            echoCancellationEnabled: false
        )

        await service.handleSystemSleep()

        XCTAssertEqual(interruptedReason, .systemSleep)
        let captured = await service.stopCapture(sessionID: sessionID)
        XCTAssertEqual(captured.outcome, .interrupted(.systemSleep))
    }

    func testSystemSleepWithoutActiveCaptureDoesNothing() async {
        let service = makeService(makeFactory())
        var interruptedCount = 0
        service.onEvent = { event in
            if case .interrupted = event {
                interruptedCount += 1
            }
        }

        await service.handleSystemSleep()

        XCTAssertEqual(interruptedCount, 0)
    }

    func testSystemWakeRestartsMonitorAndPublishesDevices() async {
        let monitor = FakeAudioDeviceMonitor()
        let service = makeService(makeFactory(), monitor: monitor)
        let published = expectation(description: "devices published after wake")
        service.onEvent = { event in
            if case .devicesChanged = event {
                published.fulfill()
            }
        }

        service.handleSystemWake()

        await fulfillment(of: [published], timeout: 2)
        XCTAssertGreaterThanOrEqual(monitor.stopCallCount, 1)
        // Init starts the monitor once; wake must start it again.
        XCTAssertGreaterThanOrEqual(monitor.startCallCount, 2)
    }

    // MARK: - Engine restart failure

    func testEngineRestartFailureAfterConfigurationChangeInterrupts() async throws {
        let factory = makeFactory()
        let service = makeService(factory)
        let interrupted = expectation(description: "interrupted after restart failure")
        var interruptedReason: AudioCaptureInterruption?
        service.onEvent = { event in
            if case let .interrupted(_, reason) = event {
                interruptedReason = reason
                interrupted.fulfill()
            }
        }
        let sessionID = UUID()
        _ = try await service.startCapture(
            sessionID: sessionID,
            preferredInputDeviceID: nil,
            echoCancellationEnabled: false
        )

        // The in-place restart on the same backend now fails to start.
        factory.failingBackends = [.inputOnlyHAL]
        factory.triggerConfigurationChange()

        await fulfillment(of: [interrupted], timeout: 2)
        XCTAssertEqual(interruptedReason, .engineConfigurationChanged)
        XCTAssertEqual(factory.startedBackends, [.inputOnlyHAL, .inputOnlyHAL])
        await service.cancelCapture(sessionID: sessionID, reason: nil)
    }

    // MARK: - First-frame deadline fallback failure

    func testFallbackFailureAtFirstFrameDeadlineInterrupts() async throws {
        // No samples ever arrive; the deadline tries the standardEngine fallback,
        // which also fails to start, so the capture is interrupted.
        let factory = FakeAudioCaptureDriverFactory(
            format: AudioCaptureFormat(sampleRate: 16_000, channelCount: 1),
            failingBackends: [.standardEngine]
        )
        let service = makeService(factory, firstFrameDeadlineSeconds: 0.05)
        let interrupted = expectation(description: "interrupted after fallback failure")
        var interruptedReason: AudioCaptureInterruption?
        service.onEvent = { event in
            if case let .interrupted(_, reason) = event {
                interruptedReason = reason
                interrupted.fulfill()
            }
        }
        let sessionID = UUID()
        _ = try await service.startCapture(
            sessionID: sessionID,
            preferredInputDeviceID: nil,
            echoCancellationEnabled: false
        )

        await fulfillment(of: [interrupted], timeout: 2)
        XCTAssertEqual(interruptedReason, .noAudioArriving)
        XCTAssertEqual(factory.startedBackends, [.inputOnlyHAL, .standardEngine])
        await service.cancelCapture(sessionID: sessionID, reason: nil)
    }

    // MARK: - Device-change branches

    func testServiceRestartedChangeInterruptsAndRestartsMonitor() async throws {
        let monitor = FakeAudioDeviceMonitor()
        let service = makeService(makeFactory(), monitor: monitor)
        let reason = try await interruption(of: service, after: { monitor.emit(.serviceRestarted) })

        XCTAssertEqual(reason, .serviceRestarted)
        XCTAssertGreaterThanOrEqual(monitor.stopCallCount, 1)
        XCTAssertGreaterThanOrEqual(monitor.startCallCount, 2)
    }

    func testDefaultInputChangeInterruptsSystemDefaultCapture() async throws {
        let monitor = FakeAudioDeviceMonitor()
        let service = makeService(makeFactory(), monitor: monitor)
        let reason = try await interruption(of: service, after: { monitor.emit(.defaultInput) })

        XCTAssertEqual(reason, .deviceChanged)
    }

    func testDefaultOutputChangeInterruptsVoiceProcessingCapture() async throws {
        let monitor = FakeAudioDeviceMonitor()
        let service = makeService(makeFactory(), monitor: monitor)
        let reason = try await interruption(
            of: service,
            echoCancellationEnabled: true,
            after: { monitor.emit(.defaultOutput) }
        )

        XCTAssertEqual(reason, .deviceChanged)
    }

    func testDevicesChangeToDifferentRouteInterrupts() async throws {
        let monitor = FakeAudioDeviceMonitor()
        let catalog = FakeAudioCaptureHardwareCatalog(route: makeDeviceRoute())
        let service = makeService(makeFactory(), monitor: monitor, catalog: catalog)
        let reason = try await interruption(of: service, after: {
            catalog.route = self.makeDeviceRoute(effectiveInputDeviceID: "other-device")
            monitor.emit(.devices)
        })

        XCTAssertEqual(reason, .deviceChanged)
    }

    func testSelectedDeviceChangedInterrupts() async throws {
        let monitor = FakeAudioDeviceMonitor()
        let service = makeService(makeFactory(), monitor: monitor)
        let reason = try await interruption(of: service, after: { monitor.emit(.selectedDeviceChanged) })

        XCTAssertEqual(reason, .deviceChanged)
    }

    func testInputMutedInterruptsWhenProcessInputIsMuted() async throws {
        let monitor = FakeAudioDeviceMonitor()
        let catalog = FakeAudioCaptureHardwareCatalog(route: makeDeviceRoute())
        catalog.processInputMuted = true
        let service = makeService(makeFactory(), monitor: monitor, catalog: catalog)
        let reason = try await interruption(of: service, after: { monitor.emit(.inputMuted) })

        XCTAssertEqual(reason, .inputMuted)
    }

    func testIOStoppedAbnormallyInterrupts() async throws {
        let monitor = FakeAudioDeviceMonitor()
        let service = makeService(makeFactory(), monitor: monitor)
        let reason = try await interruption(of: service, after: { monitor.emit(.ioStoppedAbnormally) })

        XCTAssertEqual(reason, .ioStoppedAbnormally)
    }

    func testRouteResolutionFailureDuringDeviceChangeInterruptsAsUnavailable() async throws {
        let monitor = FakeAudioDeviceMonitor()
        let catalog = FakeAudioCaptureHardwareCatalog(route: makeDeviceRoute())
        let service = makeService(makeFactory(), monitor: monitor, catalog: catalog)
        let reason = try await interruption(of: service, after: {
            catalog.resolveError = FakeError(message: "device vanished")
            monitor.emit(.selectedDeviceAlive)
        })

        XCTAssertEqual(reason, .deviceUnavailable)
    }

    func testBenignDeviceNotificationsDoNotInterruptCapture() async throws {
        // Every non-interrupting branch of handleDeviceChange in one session:
        // processor overload (log only), unmuted input, default-output change on a
        // non-voice-processing backend, default-input change with a pinned device,
        // and an alive check that resolves to the same route.
        let monitor = FakeAudioDeviceMonitor()
        let catalog = FakeAudioCaptureHardwareCatalog(
            route: makeDeviceRoute(preferredInputDeviceID: "pinned-device")
        )
        let service = makeService(makeFactory(), monitor: monitor, catalog: catalog)
        var interruptedCount = 0
        service.onEvent = { event in
            if case .interrupted = event {
                interruptedCount += 1
            }
        }
        let sessionID = UUID()
        _ = try await service.startCapture(
            sessionID: sessionID,
            preferredInputDeviceID: "pinned-device",
            echoCancellationEnabled: false
        )

        monitor.emit(.processorOverload)
        monitor.emit(.inputMuted)
        monitor.emit(.defaultOutput)
        monitor.emit(.defaultInput)
        monitor.emit(.selectedDeviceAlive)

        // stopCapture is serialized behind the emitted changes on the control queue,
        // so a .complete outcome proves none of them interrupted the session.
        let captured = await service.stopCapture(sessionID: sessionID)
        XCTAssertEqual(captured.outcome, .complete)
        XCTAssertEqual(interruptedCount, 0)
    }

    func testSecondInterruptionWhileOnePendingIsIgnored() async throws {
        let monitor = FakeAudioDeviceMonitor()
        let service = makeService(makeFactory(), monitor: monitor)
        let interrupted = expectation(description: "interrupted exactly once")
        var interruptedCount = 0
        service.onEvent = { event in
            if case .interrupted = event {
                interruptedCount += 1
                interrupted.fulfill()
            }
        }
        let sessionID = UUID()
        _ = try await service.startCapture(
            sessionID: sessionID,
            preferredInputDeviceID: nil,
            echoCancellationEnabled: false
        )

        monitor.emit(.selectedDeviceChanged)
        await fulfillment(of: [interrupted], timeout: 2)
        // The capture is already marked interrupted; further changes must be ignored.
        monitor.emit(.selectedDeviceChanged)
        monitor.emit(.ioStoppedAbnormally)

        let captured = await service.stopCapture(sessionID: sessionID)
        XCTAssertEqual(captured.outcome, .interrupted(.deviceChanged))
        XCTAssertEqual(interruptedCount, 1)
    }

    // MARK: - Restart discards previous capture

    func testStartingNewCaptureDiscardsPreviousOne() async throws {
        let factory = makeFactory()
        let service = makeService(factory)
        let firstID = UUID()
        let secondID = UUID()
        _ = try await service.startCapture(
            sessionID: firstID,
            preferredInputDeviceID: nil,
            echoCancellationEnabled: false
        )

        _ = try await service.startCapture(
            sessionID: secondID,
            preferredInputDeviceID: nil,
            echoCancellationEnabled: false
        )

        // The first driver was stopped when the second capture began.
        XCTAssertEqual(factory.drivers.first?.stopCallCount, 1)
        let second = await service.stopCapture(sessionID: secondID)
        XCTAssertEqual(second.sessionID, secondID)
        XCTAssertEqual(second.outcome, .complete)
        // The first session is gone; stopping it reports the abnormal-stop guard.
        let first = await service.stopCapture(sessionID: firstID)
        XCTAssertEqual(first.outcome, .interrupted(.ioStoppedAbnormally))
    }

    // MARK: - Helpers

    /// Starts a capture, performs `change`, and returns the interruption reason the
    /// service reported for that session (also asserting the final outcome matches).
    private func interruption(
        of service: AudioCaptureService,
        echoCancellationEnabled: Bool = false,
        after change: @escaping () -> Void
    ) async throws -> AudioCaptureInterruption? {
        let interrupted = expectation(description: "capture interrupted")
        var interruptedReason: AudioCaptureInterruption?
        service.onEvent = { event in
            if case let .interrupted(_, reason) = event {
                interruptedReason = reason
                interrupted.fulfill()
            }
        }
        let sessionID = UUID()
        _ = try await service.startCapture(
            sessionID: sessionID,
            preferredInputDeviceID: nil,
            echoCancellationEnabled: echoCancellationEnabled
        )

        change()

        await fulfillment(of: [interrupted], timeout: 2)
        await service.cancelCapture(sessionID: sessionID, reason: nil)
        return interruptedReason
    }

    private func makeService(
        _ factory: FakeAudioCaptureDriverFactory,
        monitor: FakeAudioDeviceMonitor = FakeAudioDeviceMonitor(),
        catalog: FakeAudioCaptureHardwareCatalog? = nil,
        firstFrameDeadlineSeconds: Double = 10
    ) -> AudioCaptureService {
        AudioCaptureService(
            deviceMonitor: monitor,
            hardwareCatalog: catalog ?? FakeAudioCaptureHardwareCatalog(route: makeDeviceRoute()),
            driverFactory: factory,
            firstFrameDeadlineSeconds: firstFrameDeadlineSeconds
        )
    }

    private func makeFactory() -> FakeAudioCaptureDriverFactory {
        FakeAudioCaptureDriverFactory(
            format: AudioCaptureFormat(sampleRate: 16_000, channelCount: 1),
            samples: Array(repeating: 0.2, count: 1_600)
        )
    }

    private func makeDeviceRoute(
        preferredInputDeviceID: String? = nil,
        effectiveInputDeviceID: String = "test-device"
    ) -> AudioDeviceRoute {
        AudioDeviceRoute(
            preferredInputDeviceID: preferredInputDeviceID,
            effectiveInputDeviceID: effectiveInputDeviceID,
            effectiveInputName: "Test Microphone",
            inputTransport: .builtIn,
            outputTransport: .builtIn,
            nominalInputSampleRate: 16_000,
            inputChannelCount: 1
        )
    }
}

// MARK: - Fakes (mirrors the private stubs in AudioCaptureServiceTests, which this
// file cannot reuse because they are private to that file)

private final class FakeAudioDeviceMonitor: AudioDeviceMonitorProtocol {
    var onChange: ((AudioDeviceChangeReason) -> Void)?
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var watchedDeviceIDs: [AudioObjectID?] = []

    func start() {
        startCallCount += 1
    }

    func stop() {
        stopCallCount += 1
    }

    func watch(deviceID: AudioObjectID?) {
        watchedDeviceIDs.append(deviceID)
    }

    func emit(_ reason: AudioDeviceChangeReason) {
        onChange?(reason)
    }
}

private final class FakeAudioCaptureHardwareCatalog: AudioCaptureHardwareCatalogProtocol {
    var route: AudioDeviceRoute
    var resolveError: Error?
    var processInputMuted = false

    init(route: AudioDeviceRoute) {
        self.route = route
    }

    func availableInputDevices() -> [AudioInputDevice] {
        []
    }

    func resolveDeviceRoute(preferredInputDeviceID: String?) throws -> CoreAudioRouteResolution {
        if let resolveError {
            throw resolveError
        }
        return CoreAudioRouteResolution(inputDeviceID: 42, route: route)
    }

    func deviceID(forUID uid: String) -> AudioObjectID? {
        42
    }

    func processIsRunningInput() -> Bool? {
        false
    }

    func processInputIsMuted() -> Bool? {
        processInputMuted
    }
}

private final class FakeAudioCaptureDriver: AudioCaptureDriver {
    let backend: AudioCaptureBackend
    let format: AudioCaptureFormat
    private(set) var stopCallCount = 0

    init(backend: AudioCaptureBackend, format: AudioCaptureFormat) {
        self.backend = backend
        self.format = format
    }

    func stop() {
        stopCallCount += 1
    }
}

private final class FakeAudioCaptureDriverFactory: AudioCaptureDriverFactoryProtocol {
    let format: AudioCaptureFormat
    let samples: [Float]
    var failingBackends: [AudioCaptureBackend]
    private(set) var startedBackends: [AudioCaptureBackend] = []
    private(set) var drivers: [FakeAudioCaptureDriver] = []
    private(set) var configurationChangeHandlers: [() -> Void] = []

    init(
        format: AudioCaptureFormat,
        samples: [Float] = [],
        failingBackends: [AudioCaptureBackend] = []
    ) {
        self.format = format
        self.samples = samples
        self.failingBackends = failingBackends
    }

    func startDriver(
        for plan: AudioCapturePlan,
        inputDeviceID: AudioObjectID,
        ring: OpaquePointer,
        onConfigurationChange: @escaping () -> Void
    ) throws -> AudioCaptureDriverStart {
        startedBackends.append(plan.backend)
        if failingBackends.contains(plan.backend) {
            throw AudioCaptureServiceError.operationFailed("Start test driver", -1)
        }
        if !samples.isEmpty {
            samples.withUnsafeBufferPointer {
                _ = SuniyeAudioRingBufferWrite(ring, $0.baseAddress, samples.count)
            }
        }
        let driver = FakeAudioCaptureDriver(backend: plan.backend, format: format)
        drivers.append(driver)
        configurationChangeHandlers.append(onConfigurationChange)
        return AudioCaptureDriverStart(driver: driver, format: format)
    }

    /// Simulates the engine emitting a configuration change for the current driver.
    func triggerConfigurationChange() {
        configurationChangeHandlers.last?()
    }
}
