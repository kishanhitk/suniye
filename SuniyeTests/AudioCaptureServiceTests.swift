import CoreAudio
import XCTest
@testable import Suniye

final class AudioCaptureServiceTests: XCTestCase {
    func testPolicyUsesInputOnlyHALWhenEchoCancellationIsDisabled() {
        let plan = AudioCapturePolicy.primaryPlan(
            for: makeDeviceRoute(),
            echoCancellationEnabled: false
        )

        XCTAssertEqual(plan.backend, .inputOnlyHAL)
        XCTAssertFalse(plan.effectiveEchoCancellation)
        XCTAssertNil(plan.fallbackReason)
    }

    func testPolicyUsesVoiceProcessingForNonBluetoothRoute() {
        let plan = AudioCapturePolicy.primaryPlan(
            for: makeDeviceRoute(),
            echoCancellationEnabled: true
        )

        XCTAssertEqual(plan.backend, .voiceProcessingEngine)
        XCTAssertTrue(plan.effectiveEchoCancellation)
        XCTAssertNil(plan.fallbackReason)
    }

    func testPolicyBypassesEchoCancellationForBluetoothInput() {
        let plan = AudioCapturePolicy.primaryPlan(
            for: makeDeviceRoute(inputTransport: .bluetooth),
            echoCancellationEnabled: true
        )

        XCTAssertEqual(plan.backend, .inputOnlyHAL)
        XCTAssertFalse(plan.effectiveEchoCancellation)
        XCTAssertEqual(plan.fallbackReason, .bluetoothRoute)
    }

    func testPolicyBypassesEchoCancellationForBluetoothOutput() {
        let plan = AudioCapturePolicy.primaryPlan(
            for: makeDeviceRoute(outputTransport: .bluetooth),
            echoCancellationEnabled: true
        )

        XCTAssertEqual(plan.backend, .inputOnlyHAL)
        XCTAssertFalse(plan.effectiveEchoCancellation)
        XCTAssertEqual(plan.fallbackReason, .bluetoothRoute)
    }

    func testFallbackPolicyUsesStandardEngineAndTypedReason() {
        let plan = AudioCapturePolicy.fallbackPlan(
            for: makeDeviceRoute(),
            echoCancellationEnabled: true,
            reason: .backendStartFailed
        )

        XCTAssertEqual(plan.backend, .standardEngine)
        XCTAssertFalse(plan.effectiveEchoCancellation)
        XCTAssertEqual(plan.fallbackReason, .backendStartFailed)
    }

    func testServiceUsesDriverActualFormatAndStopsOwnedDriver() async throws {
        let monitor = StubAudioDeviceMonitor()
        let catalog = StubAudioCaptureHardwareCatalog(route: makeDeviceRoute())
        let factory = StubAudioCaptureDriverFactory(
            format: AudioCaptureFormat(sampleRate: 24_000, channelCount: 1),
            samples: Array(repeating: 0.2, count: 2_400)
        )
        let service = AudioCaptureService(
            deviceMonitor: monitor,
            hardwareCatalog: catalog,
            driverFactory: factory,
            firstFrameDeadlineSeconds: 10
        )
        let sessionID = UUID()

        let session = try await service.startCapture(
            sessionID: sessionID,
            preferredInputDeviceID: nil,
            echoCancellationEnabled: false
        )
        let captured = await service.stopCapture(sessionID: sessionID)

        XCTAssertEqual(session.route.inputSampleRate, 24_000)
        XCTAssertEqual(captured.sampleRate, 24_000)
        XCTAssertEqual(captured.outcome, .complete)
        XCTAssertEqual(factory.startedBackends, [.inputOnlyHAL])
        XCTAssertEqual(factory.drivers.first?.stopCallCount, 1)
    }

    func testServiceFallsBackUsingProductionPolicy() async throws {
        let factory = StubAudioCaptureDriverFactory(
            format: AudioCaptureFormat(sampleRate: 32_000, channelCount: 1),
            samples: Array(repeating: 0.2, count: 3_200),
            failingBackends: [.inputOnlyHAL]
        )
        let service = AudioCaptureService(
            deviceMonitor: StubAudioDeviceMonitor(),
            hardwareCatalog: StubAudioCaptureHardwareCatalog(route: makeDeviceRoute()),
            driverFactory: factory,
            firstFrameDeadlineSeconds: 10
        )
        let sessionID = UUID()

        let session = try await service.startCapture(
            sessionID: sessionID,
            preferredInputDeviceID: nil,
            echoCancellationEnabled: false
        )
        _ = await service.stopCapture(sessionID: sessionID)

        XCTAssertEqual(factory.startedBackends, [.inputOnlyHAL, .standardEngine])
        XCTAssertEqual(session.route.backend, .standardEngine)
        XCTAssertEqual(session.route.fallbackReason, .backendStartFailed)
    }

    func testSelectedDeviceFormatChangeInterruptsActiveCapture() async throws {
        let monitor = StubAudioDeviceMonitor()
        let service = AudioCaptureService(
            deviceMonitor: monitor,
            hardwareCatalog: StubAudioCaptureHardwareCatalog(route: makeDeviceRoute()),
            driverFactory: StubAudioCaptureDriverFactory(
                format: AudioCaptureFormat(sampleRate: 16_000, channelCount: 1),
                samples: Array(repeating: 0.2, count: 1_600)
            ),
            firstFrameDeadlineSeconds: 10
        )
        let interrupted = expectation(description: "capture interrupted")
        service.onEvent = { event in
            if case let .interrupted(_, reason) = event {
                XCTAssertEqual(reason, .formatChanged)
                interrupted.fulfill()
            }
        }
        let sessionID = UUID()
        _ = try await service.startCapture(
            sessionID: sessionID,
            preferredInputDeviceID: nil,
            echoCancellationEnabled: false
        )

        monitor.emit(.selectedDeviceFormat)
        await fulfillment(of: [interrupted], timeout: 1)
        await service.cancelCapture(sessionID: sessionID, reason: .formatChanged)
    }

    func testNoFirstFrameFallsBackThenInterrupts() async throws {
        let factory = StubAudioCaptureDriverFactory(
            format: AudioCaptureFormat(sampleRate: 16_000, channelCount: 1)
        )
        let service = AudioCaptureService(
            deviceMonitor: StubAudioDeviceMonitor(),
            hardwareCatalog: StubAudioCaptureHardwareCatalog(route: makeDeviceRoute()),
            driverFactory: factory,
            firstFrameDeadlineSeconds: 0.01
        )
        let interrupted = expectation(description: "no audio interruption")
        service.onEvent = { event in
            if case let .interrupted(_, reason) = event {
                XCTAssertEqual(reason, .noAudioArriving)
                interrupted.fulfill()
            }
        }
        let sessionID = UUID()
        _ = try await service.startCapture(
            sessionID: sessionID,
            preferredInputDeviceID: nil,
            echoCancellationEnabled: false
        )

        await fulfillment(of: [interrupted], timeout: 1)
        XCTAssertEqual(factory.startedBackends, [.inputOnlyHAL, .standardEngine])
        await service.cancelCapture(sessionID: sessionID, reason: .noAudioArriving)
    }

    func testSpuriousEngineConfigChangeForSameDeviceRestartsInsteadOfInterrupting() async throws {
        // Reproduces KIS-141: the standardEngine fallback emits one benign
        // AVAudioEngineConfigurationChange right after start. It must NOT surface
        // "Microphone changed"; the engine should be restarted in place so audio
        // keeps flowing on the same device.
        let factory = StubAudioCaptureDriverFactory(
            format: AudioCaptureFormat(sampleRate: 48_000, channelCount: 1),
            samples: Array(repeating: 0.2, count: 4_800),
            failingBackends: [.inputOnlyHAL]
        )
        let service = AudioCaptureService(
            deviceMonitor: StubAudioDeviceMonitor(),
            hardwareCatalog: StubAudioCaptureHardwareCatalog(route: makeDeviceRoute()),
            driverFactory: factory,
            firstFrameDeadlineSeconds: 10
        )
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
        // Let the drain timer mark the first frame as seen before the config change.
        try await Task.sleep(nanoseconds: 80_000_000)

        factory.triggerConfigurationChange()
        try await Task.sleep(nanoseconds: 80_000_000)

        let captured = await service.stopCapture(sessionID: sessionID)

        XCTAssertNil(interruptedReason, "benign same-device config change must not interrupt")
        XCTAssertEqual(captured.outcome, .complete)
        XCTAssertEqual(factory.startedBackends, [.inputOnlyHAL, .standardEngine, .standardEngine])
    }

    func testEngineConfigChangeAfterRealDeviceSwitchInterrupts() async throws {
        let catalog = StubAudioCaptureHardwareCatalog(route: makeDeviceRoute())
        let factory = StubAudioCaptureDriverFactory(
            format: AudioCaptureFormat(sampleRate: 48_000, channelCount: 1),
            samples: Array(repeating: 0.2, count: 4_800),
            failingBackends: [.inputOnlyHAL]
        )
        let service = AudioCaptureService(
            deviceMonitor: StubAudioDeviceMonitor(),
            hardwareCatalog: catalog,
            driverFactory: factory,
            firstFrameDeadlineSeconds: 10
        )
        let interrupted = expectation(description: "interrupted on real device change")
        service.onEvent = { event in
            if case let .interrupted(_, reason) = event {
                XCTAssertEqual(reason, .deviceChanged)
                interrupted.fulfill()
            }
        }
        let sessionID = UUID()
        _ = try await service.startCapture(
            sessionID: sessionID,
            preferredInputDeviceID: nil,
            echoCancellationEnabled: false
        )
        try await Task.sleep(nanoseconds: 80_000_000)

        // The active input device is swapped out from under us before the engine
        // reports its configuration change.
        catalog.route = makeDeviceRoute(effectiveInputDeviceID: "different-device")
        factory.triggerConfigurationChange()

        await fulfillment(of: [interrupted], timeout: 1)
        await service.cancelCapture(sessionID: sessionID, reason: .deviceChanged)
    }

    func testBenignConfigChangePreservesVoiceProcessingBackend() async throws {
        // A benign reconfig on a voiceProcessingEngine (echo-cancellation) session must restart on the
        // SAME backend via currentPlan, never silently downgrade to standardEngine (dropping AEC).
        let factory = StubAudioCaptureDriverFactory(
            format: AudioCaptureFormat(sampleRate: 48_000, channelCount: 1),
            samples: Array(repeating: 0.2, count: 4_800)
        )
        let service = AudioCaptureService(
            deviceMonitor: StubAudioDeviceMonitor(),
            hardwareCatalog: StubAudioCaptureHardwareCatalog(route: makeDeviceRoute()),
            driverFactory: factory,
            firstFrameDeadlineSeconds: 10
        )
        var interruptedReason: AudioCaptureInterruption?
        service.onEvent = { event in
            if case let .interrupted(_, reason) = event {
                interruptedReason = reason
            }
        }
        let sessionID = UUID()
        let session = try await service.startCapture(
            sessionID: sessionID,
            preferredInputDeviceID: nil,
            echoCancellationEnabled: true
        )
        XCTAssertEqual(session.route.backend, .voiceProcessingEngine)
        try await Task.sleep(nanoseconds: 80_000_000)

        factory.triggerConfigurationChange()
        try await Task.sleep(nanoseconds: 80_000_000)

        let captured = await service.stopCapture(sessionID: sessionID)

        XCTAssertNil(interruptedReason)
        XCTAssertEqual(factory.startedBackends, [.voiceProcessingEngine, .voiceProcessingEngine])
        XCTAssertEqual(captured.route?.backend, .voiceProcessingEngine)
        XCTAssertEqual(captured.route?.effectiveEchoCancellation, true)
    }

    func testRepeatedBenignConfigChangesInterruptAfterRestartCap() async throws {
        // The restart budget is bounded: after maximumEngineRestarts benign changes we stop restarting
        // and surface the interruption instead of looping forever.
        let factory = StubAudioCaptureDriverFactory(
            format: AudioCaptureFormat(sampleRate: 48_000, channelCount: 1),
            samples: Array(repeating: 0.2, count: 4_800),
            failingBackends: [.inputOnlyHAL]
        )
        let service = AudioCaptureService(
            deviceMonitor: StubAudioDeviceMonitor(),
            hardwareCatalog: StubAudioCaptureHardwareCatalog(route: makeDeviceRoute()),
            driverFactory: factory,
            firstFrameDeadlineSeconds: 10
        )
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
        try await Task.sleep(nanoseconds: 80_000_000)

        // Two changes restart in place; the third exceeds the cap and interrupts.
        factory.triggerConfigurationChange()
        try await Task.sleep(nanoseconds: 60_000_000)
        factory.triggerConfigurationChange()
        try await Task.sleep(nanoseconds: 60_000_000)
        factory.triggerConfigurationChange()
        try await Task.sleep(nanoseconds: 60_000_000)

        XCTAssertEqual(interruptedReason, .engineConfigurationChanged)
        XCTAssertEqual(
            factory.startedBackends,
            [.inputOnlyHAL, .standardEngine, .standardEngine, .standardEngine]
        )
        await service.cancelCapture(sessionID: sessionID, reason: .engineConfigurationChanged)
    }

    func testMaximumDurationDoesNotOverrideUnsafeAudioOutcome() async throws {
        let service = AudioCaptureService(
            deviceMonitor: StubAudioDeviceMonitor(),
            hardwareCatalog: StubAudioCaptureHardwareCatalog(route: makeDeviceRoute()),
            driverFactory: StubAudioCaptureDriverFactory(
                format: AudioCaptureFormat(sampleRate: 16_000, channelCount: 1),
                samples: Array(repeating: 0, count: 1_600)
            ),
            maximumDurationSeconds: 0.1,
            firstFrameDeadlineSeconds: 10
        )
        let sessionID = UUID()
        _ = try await service.startCapture(
            sessionID: sessionID,
            preferredInputDeviceID: nil,
            echoCancellationEnabled: false
        )

        let captured = await service.stopCapture(sessionID: sessionID)

        XCTAssertEqual(captured.outcome, .silent)
    }

    func testRingBufferPreservesOrderAcrossWraparound() {
        guard let ring = SuniyeAudioRingBufferCreate(4) else {
            return XCTFail("Expected ring buffer")
        }
        defer { SuniyeAudioRingBufferDestroy(ring) }

        XCTAssertEqual(write([1, 2, 3], to: ring), 3)
        XCTAssertEqual(read(2, from: ring), [1, 2])
        XCTAssertEqual(write([4, 5, 6], to: ring), 3)
        XCTAssertEqual(read(4, from: ring), [3, 4, 5, 6])
        XCTAssertEqual(SuniyeAudioRingBufferDroppedSamples(ring), 0)
    }

    func testRingBufferDownmixesPlanarChannelsAndCountsDroppedFrames() {
        guard let ring = SuniyeAudioRingBufferCreate(2) else {
            return XCTFail("Expected ring buffer")
        }
        defer { SuniyeAudioRingBufferDestroy(ring) }

        let left: [Float] = [1, 0, -1]
        let right: [Float] = [-1, 1, 1]
        let written = left.withUnsafeBufferPointer { leftBuffer in
            right.withUnsafeBufferPointer { rightBuffer in
                let channels: [UnsafePointer<Float>?] = [leftBuffer.baseAddress, rightBuffer.baseAddress]
                return channels.withUnsafeBufferPointer {
                    SuniyeAudioRingBufferWritePlanar(ring, $0.baseAddress, 2, 3)
                }
            }
        }

        XCTAssertEqual(written, 2)
        XCTAssertEqual(read(2, from: ring), [0, 0.5])
        XCTAssertEqual(SuniyeAudioRingBufferDroppedSamples(ring), 1)
    }

    func testRingBufferPlanarSingleChannelPreservesOrderAcrossWraparound() {
        guard let ring = SuniyeAudioRingBufferCreate(4) else {
            return XCTFail("Expected ring buffer")
        }
        defer { SuniyeAudioRingBufferDestroy(ring) }

        XCTAssertEqual(write([1, 2, 3], to: ring), 3)
        XCTAssertEqual(read(2, from: ring), [1, 2])
        let samples: [Float] = [4, 5, 6]
        let written = samples.withUnsafeBufferPointer { buffer in
            let channels: [UnsafePointer<Float>?] = [buffer.baseAddress]
            return channels.withUnsafeBufferPointer {
                SuniyeAudioRingBufferWritePlanar(ring, $0.baseAddress, 1, 3)
            }
        }

        XCTAssertEqual(written, 3)
        XCTAssertEqual(read(4, from: ring), [3, 4, 5, 6])
    }

    func testCapturedAudioHealthRejectsUnsafeAudio() {
        XCTAssertEqual(
            CapturedAudio(samples: [0.2], sampleRate: 16_000).outcome,
            .tooShort
        )
        XCTAssertEqual(
            CapturedAudio(samples: Array(repeating: 0, count: 1_600), sampleRate: 16_000).outcome,
            .silent
        )
        XCTAssertEqual(
            CapturedAudio(samples: Array(repeating: 1, count: 1_600), sampleRate: 16_000).outcome,
            .clipped
        )
        XCTAssertEqual(
            CapturedAudio(
                samples: Array(repeating: 0.2, count: 1_600),
                sampleRate: 16_000,
                droppedSampleCount: 1
            ).outcome,
            .bufferOverflow
        )
        var invalid = Array(repeating: Float(0.2), count: 1_600)
        invalid[42] = .nan
        XCTAssertEqual(CapturedAudio(samples: invalid, sampleRate: 16_000).outcome, .invalidSamples)
    }

    func testCapturedAudioHealthAcceptsUsableAudio() {
        let captured = CapturedAudio(
            samples: Array(repeating: 0.2, count: 1_600),
            sampleRate: 16_000
        )

        XCTAssertEqual(captured.outcome, .complete)
        XCTAssertEqual(captured.health.durationSeconds, 0.1, accuracy: 0.000_1)
        XCTAssertEqual(captured.health.rms, 0.2, accuracy: 0.000_1)
    }

    func testRoutePrivacyLogDoesNotContainDeviceIdentity() {
        let route = AudioRouteSnapshot(
            preferredInputDeviceID: "private-device-uid",
            effectiveInputDeviceID: "private-device-uid",
            effectiveInputName: "Kishan's Private Microphone",
            inputTransport: .bluetooth,
            outputTransport: .bluetooth,
            inputSampleRate: 48_000,
            inputChannelCount: 1,
            requestedEchoCancellation: true,
            effectiveEchoCancellation: false,
            backend: .inputOnlyHAL,
            fallbackReason: .bluetoothRoute
        )

        XCTAssertFalse(route.privacySafeLogValue.contains("private-device-uid"))
        XCTAssertFalse(route.privacySafeLogValue.contains("Kishan"))
        XCTAssertTrue(route.privacySafeLogValue.contains("input=bluetooth"))
    }

    private func write(_ samples: [Float], to ring: OpaquePointer) -> Int {
        samples.withUnsafeBufferPointer {
            SuniyeAudioRingBufferWrite(ring, $0.baseAddress, samples.count)
        }
    }

    private func read(_ count: Int, from ring: OpaquePointer) -> [Float] {
        var result = Array(repeating: Float(0), count: count)
        let readCount = result.withUnsafeMutableBufferPointer {
            SuniyeAudioRingBufferRead(ring, $0.baseAddress, count)
        }
        return Array(result.prefix(readCount))
    }

    private func makeDeviceRoute(
        effectiveInputDeviceID: String = "test-device",
        inputTransport: AudioDeviceTransport = .builtIn,
        outputTransport: AudioDeviceTransport = .builtIn
    ) -> AudioDeviceRoute {
        AudioDeviceRoute(
            preferredInputDeviceID: nil,
            effectiveInputDeviceID: effectiveInputDeviceID,
            effectiveInputName: "Test Microphone",
            inputTransport: inputTransport,
            outputTransport: outputTransport,
            nominalInputSampleRate: 16_000,
            inputChannelCount: 1
        )
    }
}

private final class StubAudioDeviceMonitor: AudioDeviceMonitorProtocol {
    var onChange: ((AudioDeviceChangeReason) -> Void)?
    private(set) var watchedDeviceID: AudioObjectID?

    func start() {}
    func stop() {}

    func watch(deviceID: AudioObjectID?) {
        watchedDeviceID = deviceID
    }

    func emit(_ reason: AudioDeviceChangeReason) {
        onChange?(reason)
    }
}

private final class StubAudioCaptureHardwareCatalog: AudioCaptureHardwareCatalogProtocol {
    var route: AudioDeviceRoute
    var processInputMuted = false

    init(route: AudioDeviceRoute) {
        self.route = route
    }

    func availableInputDevices() -> [AudioInputDevice] {
        []
    }

    func resolveDeviceRoute(preferredInputDeviceID: String?) throws -> CoreAudioRouteResolution {
        CoreAudioRouteResolution(inputDeviceID: 42, route: route)
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

private final class StubAudioCaptureDriver: AudioCaptureDriver {
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

private final class StubAudioCaptureDriverFactory: AudioCaptureDriverFactoryProtocol {
    let format: AudioCaptureFormat
    let samples: [Float]
    let failingBackends: [AudioCaptureBackend]
    private(set) var startedBackends: [AudioCaptureBackend] = []
    private(set) var drivers: [StubAudioCaptureDriver] = []
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
        let driver = StubAudioCaptureDriver(backend: plan.backend, format: format)
        drivers.append(driver)
        configurationChangeHandlers.append(onConfigurationChange)
        return AudioCaptureDriverStart(driver: driver, format: format)
    }

    /// Simulates the engine emitting an `AVAudioEngineConfigurationChange` for the
    /// currently running driver (the closure the service registered most recently).
    func triggerConfigurationChange() {
        configurationChangeHandlers.last?()
    }
}
