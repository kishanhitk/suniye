import XCTest
@testable import Suniye

final class TranscriptionEditDiffTests: XCTestCase {
    func testNoEditsProducesNoSubstitutions() {
        let inserted = "Lunch with Keshawn at noon."
        let baseline = "Hi team. Lunch with Keshawn at noon."

        let substitutions = TranscriptionEditDiff.substitutions(
            insertedText: inserted,
            baseline: baseline,
            current: baseline
        )

        XCTAssertEqual(substitutions, [])
    }

    func testSingleWordEditYieldsSubstitution() {
        let inserted = "Lunch with Keshawn at noon."
        let baseline = "Hi team. Lunch with Keshawn at noon."
        let current = "Hi team. Lunch with Kishan at noon."

        let substitutions = TranscriptionEditDiff.substitutions(
            insertedText: inserted,
            baseline: baseline,
            current: current
        )

        XCTAssertEqual(substitutions, [WordSubstitution(original: "Keshawn", replacement: "Kishan")])
    }

    func testEditOutsideInsertedTextIsIgnored() {
        let inserted = "Lunch with Keshawn at noon."
        let baseline = "Hi everyone. Lunch with Keshawn at noon."
        let current = "Hi folks. Lunch with Keshawn at noon."

        let substitutions = TranscriptionEditDiff.substitutions(
            insertedText: inserted,
            baseline: baseline,
            current: current
        )

        XCTAssertEqual(substitutions, [])
    }

    func testPureInsertionYieldsNoSubstitutions() {
        let inserted = "Ship the build tomorrow."
        let baseline = "Ship the build tomorrow."
        let current = "Ship the new build tomorrow morning."

        let substitutions = TranscriptionEditDiff.substitutions(
            insertedText: inserted,
            baseline: baseline,
            current: current
        )

        XCTAssertEqual(substitutions, [])
    }

    func testDeletionYieldsNoSubstitutions() {
        let inserted = "Ship the build tomorrow."
        let baseline = "Ship the build tomorrow."
        let current = "Ship the build."

        let substitutions = TranscriptionEditDiff.substitutions(
            insertedText: inserted,
            baseline: baseline,
            current: current
        )

        XCTAssertEqual(substitutions, [])
    }

    func testClearedFieldYieldsNoSubstitutions() {
        let inserted = "Lunch with Keshawn at noon."
        let baseline = "Lunch with Keshawn at noon."

        let substitutions = TranscriptionEditDiff.substitutions(
            insertedText: inserted,
            baseline: baseline,
            current: ""
        )

        XCTAssertEqual(substitutions, [])
    }

    func testMultipleEditsYieldMultipleSubstitutions() {
        let inserted = "Ping Keshawn and Anya about the demo."
        let baseline = "Ping Keshawn and Anya about the demo."
        let current = "Ping Kishan and Ananya about the demo."

        let substitutions = TranscriptionEditDiff.substitutions(
            insertedText: inserted,
            baseline: baseline,
            current: current
        )

        XCTAssertEqual(substitutions, [
            WordSubstitution(original: "Keshawn", replacement: "Kishan"),
            WordSubstitution(original: "Anya", replacement: "Ananya"),
        ])
    }

    func testSubstitutionDetectedEvenWhenSurroundingTextAdded() {
        let inserted = "Lunch with Keshawn at noon."
        let baseline = "Lunch with Keshawn at noon."
        let current = "Quick note: Lunch with Kishan at noon. Thanks!"

        let substitutions = TranscriptionEditDiff.substitutions(
            insertedText: inserted,
            baseline: baseline,
            current: current
        )

        XCTAssertEqual(substitutions, [WordSubstitution(original: "Keshawn", replacement: "Kishan")])
    }
}

final class PhoneticSimilarityTests: XCTestCase {
    func testMisrecognizedNameIsSimilar() {
        XCTAssertGreaterThanOrEqual(CorrectionClassifier.phoneticSimilarity("Keshawn", "Kishan"), 0.6)
    }

    func testAcronymSpellingIsSimilar() {
        XCTAssertGreaterThanOrEqual(CorrectionClassifier.phoneticSimilarity("Jason", "JSON"), 0.6)
    }

    func testUnrelatedWordsAreDissimilar() {
        XCTAssertLessThan(CorrectionClassifier.phoneticSimilarity("lunch", "dinner"), 0.6)
    }

    func testIdenticalWordsAreFullySimilar() {
        XCTAssertEqual(CorrectionClassifier.phoneticSimilarity("Suniye", "Suniye"), 1.0)
    }
}

final class CorrectionClassifierTests: XCTestCase {
    private func learnable(
        _ substitutions: [WordSubstitution],
        vocabulary: [String] = [],
        knownWords: Set<String> = ["their", "there", "the", "lunch", "dinner", "john", "smith"]
    ) -> [String] {
        CorrectionClassifier.learnableTerms(
            from: substitutions,
            existingVocabulary: vocabulary,
            isKnownWord: { knownWords.contains($0.lowercased()) }
        )
    }

    func testLearnsCorrectedProperNoun() {
        let terms = learnable([WordSubstitution(original: "Keshawn", replacement: "Kishan")])
        XCTAssertEqual(terms, ["Kishan"])
    }

    func testRejectsCommonWordCorrection() {
        let terms = learnable([WordSubstitution(original: "their", replacement: "there")])
        XCTAssertEqual(terms, [])
    }

    func testRejectsContentChangeDespiteCapitalization() {
        let terms = learnable([WordSubstitution(original: "Lunch", replacement: "Dinner")])
        XCTAssertEqual(terms, [])
    }

    func testRejectsCaseOnlyChangeOfKnownWord() {
        let terms = learnable([WordSubstitution(original: "the", replacement: "The")])
        XCTAssertEqual(terms, [])
    }

    func testLearnsCaseOnlyChangeOfUnknownWord() {
        let terms = learnable([WordSubstitution(original: "kishan", replacement: "Kishan")])
        XCTAssertEqual(terms, ["Kishan"])
    }

    func testLearnsAcronymCorrection() {
        let terms = learnable([WordSubstitution(original: "Jason", replacement: "JSON")])
        XCTAssertEqual(terms, ["JSON"])
    }

    func testRejectsShortReplacements() {
        let terms = learnable([WordSubstitution(original: "al", replacement: "Al")])
        XCTAssertEqual(terms, [])
    }

    func testRejectsTermsAlreadyInVocabulary() {
        let terms = learnable(
            [WordSubstitution(original: "Keshawn", replacement: "Kishan")],
            vocabulary: ["kishan"]
        )
        XCTAssertEqual(terms, [])
    }

    func testCapsResultsAtThreeTerms() {
        let substitutions = [
            WordSubstitution(original: "Keshawn", replacement: "Kishan"),
            WordSubstitution(original: "Anya", replacement: "Ananya"),
            WordSubstitution(original: "Suniya", replacement: "Suniye"),
            WordSubstitution(original: "Parakeet", replacement: "Parakeetz"),
        ]
        let terms = learnable(substitutions)
        XCTAssertEqual(terms.count, 3)
        XCTAssertEqual(terms, ["Kishan", "Ananya", "Suniye"])
    }

    func testDeduplicatesRepeatedCorrections() {
        let substitutions = [
            WordSubstitution(original: "Keshawn", replacement: "Kishan"),
            WordSubstitution(original: "keshawn", replacement: "Kishan"),
        ]
        let terms = learnable(substitutions)
        XCTAssertEqual(terms, ["Kishan"])
    }
}
