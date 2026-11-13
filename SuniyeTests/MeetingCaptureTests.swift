import CoreAudio
import XCTest
@testable import Suniye

final class MeetingResamplerTests: XCTestCase {
    func testFortyEightKilohertzBlocksBecomeSixteenKilohertzWithoutSeams() throws {
        let resampler = try MeetingResampler(inputSampleRate: 48_000)
        let tone = (0 ..< 48_000).map { Float(sin(2 * Double.pi * 440 * Double($0) / 48_000)) * 0.5 }
        var output: [Float] = []
        for start in stride(from: 0, to: tone.count, by: 960) {
            tone[start ..< start + 960].withUnsafeBufferPointer { output += resampler.process($0) }
        }
        output += resampler.flush()

        XCTAssertEqual(Double(output.count), 16_000, accuracy: 64)
        let settled = output[200 ..< 15_800]
        let crossings = zip(settled, settled.dropFirst()).filter { $0 < 0 && $1 >= 0 }.count
        XCTAssertEqual(Double(crossings), 440 * Double(settled.count) / 16_000, accuracy: 3)
        // A 440 Hz tone at 16 kHz moves at most 2π·440/16000·0.5 ≈ 0.087 per sample.
        // A seam between 20 ms blocks would show as a larger jump.
        let largestStep = zip(settled, settled.dropFirst()).map { abs($1 - $0) }.max() ?? 0
        XCTAssertLessThan(largestStep, 0.1)
    }

    func testSixteenKilohertzPassesThroughUnchanged() throws {
        let resampler = try MeetingResampler(inputSampleRate: 16_000)
        let samples: [Float] = [0.1, -0.2, 0.3]

        let output = samples.withUnsafeBufferPointer { resampler.process($0) }

        XCTAssertEqual(output, samples)
        XCTAssertEqual(resampler.flush(), [])
    }

    func testRejectsAnUnusableRate() {
        XCTAssertThrowsError(try MeetingResampler(inputSampleRate: 0))
    }
}

final class MeetingMicCaptureTests: XCTestCase {
    func testDeliversResampledBlocksFromTheInputOnlyBackendWithoutEchoCancellation() throws {
        let catalog = FakeMeetingCatalog(route: Self.route(id: "built-in", name: "MacBook Air Microphone"))
        let factory = FakeMeetingDriverFactory(rate: 48_000, samples: Array(repeating: 0.25, count: 4_800))
        let capture = MeetingMicCapture(hardwareCatalog: catalog, deviceMonitor: FakeMeetingMonitor(), driverFactory: factory) { nil }
        let received = expectation(description: "samples")
        received.assertForOverFulfill = false
        let collected = Collected<Float>()
        capture.onSamples = { collected.append($0); received.fulfill() }

        try capture.start()
        wait(for: [received], timeout: 2)
        capture.stop()

        XCTAssertEqual(factory.startedBackends.first, .inputOnlyHAL)
        XCTAssertEqual(Double(collected.samples.count), 1_600, accuracy: 64)
    }

    func testDefaultInputChangeReopensTheNewMicrophoneAndReportsIt() throws {
        let catalog = FakeMeetingCatalog(route: Self.route(id: "airpods", name: "AirPods Pro"))
        let monitor = FakeMeetingMonitor()
        let factory = FakeMeetingDriverFactory(rate: 16_000, samples: [0.1])
        let capture = MeetingMicCapture(hardwareCatalog: catalog, deviceMonitor: monitor, driverFactory: factory) { nil }
        let changed = expectation(description: "input changed")
        let events = Collected<MeetingAudioSourceEvent>()
        capture.onEvent = { events.append([$0]); changed.fulfill() }
        try capture.start()

        catalog.route = Self.route(id: "built-in", name: "MacBook Air Microphone")
        monitor.onChange?(.defaultInput)
        wait(for: [changed], timeout: 2)
        capture.stop()

        XCTAssertEqual(events.samples, [.inputChanged(deviceName: "MacBook Air Microphone")])
        XCTAssertEqual(factory.startedBackends.count, 2)
        XCTAssertEqual(factory.drivers.first?.stopCount, 1)
    }

    func testDefaultInputEventForTheSameMicrophoneKeepsTheStream() throws {
        let catalog = FakeMeetingCatalog(route: Self.route(id: "built-in", name: "MacBook Air Microphone"))
        let monitor = FakeMeetingMonitor()
        let factory = FakeMeetingDriverFactory(rate: 16_000, samples: [0.1])
        let capture = MeetingMicCapture(hardwareCatalog: catalog, deviceMonitor: monitor, driverFactory: factory) { nil }
        try capture.start()

        monitor.onChange?(.defaultInput)
        capture.stop()

        XCTAssertEqual(factory.startedBackends.count, 1)
    }

    func testNoAudioMovesToTheStandardEngineAndThenEndsTheTrack() throws {
        let catalog = FakeMeetingCatalog(route: Self.route(id: "built-in", name: "MacBook Air Microphone"))
        let factory = FakeMeetingDriverFactory(rate: 16_000, samples: [])
        let capture = MeetingMicCapture(hardwareCatalog: catalog, deviceMonitor: FakeMeetingMonitor(), driverFactory: factory, firstFrameDeadline: .milliseconds(50)) { nil }
        let failed = expectation(description: "failed")
        let events = Collected<MeetingAudioSourceEvent>()
        capture.onEvent = { events.append([$0]); failed.fulfill() }

        try capture.start()
        wait(for: [failed], timeout: 2)
        capture.stop()

        XCTAssertEqual(factory.startedBackends, [.inputOnlyHAL, .standardEngine])
        XCTAssertEqual(events.samples, [.failed("The microphone delivered no audio.")])
    }

    func testAPrimaryBackendThatCannotStartMovesToTheStandardEngine() throws {
        let catalog = FakeMeetingCatalog(route: Self.route(id: "built-in", name: "MacBook Air Microphone"))
        let factory = FakeMeetingDriverFactory(rate: 16_000, samples: [0.1])
        factory.failingBackends = [.inputOnlyHAL]
        let capture = MeetingMicCapture(hardwareCatalog: catalog, deviceMonitor: FakeMeetingMonitor(), driverFactory: factory) { nil }

        try capture.start()
        capture.stop()

        XCTAssertEqual(factory.startedBackends, [.inputOnlyHAL, .standardEngine])
    }

    func testAStreamThatStopsAbnormallyReopensTheSameMicrophone() throws {
        let catalog = FakeMeetingCatalog(route: Self.route(id: "built-in", name: "MacBook Air Microphone"))
        let monitor = FakeMeetingMonitor()
        let factory = FakeMeetingDriverFactory(rate: 16_000, samples: [0.1])
        let capture = MeetingMicCapture(hardwareCatalog: catalog, deviceMonitor: monitor, driverFactory: factory) { nil }
        try capture.start()

        monitor.onChange?(.ioStoppedAbnormally)
        capture.stop()

        XCTAssertEqual(factory.startedBackends.count, 2)
        XCTAssertEqual(factory.drivers.first?.stopCount, 1)
    }

    func testEngineConfigurationChangeRightAfterStartIsIgnored() throws {
        let catalog = FakeMeetingCatalog(route: Self.route(id: "built-in", name: "MacBook Air Microphone"))
        let factory = FakeMeetingDriverFactory(rate: 16_000, samples: [0.1])
        var now: TimeInterval = 100
        let capture = MeetingMicCapture(hardwareCatalog: catalog, deviceMonitor: FakeMeetingMonitor(), driverFactory: factory, uptime: { now }) { nil }
        try capture.start()

        factory.configurationChangeHandlers.last?()
        now += MeetingMicCapture.settleTime + 1
        let reopened = expectation(description: "reopen")
        factory.onStart = { if $0 == 2 { reopened.fulfill() } }
        factory.configurationChangeHandlers.last?()
        wait(for: [reopened], timeout: 2)
        capture.stop()

        XCTAssertEqual(factory.startedBackends.count, 2)
    }

    func testDigitalSilenceMovesToTheMicrophoneTheDeviceChoicePicksNow() throws {
        let catalog = FakeMeetingCatalog(route: Self.route(id: "built-in", name: "MacBook Air Microphone"))
        let factory = FakeMeetingDriverFactory(rate: 16_000, samples: Array(repeating: 0, count: 320))
        var now: TimeInterval = 100
        let capture = MeetingMicCapture(hardwareCatalog: catalog, deviceMonitor: FakeMeetingMonitor(), driverFactory: factory, uptime: { now }) { nil }
        let reopened = expectation(description: "reopen")
        factory.onStart = { if $0 == 2 { reopened.fulfill() } }
        let events = Collected<MeetingAudioSourceEvent>()
        capture.onEvent = { events.append([$0]) }
        try capture.start()
        Thread.sleep(forTimeInterval: 0.1)

        catalog.route = Self.route(id: "usb", name: "USB Microphone")
        now += MeetingMicCapture.digitalSilenceLimit + 1
        factory.feedLatestRing(Array(repeating: 0, count: 320))
        wait(for: [reopened], timeout: 2)
        capture.stop()

        XCTAssertEqual(factory.startedBackends.count, 2)
        XCTAssertEqual(events.samples, [.inputChanged(deviceName: "USB Microphone")])
    }

    func testDigitalSilenceOnTheSameMicrophoneKeepsTheStream() throws {
        let catalog = FakeMeetingCatalog(route: Self.route(id: "built-in", name: "MacBook Air Microphone"))
        let factory = FakeMeetingDriverFactory(rate: 16_000, samples: Array(repeating: 0, count: 320))
        var now: TimeInterval = 100
        let capture = MeetingMicCapture(hardwareCatalog: catalog, deviceMonitor: FakeMeetingMonitor(), driverFactory: factory, uptime: { now }) { nil }
        let delivered = expectation(description: "two blocks")
        delivered.expectedFulfillmentCount = 2
        capture.onSamples = { _ in delivered.fulfill() }
        try capture.start()
        Thread.sleep(forTimeInterval: 0.1)

        now += MeetingMicCapture.digitalSilenceLimit + 1
        factory.feedLatestRing(Array(repeating: 0, count: 320))
        wait(for: [delivered], timeout: 2)
        capture.stop()

        XCTAssertEqual(factory.startedBackends.count, 1, "a muted microphone is not a broken one")
    }

    func testReopensWithNoSoundBetweenThemEndTheTrack() throws {
        let factory = FakeMeetingDriverFactory(rate: 16_000, samples: Array(repeating: 0, count: 160))
        let (capture, delivered) = makeClockedCapture(factory: factory)
        let failed = expectation(description: "failed")
        let events = Collected<MeetingAudioSourceEvent>()
        capture.onEvent = { events.append([$0]); failed.fulfill() }
        try capture.start()

        for _ in 0 ... MeetingMicCapture.maximumReopens {
            XCTAssertEqual(delivered.wait(timeout: .now() + 2), .success)
            sendConfigurationChangeAfterTheSettleTime(factory)
        }
        wait(for: [failed], timeout: 2)
        capture.stop()

        XCTAssertEqual(events.samples, [.failed("The microphone kept failing (configuration change).")])
        XCTAssertEqual(factory.startedBackends.count, MeetingMicCapture.maximumReopens + 1)
    }

    func testSoundBetweenReopensKeepsTheTrackAlive() throws {
        let factory = FakeMeetingDriverFactory(rate: 16_000, samples: Array(repeating: 0.1, count: 160))
        let (capture, delivered) = makeClockedCapture(factory: factory)
        let events = Collected<MeetingAudioSourceEvent>()
        capture.onEvent = { events.append([$0]) }
        try capture.start()

        for _ in 0 ... MeetingMicCapture.maximumReopens + 4 {
            XCTAssertEqual(delivered.wait(timeout: .now() + 2), .success)
            sendConfigurationChangeAfterTheSettleTime(factory)
        }
        XCTAssertEqual(delivered.wait(timeout: .now() + 2), .success)
        capture.stop()

        XCTAssertEqual(events.samples, [])
        XCTAssertEqual(factory.startedBackends.count, MeetingMicCapture.maximumReopens + 6)
    }

    private var clock: TimeInterval = 100

    /// The semaphore signals once for each open: the fake driver writes one
    /// block, so a signal also means that the open finished.
    private func makeClockedCapture(factory: FakeMeetingDriverFactory) -> (MeetingMicCapture, DispatchSemaphore) {
        let catalog = FakeMeetingCatalog(route: Self.route(id: "built-in", name: "MacBook Air Microphone"))
        let capture = MeetingMicCapture(
            hardwareCatalog: catalog,
            deviceMonitor: FakeMeetingMonitor(),
            driverFactory: factory,
            uptime: { [weak self] in self?.clock ?? 0 }
        ) { nil }
        let delivered = DispatchSemaphore(value: 0)
        capture.onSamples = { _ in delivered.signal() }
        return (capture, delivered)
    }

    private func sendConfigurationChangeAfterTheSettleTime(_ factory: FakeMeetingDriverFactory) {
        clock += MeetingMicCapture.settleTime + 1
        factory.configurationChangeHandlers.last?()
    }

    static func route(id: String, name: String) -> AudioDeviceRoute {
        AudioDeviceRoute(
            preferredInputDeviceID: nil,
            effectiveInputDeviceID: id,
            effectiveInputName: name,
            inputTransport: .builtIn,
            outputTransport: .builtIn,
            nominalInputSampleRate: 48_000,
            inputChannelCount: 1,
            standIn: nil
        )
    }
}

final class MeetingRecorderTests: XCTestCase {
    private var folder: URL!
    private var now: TimeInterval = 1_024

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("MeetingRecorderTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    private func makeRecorder(you: FakeMeetingSource, them: FakeMeetingSource?, silenceCheck: DispatchTimeInterval = .seconds(60)) -> MeetingRecorder {
        var sources: [MeetingTrack: MeetingAudioSource] = [.you: you]
        sources[.them] = them
        return MeetingRecorder(
            sources: sources,
            fileURLs: [.you: url(.you), .them: url(.them)],
            uptime: { [unowned self] in self.now },
            silenceCheckInterval: silenceCheck
        )
    }

    private func url(_ track: MeetingTrack) -> URL {
        folder.appendingPathComponent("\(track.rawValue).wav")
    }

    func testWritesEachTrackToItsOwnFile() throws {
        let you = FakeMeetingSource(), them = FakeMeetingSource()
        let recorder = makeRecorder(you: you, them: them)
        try recorder.start()

        you.push(Array(repeating: 0.5, count: 320))
        them.push(Array(repeating: -0.25, count: 320))
        recorder.stop()

        XCTAssertEqual(try MeetingAudioFileReader.samples(at: url(.you)).first ?? 0, 0.5, accuracy: 0.001)
        XCTAssertEqual(try MeetingAudioFileReader.samples(at: url(.them)).first ?? 0, -0.25, accuracy: 0.001)
        XCTAssertEqual(you.startCount, 1)
        XCTAssertEqual(you.stopCount, 1)
    }

    func testMicrophoneTrackIsSilentWhileDictationRecords() throws {
        let you = FakeMeetingSource(), them = FakeMeetingSource()
        let recorder = makeRecorder(you: you, them: them)
        try recorder.start()

        you.push(Array(repeating: 0.5, count: 160))
        recorder.setMicrophoneMuted(true)
        you.push(Array(repeating: 0.5, count: 160))
        them.push(Array(repeating: 0.3, count: 320))
        recorder.setMicrophoneMuted(false)
        you.push(Array(repeating: 0.5, count: 160))
        recorder.stop()

        let mic = try MeetingAudioFileReader.samples(at: url(.you))
        XCTAssertEqual(mic.count, 480)
        XCTAssertEqual(mic[100], 0.5, accuracy: 0.001)
        XCTAssertEqual(mic[200], 0, accuracy: 0.0001)
        XCTAssertEqual(mic[400], 0.5, accuracy: 0.001)
        XCTAssertEqual(try MeetingAudioFileReader.samples(at: url(.them))[200], 0.3, accuracy: 0.001)
    }

    func testPauseKeepsTheTailASourceHandsOverWhileStoppingAndWritesNothingUntilResume() throws {
        let you = FakeMeetingSource()
        let recorder = makeRecorder(you: you, them: nil)
        let outputs = Collected<MeetingRecorderOutput>()
        recorder.onOutput = { outputs.append([$0]) }
        try recorder.start()
        you.push(Array(repeating: 0.5, count: 160))
        you.tailOnStop = Array(repeating: 0.7, count: 80)

        recorder.pause()
        you.push(Array(repeating: 0.9, count: 160))
        now += 30
        you.tailOnStop = []
        try recorder.resume()
        you.push(Array(repeating: 0.2, count: 160))
        recorder.stop()

        let mic = try MeetingAudioFileReader.samples(at: url(.you))
        XCTAssertEqual(mic.count, 400, "paused audio and paused time are not written")
        XCTAssertEqual(mic[200], 0.7, accuracy: 0.001)
        XCTAssertEqual(mic[300], 0.2, accuracy: 0.001)
        XCTAssertEqual(outputs.samples.map(\.positionOrPause), [0, 160, nil, 240], "the pause follows the tail")
        XCTAssertEqual(you.startCount, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url(.them).path))
    }

    func testACallTrackThatCannotStartLeavesTheMicrophoneRecording() throws {
        let you = FakeMeetingSource(), them = FakeMeetingSource()
        them.startError = FakeStartError()
        let recorder = makeRecorder(you: you, them: them)
        let failed = expectation(description: "failed")
        let events = Collected<MeetingRecorderEvent>()
        recorder.onEvent = { event in
            guard case .trackFailed = event else { return }
            events.append([event])
            failed.fulfill()
        }

        try recorder.start()
        you.push(Array(repeating: 0.5, count: 160))
        wait(for: [failed], timeout: 2)
        recorder.stop()

        XCTAssertEqual(events.samples, [.trackFailed(.them, "tap refused")])
        XCTAssertEqual(try MeetingAudioFileReader.sampleCount(at: url(.you)), 160)
    }

    func testStartThrowsAndReportsNothingWhenNoTrackStarts() throws {
        let you = FakeMeetingSource(), them = FakeMeetingSource()
        you.startError = FakeStartError()
        them.startError = FakeStartError()
        let recorder = makeRecorder(you: you, them: them)
        let events = Collected<MeetingRecorderEvent>()
        recorder.onEvent = { events.append([$0]) }

        XCTAssertThrowsError(try recorder.start())
        you.push(Array(repeating: 0.5, count: 160))
        recorder.stop()

        XCTAssertEqual(events.samples, [])
        XCTAssertEqual(try MeetingAudioFileReader.sampleCount(at: url(.you)), 0)
    }

    func testAResumeThatCannotStartStaysPaused() throws {
        let you = FakeMeetingSource()
        let recorder = makeRecorder(you: you, them: nil)
        try recorder.start()
        recorder.pause()

        you.startError = FakeStartError()
        XCTAssertThrowsError(try recorder.resume())
        you.push(Array(repeating: 0.9, count: 160))
        you.startError = nil
        now += 5
        try recorder.resume()
        you.push(Array(repeating: 0.2, count: 160))
        recorder.stop()

        let mic = try MeetingAudioFileReader.samples(at: url(.you))
        XCTAssertEqual(mic.count, 160)
        XCTAssertEqual(mic.first ?? 0, 0.2, accuracy: 0.001)
    }

    func testAGapInATrackIsFilledSoBothFilesStayOnTheWallClock() throws {
        let you = FakeMeetingSource(), them = FakeMeetingSource()
        let recorder = makeRecorder(you: you, them: them)
        let positions = Collected<Int>()
        recorder.onOutput = { output in
            if case let .samples(.you, _, position) = output { positions.append([position]) }
        }
        try recorder.start()

        now += 0.0625
        you.push(Array(repeating: 0.5, count: 1_000))
        now += 2
        you.push(Array(repeating: 0.5, count: 1_000))
        recorder.stop()

        XCTAssertEqual(try MeetingAudioFileReader.sampleCount(at: url(.you)), 33_000, "2.0625 s on the wall clock")
        XCTAssertEqual(positions.samples, [0, 1_000, 32_000])
    }

    func testReportsCallSilenceAfterTheLimitAndItsReturn() throws {
        let you = FakeMeetingSource(), them = FakeMeetingSource()
        let recorder = makeRecorder(you: you, them: them, silenceCheck: .milliseconds(20))
        let silent = expectation(description: "silent")
        let returned = expectation(description: "returned")
        recorder.onEvent = { event in
            if event == .callAudioSilent(heardBefore: false) { silent.fulfill() }
            if event == .callAudioReturned { returned.fulfill() }
        }
        try recorder.start()

        them.push(Array(repeating: 0, count: 320))
        now += MeetingRecorder.callSilenceLimit + 1
        wait(for: [silent], timeout: 2)
        them.push(Array(repeating: 0.2, count: 320))
        wait(for: [returned], timeout: 2)
        recorder.stop()
    }

    func testSilenceAfterSoundIsReportedAsStoppedCallAudioAndRestartRebuildsTheTrack() throws {
        let you = FakeMeetingSource(), them = FakeMeetingSource()
        let recorder = makeRecorder(you: you, them: them, silenceCheck: .milliseconds(20))
        let stopped = expectation(description: "stopped")
        recorder.onEvent = { if $0 == .callAudioSilent(heardBefore: true) { stopped.fulfill() } }
        try recorder.start()

        them.push(Array(repeating: 0.2, count: 320))
        now += MeetingRecorder.callSilenceLimit + 1
        wait(for: [stopped], timeout: 2)
        recorder.restartCallAudio()
        recorder.stop()

        XCTAssertEqual(them.startCount, 2)
        XCTAssertEqual(them.stopCount, 2)
        XCTAssertEqual(you.startCount, 1)
    }

    func testMicrophoneOnlyRecordingNeverReportsCallSilence() throws {
        let you = FakeMeetingSource()
        let recorder = makeRecorder(you: you, them: nil, silenceCheck: .milliseconds(10))
        let events = Collected<MeetingRecorderEvent>()
        recorder.onEvent = { events.append([$0]) }
        try recorder.start()

        now += MeetingRecorder.callSilenceLimit * 2
        Thread.sleep(forTimeInterval: 0.1)
        recorder.stop()

        XCTAssertFalse(events.samples.contains { if case .callAudioSilent = $0 { return true }; return false })
        XCTAssertEqual(recorder.tracks, [.you])
    }

    func testSourceEventsReachTheRecorderListener() throws {
        let you = FakeMeetingSource()
        let recorder = makeRecorder(you: you, them: nil)
        let received = expectation(description: "event")
        let events = Collected<MeetingRecorderEvent>()
        recorder.onEvent = { events.append([$0]); received.fulfill() }
        try recorder.start()

        you.onEvent?(.failed("gone"))
        wait(for: [received], timeout: 2)
        recorder.stop()

        XCTAssertEqual(events.samples, [.trackFailed(.you, "gone")])
    }
}

// MARK: - Fakes

private extension MeetingRecorderOutput {
    var positionOrPause: Int? {
        if case let .samples(_, _, position) = self { return position }
        return nil
    }
}

private final class Collected<Element>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Element] = []

    func append(_ items: [Element]) {
        lock.lock()
        storage += items
        lock.unlock()
    }

    var samples: [Element] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private struct FakeStartError: LocalizedError {
    var errorDescription: String? { "tap refused" }
}

private final class FakeMeetingSource: MeetingAudioSource {
    var onSamples: (([Float]) -> Void)?
    var onEvent: ((MeetingAudioSourceEvent) -> Void)?
    var startError: Error?
    var tailOnStop: [Float] = []
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() throws {
        startCount += 1
        if let startError {
            throw startError
        }
    }

    func stop() {
        stopCount += 1
        if !tailOnStop.isEmpty {
            onSamples?(tailOnStop)
        }
    }

    func push(_ samples: [Float]) {
        onSamples?(samples)
    }
}

private final class FakeMeetingMonitor: AudioDeviceMonitorProtocol {
    var onChange: ((AudioDeviceChangeReason) -> Void)?
    func start() {}
    func stop() {}
    func watch(deviceID: AudioObjectID?) {}
}

private final class FakeMeetingCatalog: AudioCaptureHardwareCatalogProtocol {
    var route: AudioDeviceRoute

    init(route: AudioDeviceRoute) {
        self.route = route
    }

    func availableInputDevices() -> [AudioInputDevice] {
        [AudioInputDevice(id: route.effectiveInputDeviceID, name: route.effectiveInputName, isDefault: true, transport: route.inputTransport)]
    }

    func resolveDeviceRoute(preferredInputDeviceID: String?) throws -> CoreAudioRouteResolution {
        CoreAudioRouteResolution(inputDeviceID: 42, route: route)
    }

    func deviceID(forUID uid: String) -> AudioObjectID? { 42 }
    func processIsRunningInput() -> Bool? { false }
    func processInputIsMuted() -> Bool? { false }
}

private final class FakeMeetingDriver: AudioCaptureDriver {
    let backend: AudioCaptureBackend
    let format: AudioCaptureFormat
    private(set) var stopCount = 0

    init(backend: AudioCaptureBackend, format: AudioCaptureFormat) {
        self.backend = backend
        self.format = format
    }

    func stop() {
        stopCount += 1
    }
}

private final class FakeMeetingDriverFactory: AudioCaptureDriverFactoryProtocol, @unchecked Sendable {
    let rate: Int
    let samples: [Float]
    private(set) var startedBackends: [AudioCaptureBackend] = []
    private(set) var drivers: [FakeMeetingDriver] = []
    private(set) var configurationChangeHandlers: [() -> Void] = []
    var failingBackends: Set<AudioCaptureBackend> = []
    var onStart: ((Int) -> Void)?

    init(rate: Int, samples: [Float]) {
        self.rate = rate
        self.samples = samples
    }

    func startDriver(
        for plan: AudioCapturePlan,
        inputDeviceID: AudioObjectID,
        ring: OpaquePointer,
        onConfigurationChange: @escaping () -> Void
    ) throws -> AudioCaptureDriverStart {
        startedBackends.append(plan.backend)
        if failingBackends.contains(plan.backend) {
            throw AudioCaptureServiceError.ringBufferUnavailable
        }
        if !samples.isEmpty {
            samples.withUnsafeBufferPointer { _ = SuniyeAudioRingBufferWrite(ring, $0.baseAddress, samples.count) }
        }
        let driver = FakeMeetingDriver(backend: plan.backend, format: AudioCaptureFormat(sampleRate: rate, channelCount: 1))
        drivers.append(driver)
        configurationChangeHandlers.append(onConfigurationChange)
        rings.append(ring)
        onStart?(startedBackends.count)
        return AudioCaptureDriverStart(driver: driver, format: driver.format)
    }

    private(set) var rings: [OpaquePointer] = []

    func feedLatestRing(_ samples: [Float]) {
        guard let ring = rings.last else { return }
        samples.withUnsafeBufferPointer { _ = SuniyeAudioRingBufferWrite(ring, $0.baseAddress, samples.count) }
    }
}
