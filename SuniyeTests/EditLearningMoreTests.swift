import XCTest
@testable import Suniye

final class EditLearningMoreTests: XCTestCase {
    func testReplacementContainingDigitsIsProperNounLike() {
        // Even when the replacement is a known "word", digits mark it as a
        // learnable identifier-style term.
        let terms = CorrectionClassifier.learnableTerms(
            from: [WordSubstitution(original: "gptfour", replacement: "GPT4")],
            existingVocabulary: [],
            isKnownWord: { _ in true }
        )

        XCTAssertEqual(terms, ["GPT4"])
    }

    func testPhoneticSimilarityOfLetterlessTokensComparesLiterally() {
        XCTAssertEqual(CorrectionClassifier.phoneticSimilarity("123", "123"), 1.0)
        XCTAssertEqual(CorrectionClassifier.phoneticSimilarity("42", "7"), 0.0)
    }
}
