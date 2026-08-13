import XCTest
@testable import Suniye

/// Timing rules for turn-end detection (UX plan: state 3, acceptance
/// criterion 3 — no button, no fixed pause ritual).
final class VoiceTurnEndpointerTests: XCTestCase {
    private var endpointer = VoiceTurnEndpointer()

    override func setUp() {
        super.setUp()
        endpointer = VoiceTurnEndpointer()
        endpointer.begin(at: 0)
    }

    /// Feeds frames every 20 ms over a span, marking speech inside the ranges.
    private func run(until end: TimeInterval, speech: [ClosedRange<TimeInterval>]) -> VoiceTurnEndpointer.Verdict {
        var verdict = VoiceTurnEndpointer.Verdict.waiting
        var t: TimeInterval = 0
        while t <= end {
            let isSpeech = speech.contains { $0.contains(t) }
            verdict = endpointer.process(isSpeech: isSpeech, at: t)
            switch verdict {
            case .turnEnded, .noSpeechTimeout, .maxTurnReached:
                return verdict
            case .waiting, .speaking:
                break
            }
            t += 0.02
        }
        return verdict
    }

    func testNormalTurnEndsAfterTrailingSilence() {
        let verdict = run(until: 5, speech: [0.2...2.0])
        guard case .turnEnded(let duration) = verdict else {
            return XCTFail("expected turnEnded, got \(verdict)")
        }
        XCTAssertEqual(duration, 1.8, accuracy: 0.05)
    }

    func testMidThoughtPauseShorterThanWindowDoesNotEndTurn() {
        // 0.5 s pause inside speech: below the 0.9 s trailing window.
        let verdict = run(until: 6, speech: [0.2...1.5, 2.0...3.0])
        guard case .turnEnded(let duration) = verdict else {
            return XCTFail("expected turnEnded, got \(verdict)")
        }
        // Turn spans both segments.
        XCTAssertEqual(duration, 2.8, accuracy: 0.05)
    }

    func testSilenceAfterWakeTimesOut() {
        XCTAssertEqual(run(until: 6, speech: []), .noSpeechTimeout)
    }

    func testShortNoiseBurstDoesNotBecomeATurn() {
        // 150 ms blip is under minimumSpeechSeconds; window then times out.
        XCTAssertEqual(run(until: 6, speech: [1.0...1.15]), .noSpeechTimeout)
    }

    func testNoiseBurstThenRealSpeechStillEndsAsTurn() {
        let verdict = run(until: 8, speech: [0.5...0.65, 2.0...4.0])
        guard case .turnEnded(let duration) = verdict else {
            return XCTFail("expected turnEnded, got \(verdict)")
        }
        XCTAssertEqual(duration, 2.0, accuracy: 0.05)
    }

    func testMaxTurnCapFiresWhileStillSpeaking() {
        let verdict = run(until: 35, speech: [0.1...34.0])
        guard case .maxTurnReached(let duration) = verdict else {
            return XCTFail("expected maxTurnReached, got \(verdict)")
        }
        XCTAssertEqual(duration, 30, accuracy: 0.1)
    }

    func testProcessBeforeBeginIsInert() {
        var fresh = VoiceTurnEndpointer()
        XCTAssertEqual(fresh.process(isSpeech: true, at: 1), .waiting)
    }

    func testBeginResetsPriorState() {
        _ = run(until: 5, speech: [0.2...2.0])
        endpointer.begin(at: 100)
        XCTAssertEqual(endpointer.process(isSpeech: false, at: 100.5), .waiting)
    }
}
