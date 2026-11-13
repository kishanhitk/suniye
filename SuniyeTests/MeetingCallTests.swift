import XCTest
@testable import Suniye

let zoom = MeetingCallApp(name: "Zoom", bundleID: "us.zoom.xos", isBrowser: false)
let teams = MeetingCallApp(name: "Microsoft Teams", bundleID: "com.microsoft.teams2", isBrowser: false)
let chrome = MeetingCallApp(name: "Chrome", bundleID: "com.google.Chrome", isBrowser: true)

func holding(_ apps: MeetingCallApp..., output: Bool = true) -> [MicrophoneUser] {
    apps.map { MicrophoneUser(app: $0, playsOutput: output) }
}

final class MeetingCallWatchTests: XCTestCase {
    func testHelperProcessesAndHostsBelongToTheirApp() {
        XCTAssertEqual(MeetingCallApps.app(forProcess: "com.google.Chrome.helper"), chrome)
        XCTAssertEqual(MeetingCallApps.app(forProcess: "com.apple.WebKit.GPU")?.name, "Safari")
        XCTAssertEqual(MeetingCallApps.app(forProcess: "com.microsoft.teams2"), teams)
        XCTAssertNil(MeetingCallApps.app(forProcess: "dev.suniye.app"))
        XCTAssertNil(MeetingCallApps.app(forProcess: "us.zoom.xosx"))
    }

    func testACallAppBecomesACallAfterTwoSecondsOnceUntilItReleasesTheMicrophone() {
        var watch = MeetingCallWatch()
        let noTitle: (MeetingCallApp) -> Bool = { _ in false }

        let starting = [0, 1].flatMap { watch.update(holding(zoom), at: $0, showsMeeting: noTitle) }
        let started = watch.update(holding(zoom), at: 2, showsMeeting: noTitle)
        let goingOn = watch.update(holding(zoom), at: 3, showsMeeting: noTitle)
        let ended = watch.update([], at: 4, showsMeeting: noTitle)
        let shortUse = watch.update(holding(teams), at: 10, showsMeeting: noTitle) + watch.update([], at: 11, showsMeeting: noTitle)

        XCTAssertEqual(starting, [])
        XCTAssertEqual(started, [.callStarted(zoom, confirmed: true)])
        XCTAssertEqual(goingOn, [])
        XCTAssertEqual(ended, [.callEnded(zoom)])
        XCTAssertEqual(shortUse, [], "a use shorter than the delay is no call")
    }

    func testABrowserIsACallAfterTwoSecondsWithACallTitleOrTwentyWithout() {
        var watch = MeetingCallWatch()
        var titleReads = 0
        let safari = MeetingCallApp(name: "Safari", bundleID: "com.apple.Safari", isBrowser: true)
        let showsMeeting: (MeetingCallApp) -> Bool = { app in
            titleReads += 1
            return app == safari
        }

        let early = watch.update(holding(chrome, safari), at: 0, showsMeeting: showsMeeting)
        let atTwo = watch.update(holding(chrome, safari), at: 2, showsMeeting: showsMeeting)
        let readsAtTwo = titleReads
        let beforeTwenty = watch.update(holding(chrome, safari), at: 19, showsMeeting: showsMeeting)
        let atTwenty = watch.update(holding(chrome, safari), at: 20, showsMeeting: showsMeeting)
        let afterwards = watch.update(holding(chrome, safari), at: 30, showsMeeting: showsMeeting)

        XCTAssertEqual(early, [])
        XCTAssertEqual(atTwo, [.callStarted(safari, confirmed: true)])
        XCTAssertEqual(beforeTwenty, [])
        XCTAssertEqual(atTwenty, [.callStarted(chrome, confirmed: false)])
        XCTAssertEqual(afterwards, [])
        XCTAssertEqual(titleReads, readsAtTwo + 2, "titles are read only until the browser's call starts")
    }

    func testARecordingFollowsOneCallAndReportsWhenItEnds() {
        var watch = MeetingCallWatch()
        let noTitle: (MeetingCallApp) -> Bool = { _ in false }
        _ = watch.update(holding(zoom), at: 0, showsMeeting: noTitle)
        _ = watch.update(holding(zoom), at: 2, showsMeeting: noTitle)

        let atStart = watch.recordingStarted(call: nil)
        let secondCall = watch.update(holding(zoom, teams), at: 5, showsMeeting: noTitle) + watch.update(holding(zoom, teams), at: 7, showsMeeting: noTitle)
        let zoomLeft = watch.update(holding(teams), at: 10, showsMeeting: noTitle)
        let teamsLater = watch.update([], at: 11, showsMeeting: noTitle)
            + watch.update(holding(teams), at: 12, showsMeeting: noTitle)
            + watch.update(holding(teams), at: 14, showsMeeting: noTitle)

        XCTAssertEqual(atStart, [.followed(zoom)], "a recording follows the call that goes on at its start")
        XCTAssertEqual(secondCall, [], "it follows one call")
        XCTAssertEqual(zoomLeft, [.recordedCallEnded(zoom, endedAt: 10, silent: false)])
        XCTAssertEqual(teamsLater, [.callEnded(teams), .followed(teams)], "after its call ended, it follows the next call that starts")
    }

    func testTheRecordedCallEndsOnceAfterTwoMinutesWithoutSound() {
        var watch = MeetingCallWatch()
        let noTitle: (MeetingCallApp) -> Bool = { _ in false }
        _ = watch.recordingStarted(call: zoom)
        _ = watch.update(holding(zoom), at: 0, showsMeeting: noTitle)
        _ = watch.update(holding(zoom), at: 5, showsMeeting: noTitle)

        let quiet = watch.update(holding(zoom, output: false), at: 124, showsMeeting: noTitle)
        let silent = watch.update(holding(zoom, output: false), at: 125, showsMeeting: noTitle)
        let later = watch.update(holding(zoom, output: false), at: 300, showsMeeting: noTitle)

        XCTAssertEqual(quiet, [])
        XCTAssertEqual(silent, [.recordedCallEnded(zoom, endedAt: 5, silent: true)])
        XCTAssertEqual(later, [])
    }
}

@MainActor
final class MeetingCallDetectorTests: XCTestCase {
    func testTheDetectorReadsOnlyWhileInputRunsAndNotDuringADictation() {
        let microphone = FakeMicrophoneUsers()
        let detector = MeetingCallDetector(reader: microphone, uptime: { 0 })

        detector.start()
        microphone.inputActivityChanged()
        let idleReads = microphone.reads
        microphone.anyInputRunning = true
        microphone.inputActivityChanged()
        let readsWithInput = microphone.reads
        detector.dictationChanged(active: true)
        microphone.inputActivityChanged()
        let readsDuringDictation = microphone.reads
        detector.dictationChanged(active: false)
        let readsAfterDictation = microphone.reads
        detector.stop()

        XCTAssertEqual(idleReads, 0, "no input runs: listeners only, no reads")
        XCTAssertEqual(readsWithInput, 1)
        XCTAssertEqual(readsDuringDictation, 1)
        XCTAssertEqual(readsAfterDictation, 2, "a dictation's end reads again")
        XCTAssertFalse(microphone.listening)
    }
}

/// Counts reads; the test sets what a read returns.
@MainActor
final class FakeMicrophoneUsers: MicrophoneUserReading {
    var anyInputRunning = false
    var users: [MicrophoneUser] = []
    var meetingTitles: Set<String> = []
    var onInputActivityChanged: (() -> Void)?
    private(set) var reads = 0
    private(set) var listening = false

    func startListening() {
        listening = true
    }

    func stopListening() {
        listening = false
    }

    func read() -> [MicrophoneUser] {
        reads += 1
        return users
    }

    func showsMeeting(_ browser: MeetingCallApp) -> Bool {
        meetingTitles.contains(browser.bundleID)
    }

    /// What a Core Audio listener does when an input device starts or stops.
    func inputActivityChanged() {
        onInputActivityChanged?()
    }
}
