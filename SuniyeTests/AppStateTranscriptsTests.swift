import AppKit
import Carbon
import SuniyeAnalytics
import XCTest
@testable import Suniye

@MainActor
final class AppStateTranscriptsTests: XCTestCase {
    func testHistoryLoadSeedsDurableStats() {
        let historyStore = TestHistoryStore()
        historyStore.value = [
            RecentResult(id: UUID(), text: "hello world", createdAt: .now, durationSeconds: 1.5, wasLLMPolished: false),
            RecentResult(id: UUID(), text: "second test clip", createdAt: .now.addingTimeInterval(-60), durationSeconds: 2.5, wasLLMPolished: true)
        ]

        let appState = makeTestAppState(historyStore: historyStore)

        XCTAssertEqual(appState.dictationStats.lifetimeSessions, 2)
        XCTAssertEqual(appState.dictationStats.lifetimeWords, 5)
        XCTAssertEqual(appState.dictationStats.lifetimeSeconds, 4.0, accuracy: 0.001)
    }

    /// Stats are a durable record, not a view over history: removing a transcript
    /// (a privacy action) must not rewrite what the user already did.
    func testDeleteRecentResultLeavesDurableStatsIntact() {
        let first = RecentResult(id: UUID(), text: "hello world", createdAt: .now, durationSeconds: 1.5, wasLLMPolished: false)
        let second = RecentResult(id: UUID(), text: "second test clip", createdAt: .now.addingTimeInterval(-60), durationSeconds: 2.5, wasLLMPolished: true)
        let historyStore = TestHistoryStore()
        historyStore.value = [first, second]

        let appState = makeTestAppState(historyStore: historyStore)
        appState.library.delete(first)

        XCTAssertEqual(appState.recentResults.count, 1)
        XCTAssertEqual(appState.dictationStats.lifetimeSessions, 2)
        XCTAssertEqual(appState.dictationStats.lifetimeWords, 5)
        XCTAssertEqual(historyStore.value.map(\.id), [second.id])
    }

    func testCopyLastTranscriptCopiesNewestHistoryResult() {
        let first = RecentResult(id: UUID(), text: "latest transcript", createdAt: .now, durationSeconds: 1.5, wasLLMPolished: false)
        let second = RecentResult(id: UUID(), text: "older transcript", createdAt: .now.addingTimeInterval(-60), durationSeconds: 2.5, wasLLMPolished: true)
        let historyStore = TestHistoryStore()
        historyStore.value = [first, second]
        let insertion = SpyTextInsertionService()

        let appState = makeTestAppState(textInsertionService: insertion, historyStore: historyStore)
        let didCopy = appState.copyLastTranscript()

        XCTAssertTrue(didCopy)
        XCTAssertEqual(insertion.copiedTexts, ["latest transcript"])
    }

    func testCopyLastTranscriptReturnsFalseWhenHistoryIsEmpty() {
        let insertion = SpyTextInsertionService()
        let appState = makeTestAppState(textInsertionService: insertion)

        let didCopy = appState.copyLastTranscript()

        XCTAssertFalse(didCopy)
        XCTAssertEqual(insertion.copiedTexts, [])
    }

    func testPasteLastTranscriptWorksWhileBusyWithoutChangingHistoryOrSubmitting() async {
        let result = RecentResult(
            id: UUID(),
            text: "latest transcript",
            createdAt: .now,
            durationSeconds: 1.5,
            wasLLMPolished: false
        )
        let historyStore = TestHistoryStore()
        historyStore.value = [result]
        let textInsertionService = SpyTextInsertionService()
        let appState = makeTestAppState(
            textInsertionService: textInsertionService,
            historyStore: historyStore
        )

        appState.phase = .recording
        let didPasteWhileRecording = await appState.pasteLastTranscript()
        XCTAssertTrue(didPasteWhileRecording)
        appState.phase = .transcribing
        let didPasteWhileTranscribing = await appState.pasteLastTranscript()
        XCTAssertTrue(didPasteWhileTranscribing)

        XCTAssertEqual(textInsertionService.insertedTexts, ["latest transcript", "latest transcript"])
        XCTAssertEqual(textInsertionService.submitCallCount, 0)
        XCTAssertEqual(appState.recentResults, [result])
        XCTAssertEqual(appState.phase, .transcribing)
    }

    func testPasteLastTranscriptSilentlyReturnsFalseWhenHistoryIsEmpty() async {
        let textInsertionService = SpyTextInsertionService()
        let appState = makeTestAppState(textInsertionService: textInsertionService)

        let didPaste = await appState.pasteLastTranscript()
        XCTAssertFalse(didPaste)
        XCTAssertTrue(textInsertionService.attemptedTexts.isEmpty)
        XCTAssertNil(appState.lastError)
        XCTAssertEqual(appState.floatingIndicatorState, .idle)
    }

    func testPasteLastTranscriptSilentlyReturnsFalseWhenLatestHistoryTextIsEmpty() async {
        let historyStore = TestHistoryStore()
        historyStore.value = [
            RecentResult(id: UUID(), text: "", createdAt: .now, durationSeconds: 1, wasLLMPolished: false)
        ]
        let textInsertionService = SpyTextInsertionService()
        let appState = makeTestAppState(
            textInsertionService: textInsertionService,
            historyStore: historyStore
        )

        let didPaste = await appState.pasteLastTranscript()
        XCTAssertFalse(didPaste)
        XCTAssertTrue(textInsertionService.attemptedTexts.isEmpty)
        XCTAssertNil(appState.lastError)
        XCTAssertEqual(appState.floatingIndicatorState, .idle)
    }

    func testPasteLastTranscriptFailureUsesConfiguredShortcutInWarning() async {
        let historyStore = TestHistoryStore()
        historyStore.value = [
            RecentResult(id: UUID(), text: "latest transcript", createdAt: .now, durationSeconds: 1, wasLLMPolished: false)
        ]
        let textInsertionService = SpyTextInsertionService()
        textInsertionService.insertError = FakeError(message: "no focus")
        let appState = makeTestAppState(
            textInsertionService: textInsertionService,
            historyStore: historyStore
        )
        appState.updatePasteLastTranscriptHotkey(
            .keyCombo(keyCode: UInt32(kVK_ANSI_P), carbonModifiers: UInt32(controlKey | cmdKey))
        )

        let didPaste = await appState.pasteLastTranscript()
        XCTAssertFalse(didPaste)

        XCTAssertEqual(appState.lastError, "Couldn't insert text. Focus a text field, then press ⌃⌘P.")
        XCTAssertEqual(
            appState.floatingIndicatorState,
            .error(message: "Couldn't insert text. Focus a text field, then press ⌃⌘P.")
        )
    }

    func testOriginalTranscriptOpenAndCopyAreCounted() {
        let spy = SpyAnalytics()
        let insertion = SpyTextInsertionService()
        let appState = makeTestAppState(textInsertionService: insertion, analytics: spy)

        appState.originalTranscriptOpened()
        XCTAssertTrue(appState.copyOriginalTranscript("um so hello"))

        XCTAssertEqual(insertion.copiedTexts, ["um so hello"])
        let actions = spy.trackedEvents.compactMap { event -> RawTranscriptAction? in
            if case let .rawTranscript(action) = event { return action }
            return nil
        }
        XCTAssertEqual(actions, [.opened, .copied])
    }
}
