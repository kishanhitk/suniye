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

    func testVoiceProcessingIgnoresNegotiatedHardwareFormatChange() async throws {
        let monitor = StubAudioDeviceMonitor()
        let catalog = StubAudioCaptureHardwareCatalog(route: makeDeviceRoute())
        let factory = StubAudioCaptureDriverFactory(
            format: AudioCaptureFormat(sampleRate: 16_000, channelCount: 1),
            samples: Array(repeating: 0.2, count: 1_600)
        )
        let service = AudioCaptureService(
            deviceMonitor: monitor,
            hardwareCatalog: catalog,
            driverFactory: factory,
            firstFrameDeadlineSeconds: 10
        )
        let interrupted = expectation(description: "capture not interrupted")
        interrupted.isInverted = true
        service.onEvent = { event in
            if case .interrupted = event {
                interrupted.fulfill()
            }
        }
        let sessionID = UUID()
        _ = try await service.startCapture(
            sessionID: sessionID,
            preferredInputDeviceID: nil,
            echoCancellationEnabled: true
        )

        catalog.route = makeDeviceRoute(sampleRate: 48_000)
        monitor.emit(.selectedDeviceFormat)
        await fulfillment(of: [interrupted], timeout: 0.1)
        let captured = await service.stopCapture(sessionID: sessionID)

        XCTAssertEqual(factory.startedBackends, [.voiceProcessingEngine])
        XCTAssertEqual(captured.outcome, .complete)
    }

    func testSelectedDeviceFormatChangeInterruptsActiveCapture() async throws {
        let monitor = StubAudioDeviceMonitor()
        let catalog = StubAudioCaptureHardwareCatalog(route: makeDeviceRoute())
        let service = AudioCaptureService(
            deviceMonitor: monitor,
            hardwareCatalog: catalog,
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

        catalog.route = makeDeviceRoute(sampleRate: 48_000)
        monitor.emit(.selectedDeviceFormat)
        await fulfillment(of: [interrupted], timeout: 1)
        await service.cancelCapture(sessionID: sessionID, reason: .formatChanged)
    }

    func testAECStartupEngineConfigurationChangeRestartsVoiceProcessing() async throws {
        let factory = StubAudioCaptureDriverFactory(
            format: AudioCaptureFormat(sampleRate: 16_000, channelCount: 1)
        )
        let service = AudioCaptureService(
            deviceMonitor: StubAudioDeviceMonitor(),
            hardwareCatalog: StubAudioCaptureHardwareCatalog(route: makeDeviceRoute()),
            driverFactory: factory,
            firstFrameDeadlineSeconds: 10
        )
        let sessionID = UUID()
        _ = try await service.startCapture(
            sessionID: sessionID,
            preferredInputDeviceID: nil,
            echoCancellationEnabled: true
        )

        factory.emitConfigurationChange(forStartAt: 0)
        let captured = await service.stopCapture(sessionID: sessionID)

        XCTAssertEqual(factory.startedBackends, [.voiceProcessingEngine, .voiceProcessingEngine])
        XCTAssertEqual(captured.outcome, .tooShort)
    }

    func testAECFallbackStartupEngineConfigurationChangeRestartsStandardEngine() async throws {
        let factory = StubAudioCaptureDriverFactory(
            format: AudioCaptureFormat(sampleRate: 16_000, channelCount: 1),
            failingBackends: [.voiceProcessingEngine]
        )
        let service = AudioCaptureService(
            deviceMonitor: StubAudioDeviceMonitor(),
            hardwareCatalog: StubAudioCaptureHardwareCatalog(route: makeDeviceRoute()),
            driverFactory: factory,
            firstFrameDeadlineSeconds: 10
        )
        let sessionID = UUID()
        _ = try await service.startCapture(
            sessionID: sessionID,
            preferredInputDeviceID: nil,
            echoCancellationEnabled: true
        )

        factory.emitConfigurationChange(forStartAt: 0)
        let captured = await service.stopCapture(sessionID: sessionID)

        XCTAssertEqual(factory.startedBackends, [.voiceProcessingEngine, .standardEngine, .standardEngine])
        XCTAssertEqual(captured.outcome, .tooShort)
    }

    func testEngineConfigurationChangeAfterAudioArrivesInterruptsCapture() async throws {
        let factory = StubAudioCaptureDriverFactory(
            format: AudioCaptureFormat(sampleRate: 16_000, channelCount: 1),
            samples: Array(repeating: 0.2, count: 1_600)
        )
        let service = AudioCaptureService(
            deviceMonitor: StubAudioDeviceMonitor(),
            hardwareCatalog: StubAudioCaptureHardwareCatalog(route: makeDeviceRoute()),
            driverFactory: factory,
            firstFrameDeadlineSeconds: 10
        )
        let sessionID = UUID()
        _ = try await service.startCapture(
            sessionID: sessionID,
            preferredInputDeviceID: nil,
            echoCancellationEnabled: true
        )
        try await Task.sleep(nanoseconds: 80_000_000)

        factory.emitConfigurationChange(forStartAt: 0)
        let captured = await service.stopCapture(sessionID: sessionID)

        XCTAssertEqual(factory.startedBackends, [.voiceProcessingEngine])
        XCTAssertEqual(captured.outcome, .interrupted(.engineConfigurationChanged))
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
        inputTransport: AudioDeviceTransport = .builtIn,
        outputTransport: AudioDeviceTransport = .builtIn,
        sampleRate: Int = 16_000
    ) -> AudioDeviceRoute {
        AudioDeviceRoute(
            preferredInputDeviceID: nil,
            effectiveInputDeviceID: "test-device",
            effectiveInputName: "Test Microphone",
            inputTransport: inputTransport,
            outputTransport: outputTransport,
            nominalInputSampleRate: sampleRate,
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
    private var configurationChangeCallbacks: [() -> Void] = []

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
        configurationChangeCallbacks.append(onConfigurationChange)
        if !samples.isEmpty {
            samples.withUnsafeBufferPointer {
                _ = SuniyeAudioRingBufferWrite(ring, $0.baseAddress, samples.count)
            }
        }
        let driver = StubAudioCaptureDriver(backend: plan.backend, format: format)
        drivers.append(driver)
        return AudioCaptureDriverStart(driver: driver, format: format)
    }

    func emitConfigurationChange(forStartAt index: Int) {
        configurationChangeCallbacks[index]()
    }
}
