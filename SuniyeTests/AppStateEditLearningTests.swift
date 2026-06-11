import XCTest
@testable import Suniye

@MainActor
final class AppStateEditLearningTests: XCTestCase {
    private func runDictation(_ appState: AppState) async {
        appState.phase = .ready
        appState.hasMicPermission = true
        appState.hasAccessibilityPermission = true

        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)
        appState.toggleFloatingIndicatorRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)
    }

    private func makeDictationFixture(
        transcript: String = "Lunch with Keshawn at noon.",
        fieldValue: String? = "Lunch with Keshawn at noon."
    ) -> (AppState, SpyEditLearningService, SpyTextInsertionService) {
        let audioCapture = StubAudioCaptureService()
        audioCapture.stopCaptureResult = makeValidCapturedAudio()
        let transcriptionService = StubTranscriptionService()
        transcriptionService.transcribeResult = .success(transcript)
        let textInsertionService = SpyTextInsertionService()
        textInsertionService.fieldValueProvider = { fieldValue }
        let editLearningService = SpyEditLearningService()
        let appState = makeTestAppState(
            transcriptionService: transcriptionService,
            audioCaptureService: audioCapture,
            textInsertionService: textInsertionService,
            editLearningService: editLearningService
        )
        return (appState, editLearningService, textInsertionService)
    }

    func testDictationBeginsEditTrackingWithInsertedText() async {
        let (appState, editLearningService, _) = makeDictationFixture()

        await runDictation(appState)

        XCTAssertEqual(editLearningService.beganSessions.count, 1)
        let session = editLearningService.beganSessions[0]
        XCTAssertEqual(session.insertedText, "Lunch with Keshawn at noon.")
        XCTAssertEqual(session.fieldValueAfterInsertion, "Lunch with Keshawn at noon.")
        XCTAssertEqual(session.readCurrentFieldValue(), "Lunch with Keshawn at noon.")
    }

    func testDictationFinalizesPreviousSessionBeforeBeginningNewOne() async {
        let (appState, editLearningService, _) = makeDictationFixture()

        await runDictation(appState)

        XCTAssertEqual(editLearningService.events, [
            .finalize,
            .begin(insertedText: "Lunch with Keshawn at noon."),
        ])
    }

    func testDictationPassesCurrentVocabularyToSession() async {
        let (appState, editLearningService, _) = makeDictationFixture()
        appState.addVocabularyTerm("PostgreSQL")

        await runDictation(appState)

        XCTAssertEqual(editLearningService.beganSessions.first?.existingVocabulary, ["PostgreSQL"])
    }

    func testNoTrackingWhenLearnFromEditsDisabled() async {
        let (appState, editLearningService, _) = makeDictationFixture()
        appState.learnFromEditsEnabled = false

        await runDictation(appState)

        XCTAssertEqual(editLearningService.beganSessions.count, 0)
    }

    func testNoTrackingWhenFieldValueProviderUnavailable() async {
        let (appState, editLearningService, textInsertionService) = makeDictationFixture()
        textInsertionService.fieldValueProvider = nil

        await runDictation(appState)

        XCTAssertEqual(editLearningService.beganSessions.count, 0)
    }

    func testLearnedTermsEnterAutoLearnedVocabularyAndShowToast() {
        let editLearningService = SpyEditLearningService()
        let toastPresenter = SpyLearningToastPresenter()
        let settingsStore = TestLLMSettingsStore()
        let appState = makeTestAppState(
            llmSettingsStore: settingsStore,
            editLearningService: editLearningService,
            learningToastPresenter: toastPresenter
        )

        editLearningService.onLearnedTerms?(["Kishan"])

        XCTAssertTrue(appState.vocabularyTerms.contains("Kishan"))
        XCTAssertTrue(appState.isAutoLearnedVocabularyTerm("Kishan"))
        XCTAssertFalse(appState.isAutoLearnedVocabularyTerm("PostgreSQL"))
        XCTAssertEqual(toastPresenter.shownTermBatches, [["Kishan"]])
        XCTAssertEqual(settingsStore.latest.autoLearnedKeywordsRaw, "Kishan")
    }

    func testToastUndoRemovesLearnedTerms() {
        let editLearningService = SpyEditLearningService()
        let toastPresenter = SpyLearningToastPresenter()
        let appState = makeTestAppState(
            editLearningService: editLearningService,
            learningToastPresenter: toastPresenter
        )

        editLearningService.onLearnedTerms?(["Kishan"])
        toastPresenter.lastUndo?()

        XCTAssertFalse(appState.vocabularyTerms.contains("Kishan"))
        XCTAssertFalse(appState.isAutoLearnedVocabularyTerm("Kishan"))
    }

    func testLearnedTermAlreadyInUserVocabularyIsNotDuplicated() {
        let editLearningService = SpyEditLearningService()
        let toastPresenter = SpyLearningToastPresenter()
        let appState = makeTestAppState(
            editLearningService: editLearningService,
            learningToastPresenter: toastPresenter
        )
        appState.addVocabularyTerm("Kishan")

        editLearningService.onLearnedTerms?(["kishan"])

        XCTAssertEqual(appState.vocabularyTerms.filter { $0.caseInsensitiveCompare("Kishan") == .orderedSame }.count, 1)
        XCTAssertFalse(appState.isAutoLearnedVocabularyTerm("Kishan"))
        XCTAssertEqual(toastPresenter.shownTermBatches, [])
    }

    func testRemoveVocabularyTermAlsoRemovesAutoLearnedEntry() {
        let editLearningService = SpyEditLearningService()
        let appState = makeTestAppState(
            editLearningService: editLearningService,
            learningToastPresenter: SpyLearningToastPresenter()
        )

        editLearningService.onLearnedTerms?(["Kishan"])
        appState.removeVocabularyTerm("Kishan")

        XCTAssertFalse(appState.vocabularyTerms.contains("Kishan"))
        XCTAssertFalse(appState.isAutoLearnedVocabularyTerm("Kishan"))
    }

    func testLearnFromEditsToggleAndLearnedTermsPersistAcrossRestart() {
        let settingsStore = TestLLMSettingsStore()
        let editLearningService = SpyEditLearningService()
        let appState = makeTestAppState(
            llmSettingsStore: settingsStore,
            editLearningService: editLearningService,
            learningToastPresenter: SpyLearningToastPresenter()
        )
        appState.learnFromEditsEnabled = false
        editLearningService.onLearnedTerms?(["Kishan"])

        let restored = makeTestAppState(llmSettingsStore: settingsStore)

        XCTAssertFalse(restored.learnFromEditsEnabled)
        XCTAssertTrue(restored.isAutoLearnedVocabularyTerm("Kishan"))
        XCTAssertTrue(restored.vocabularyTerms.contains("Kishan"))
    }
}

final class LLMSettingsEditLearningTests: XCTestCase {
    func testKeywordsMergeUserAndAutoLearnedWithUserCasingWinning() {
        let settings = LLMSettings(
            keywordsRaw: "PostgreSQL\nKishan",
            autoLearnedKeywordsRaw: "kishan\nAnanya"
        )

        XCTAssertEqual(settings.keywords, ["PostgreSQL", "Kishan", "Ananya"])
        XCTAssertEqual(settings.autoLearnedKeywords, ["kishan", "Ananya"])
    }

    func testCodableRoundTripPreservesEditLearningFields() throws {
        var settings = LLMSettings()
        settings.autoLearnedKeywordsRaw = "Kishan\nAnanya"
        settings.learnFromEditsEnabled = false

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(LLMSettings.self, from: data)

        XCTAssertEqual(decoded.autoLearnedKeywordsRaw, "Kishan\nAnanya")
        XCTAssertFalse(decoded.learnFromEditsEnabled)
    }

    func testDecodingLegacyPayloadDefaultsEditLearningFields() throws {
        let decoded = try JSONDecoder().decode(LLMSettings.self, from: Data("{}".utf8))

        XCTAssertEqual(decoded.autoLearnedKeywordsRaw, "")
        XCTAssertTrue(decoded.learnFromEditsEnabled)
    }
}
