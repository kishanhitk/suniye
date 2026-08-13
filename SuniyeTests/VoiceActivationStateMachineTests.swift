import XCTest
@testable import Suniye

/// Transition coverage for the Voice Activation state machine. Each test cites
/// the section of `always-listening-ux-plan.md` it enforces.
final class VoiceActivationStateMachineTests: XCTestCase {
    private func makeReady(followUp: Bool = false) -> VoiceActivationStateMachine {
        var machine = VoiceActivationStateMachine(
            configuration: .init(followUpWindowEnabled: followUp)
        )
        machine.handle(.enabled)
        return machine
    }

    // UX plan: states 1-2. Off -> Ready on enable; Off ignores everything else.
    func testEnableMovesOffToReady() {
        var machine = VoiceActivationStateMachine()
        XCTAssertEqual(machine.state, .off)
        XCTAssertEqual(machine.handle(.enabled), [])
        XCTAssertEqual(machine.state, .ready)
    }

    func testOffIgnoresNonEnableEvents() {
        var machine = VoiceActivationStateMachine()
        XCTAssertEqual(machine.handle(.wakeDetected(runActive: false)), [])
        XCTAssertEqual(machine.handle(.speechEnded), [])
        XCTAssertEqual(machine.state, .off)
    }

    // UX plan: state 3. Wake-up plays a cue and starts turn capture.
    func testWakeFromReadyStartsListening() {
        var machine = makeReady()
        let effects = machine.handle(.wakeDetected(runActive: false))
        XCTAssertEqual(effects, [.playWakeCue, .startTurnCapture(.initial)])
        XCTAssertEqual(machine.state, .listening(.initial))
    }

    // UX plan: state 5. Wake during a run captures an intervention turn.
    func testWakeDuringRunCapturesInterventionContext() {
        var machine = makeReady()
        machine.handle(.wakeDetected(runActive: true))
        XCTAssertEqual(machine.state, .listening(.duringRun))
        let effects = machine.handle(.speechEnded)
        XCTAssertEqual(effects, [.stopTurnCapture, .transcribeAndSubmit(.duringRun)])
        XCTAssertEqual(machine.state, .transcribing(.duringRun))
    }

    // UX plan: false wake-up. Silence returns to Ready and creates no turn.
    func testNoSpeechTimeoutReturnsToReadyWithoutSubmit() {
        var machine = makeReady()
        machine.handle(.wakeDetected(runActive: false))
        let effects = machine.handle(.noSpeechTimeout)
        XCTAssertEqual(effects, [.stopTurnCapture])
        XCTAssertEqual(machine.state, .ready)
    }

    // UX plan: state 3. The Cancel control discards the turn.
    func testCancelWhileListeningReturnsToReady() {
        var machine = makeReady()
        machine.handle(.wakeDetected(runActive: false))
        XCTAssertEqual(machine.handle(.cancelRequested), [.stopTurnCapture])
        XCTAssertEqual(machine.state, .ready)
    }

    func testTranscriptOutcomeReturnsToReady() {
        var machine = makeReady()
        machine.handle(.wakeDetected(runActive: false))
        machine.handle(.speechEnded)
        machine.handle(.transcriptSubmitted)
        XCTAssertEqual(machine.state, .ready)

        machine.handle(.wakeDetected(runActive: false))
        machine.handle(.speechEnded)
        machine.handle(.transcriptFailed)
        XCTAssertEqual(machine.state, .ready)
    }

    // UX plan: Mac sleeps or locks. Sleep suspends; wake restores Ready only
    // when the tap restarts cleanly.
    func testSleepSuspendsAndWakeRestoresOnlyWithTap() {
        var machine = makeReady()
        machine.handle(.systemSlept)
        XCTAssertEqual(machine.state, .suspended)
        machine.handle(.systemWoke(tapRestored: false))
        XCTAssertEqual(machine.state, .suspended)
        machine.handle(.systemWoke(tapRestored: true))
        XCTAssertEqual(machine.state, .ready)
    }

    func testSleepDuringListeningStopsCapture() {
        var machine = makeReady()
        machine.handle(.wakeDetected(runActive: false))
        XCTAssertEqual(machine.handle(.systemSlept), [.stopTurnCapture])
        XCTAssertEqual(machine.state, .suspended)
    }

    // Hold-to-talk coexistence: the tap pauses; listening state suspends.
    func testTapSuspensionAndRestore() {
        var machine = makeReady()
        machine.handle(.tapSuspended)
        XCTAssertEqual(machine.state, .suspended)
        machine.handle(.tapRestored)
        XCTAssertEqual(machine.state, .ready)
    }

    // UX plan: Turn Voice Activation off. Disable works from every state and
    // stops any capture in flight.
    func testDisableFromEachState() {
        var machine = makeReady()
        machine.handle(.wakeDetected(runActive: false))
        XCTAssertEqual(machine.handle(.disabled), [.stopTurnCapture])
        XCTAssertEqual(machine.state, .off)

        machine = makeReady(followUp: true)
        machine.handle(.runCompleted(speechWillPlay: false))
        XCTAssertEqual(machine.handle(.disabled), [.disarmFollowUpWindow])
        XCTAssertEqual(machine.state, .off)
    }

    // UX plan: follow-up window. Arms after Done when enabled; never when the
    // setting is off.
    func testFollowUpWindowArmsAfterDoneWhenEnabled() {
        var machine = makeReady(followUp: true)
        XCTAssertEqual(machine.handle(.runCompleted(speechWillPlay: false)), [.armFollowUpWindow])
        XCTAssertEqual(machine.state, .followUpWindow)

        var disabled = makeReady(followUp: false)
        XCTAssertEqual(disabled.handle(.runCompleted(speechWillPlay: false)), [])
        XCTAssertEqual(disabled.state, .ready)
    }

    // UX plan: follow-up window self-capture guard. With speech playing, the
    // window arms only when playback ends.
    func testFollowUpWindowWaitsForSpeechPlayback() {
        var machine = makeReady(followUp: true)
        XCTAssertEqual(machine.handle(.runCompleted(speechWillPlay: true)), [])
        XCTAssertEqual(machine.state, .ready)
        XCTAssertEqual(machine.handle(.speechPlaybackEnded), [.armFollowUpWindow])
        XCTAssertEqual(machine.state, .followUpWindow)
    }

    // UX plan: follow-up window never opens after Stopped or a failure.
    func testFollowUpWindowNeverArmsAfterStopOrFailure() {
        var machine = makeReady(followUp: true)
        XCTAssertEqual(machine.handle(.runStoppedOrFailed), [])
        XCTAssertEqual(machine.state, .ready)
    }

    // UX plan: follow-up speech starts a turn without a wake phrase.
    func testFollowUpSpeechSubmitsAsFollowUpTurn() {
        var machine = makeReady(followUp: true)
        machine.handle(.runCompleted(speechWillPlay: false))
        let effects = machine.handle(.speechEnded)
        XCTAssertEqual(effects, [.stopTurnCapture, .transcribeAndSubmit(.followUp)])
        XCTAssertEqual(machine.state, .transcribing(.followUp))
    }

    // A wake phrase inside the window behaves like a normal wake-up.
    func testWakeInsideFollowUpWindowDisarmsAndListens() {
        var machine = makeReady(followUp: true)
        machine.handle(.runCompleted(speechWillPlay: false))
        let effects = machine.handle(.wakeDetected(runActive: false))
        XCTAssertEqual(effects, [.disarmFollowUpWindow, .playWakeCue, .startTurnCapture(.initial)])
        XCTAssertEqual(machine.state, .listening(.initial))
    }

    func testFollowUpWindowExpiryReturnsToReady() {
        var machine = makeReady(followUp: true)
        machine.handle(.runCompleted(speechWillPlay: false))
        XCTAssertEqual(machine.handle(.followUpWindowExpired), [.disarmFollowUpWindow])
        XCTAssertEqual(machine.state, .ready)
    }
}
