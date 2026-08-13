import Carbon
import XCTest

@testable import Suniye

final class HotkeySlotAssignmentsTests: XCTestCase {
    private let comboA = HotkeyConfiguration.keyCombo(keyCode: UInt32(kVK_ANSI_A), carbonModifiers: UInt32(optionKey))
    private let comboB = HotkeyConfiguration.keyCombo(keyCode: UInt32(kVK_ANSI_B), carbonModifiers: UInt32(controlKey))
    private let comboC = HotkeyConfiguration.keyCombo(keyCode: UInt32(kVK_ANSI_C), carbonModifiers: UInt32(cmdKey))
    private let comboD = HotkeyConfiguration.keyCombo(keyCode: UInt32(kVK_ANSI_D), carbonModifiers: UInt32(controlKey | cmdKey))
    private let unmodified = HotkeyConfiguration.keyCombo(keyCode: UInt32(kVK_ANSI_E), carbonModifiers: 0)

    private func makeAssignments() -> HotkeySlotAssignments {
        HotkeySlotAssignments(
            dictation: .globe,
            pasteLastTranscript: comboA,
            editMode: comboB,
            computerUse: comboC
        )
    }

    // MARK: Dictation

    func testDictationClearsCollidingOptionalSlots() {
        var assignments = makeAssignments()
        let outcome = assignments.assign(comboB, to: .dictation)
        XCTAssertEqual(outcome, .applied(cleared: [.editMode]))
        XCTAssertEqual(assignments.dictation, comboB)
        XCTAssertNil(assignments.editMode)
        XCTAssertEqual(assignments.computerUse, comboC)
    }

    func testDictationClearsBothOptionalSlotsWhenBothCollide() {
        var assignments = makeAssignments()
        assignments.editMode = comboD
        assignments.computerUse = comboD
        XCTAssertEqual(assignments.assign(comboD, to: .dictation), .applied(cleared: [.editMode, .computerUse]))
        XCTAssertNil(assignments.editMode)
        XCTAssertNil(assignments.computerUse)
    }

    func testDictationRejectedWhenMatchingPaste() {
        var assignments = makeAssignments()
        let outcome = assignments.assign(comboA, to: .dictation)
        XCTAssertEqual(outcome, .rejected(.collision(.pasteLastTranscript)))
        XCTAssertEqual(assignments, makeAssignments())
    }

    // MARK: Paste Last Transcript

    func testPasteRequiresModifiedKeyCombo() {
        var assignments = makeAssignments()
        XCTAssertEqual(assignments.assign(unmodified, to: .pasteLastTranscript), .rejected(.missingModifier))
        XCTAssertEqual(assignments, makeAssignments())
    }

    func testPasteRejectedAgainstEverySlot() {
        var assignments = makeAssignments()
        assignments.dictation = comboD
        XCTAssertEqual(assignments.assign(comboD, to: .pasteLastTranscript), .rejected(.collision(.dictation)))
        XCTAssertEqual(assignments.assign(comboB, to: .pasteLastTranscript), .rejected(.collision(.editMode)))
        XCTAssertEqual(assignments.assign(comboC, to: .pasteLastTranscript), .rejected(.collision(.computerUse)))
        XCTAssertEqual(assignments.pasteLastTranscript, comboA)
    }

    // MARK: Edit Mode and Computer Use

    func testOptionalSlotsRejectAllCollisions() {
        var assignments = makeAssignments()
        assignments.dictation = comboD
        XCTAssertEqual(assignments.assign(comboD, to: .editMode), .rejected(.collision(.dictation)))
        XCTAssertEqual(assignments.assign(comboA, to: .editMode), .rejected(.collision(.pasteLastTranscript)))
        XCTAssertEqual(assignments.assign(comboC, to: .editMode), .rejected(.collision(.computerUse)))
        XCTAssertEqual(assignments.assign(comboD, to: .computerUse), .rejected(.collision(.dictation)))
        XCTAssertEqual(assignments.assign(comboA, to: .computerUse), .rejected(.collision(.pasteLastTranscript)))
        XCTAssertEqual(assignments.assign(comboB, to: .computerUse), .rejected(.collision(.editMode)))
    }

    func testOptionalSlotsAcceptNilAndDistinctCombos() {
        var assignments = makeAssignments()
        XCTAssertEqual(assignments.assign(nil, to: .editMode), .applied(cleared: []))
        XCTAssertNil(assignments.editMode)
        XCTAssertEqual(assignments.assign(comboD, to: .computerUse), .applied(cleared: []))
        XCTAssertEqual(assignments.computerUse, comboD)
    }

    // MARK: Normalization

    func testNormalizedKeepsValidAssignments() {
        let (normalized, changed) = HotkeySlotAssignments.normalized(
            dictation: .globe,
            pasteLastTranscript: comboA,
            editMode: comboB,
            computerUse: comboC,
            pasteFallbacks: [comboD]
        )
        XCTAssertEqual(normalized, makeAssignments())
        XCTAssertTrue(changed.isEmpty)
    }

    func testNormalizedWalksPasteFallbackLadder() {
        let (normalized, changed) = HotkeySlotAssignments.normalized(
            dictation: comboA,
            pasteLastTranscript: comboA,
            editMode: nil,
            computerUse: nil,
            pasteFallbacks: [comboD]
        )
        XCTAssertEqual(normalized.pasteLastTranscript, comboD)
        XCTAssertEqual(changed, [.pasteLastTranscript])
    }

    func testNormalizedFallsBackToDefaultPasteWhenLadderExhausted() {
        let (normalized, _) = HotkeySlotAssignments.normalized(
            dictation: comboA,
            pasteLastTranscript: comboA,
            editMode: nil,
            computerUse: nil,
            pasteFallbacks: []
        )
        XCTAssertEqual(normalized.pasteLastTranscript, .pasteLastTranscriptDefault)
    }

    func testNormalizedClearsCollidingOptionalSlots() {
        let (normalized, changed) = HotkeySlotAssignments.normalized(
            dictation: comboB,
            pasteLastTranscript: comboA,
            editMode: comboB,
            computerUse: comboA,
            pasteFallbacks: []
        )
        XCTAssertNil(normalized.editMode)
        XCTAssertNil(normalized.computerUse)
        XCTAssertEqual(changed, [.editMode, .computerUse])
    }

    func testNormalizedClearsComputerUseCollidingWithNormalizedEditMode() {
        let (normalized, changed) = HotkeySlotAssignments.normalized(
            dictation: .globe,
            pasteLastTranscript: comboA,
            editMode: comboB,
            computerUse: comboB,
            pasteFallbacks: []
        )
        XCTAssertEqual(normalized.editMode, comboB)
        XCTAssertNil(normalized.computerUse)
        XCTAssertEqual(changed, [.computerUse])
    }

    // MARK: Voice Activation toggle (slot 5)

    func testVoiceActivationToggleAcceptsDistinctComboAndNil() {
        var assignments = makeAssignments()
        XCTAssertEqual(assignments.assign(comboD, to: .voiceActivationToggle), .applied(cleared: []))
        XCTAssertEqual(assignments.voiceActivationToggle, comboD)
        XCTAssertEqual(assignments.assign(nil, to: .voiceActivationToggle), .applied(cleared: []))
        XCTAssertNil(assignments.voiceActivationToggle)
    }

    func testVoiceActivationToggleRejectedOnCollision() {
        var assignments = makeAssignments()
        let outcome = assignments.assign(comboC, to: .voiceActivationToggle)
        XCTAssertEqual(outcome, .rejected(.collision(.computerUse)))
        XCTAssertNil(assignments.voiceActivationToggle)
    }

    func testDictationClearsCollidingVoiceActivationToggle() {
        var assignments = makeAssignments()
        assignments.voiceActivationToggle = comboD
        let outcome = assignments.assign(comboD, to: .dictation)
        XCTAssertEqual(outcome, .applied(cleared: [.voiceActivationToggle]))
        XCTAssertNil(assignments.voiceActivationToggle)
    }

    func testNormalizedClearsCollidingVoiceActivationToggle() {
        let (normalized, changed) = HotkeySlotAssignments.normalized(
            dictation: .globe,
            pasteLastTranscript: comboA,
            editMode: comboB,
            computerUse: comboC,
            voiceActivationToggle: comboC,
            pasteFallbacks: []
        )
        XCTAssertNil(normalized.voiceActivationToggle)
        XCTAssertEqual(changed, [.voiceActivationToggle])
    }

    func testNormalizedKeepsDistinctVoiceActivationToggle() {
        let (normalized, changed) = HotkeySlotAssignments.normalized(
            dictation: .globe,
            pasteLastTranscript: comboA,
            editMode: comboB,
            computerUse: comboC,
            voiceActivationToggle: comboD,
            pasteFallbacks: []
        )
        XCTAssertEqual(normalized.voiceActivationToggle, comboD)
        XCTAssertTrue(changed.isEmpty)
    }
}
