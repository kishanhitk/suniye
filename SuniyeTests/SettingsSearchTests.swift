import XCTest
@testable import Suniye

final class SettingsSearchTests: XCTestCase {
    private func search(_ query: String, info: (SettingsRowID) -> String? = { $0.info }) -> [SettingsRowID] {
        SettingsSearch.results(for: query, in: SettingsRowID.allCases, info: info)
    }

    /// A title match ranks above an alias match; ties keep catalog order.
    func testTitleMatchesRankFirstInCatalogOrder() {
        let results = search("model")

        XCTAssertEqual(Array(results.prefix(3)), [.speechModel, .transcriptModel, .summaryModel])
        guard let engine = results.firstIndex(of: .magicFormatEngine),
              let summary = results.firstIndex(of: .summaryModel) else {
            return XCTFail("the engine row has the alias \"model\"")
        }
        XCTAssertGreaterThan(engine, summary)
    }

    /// The words people type find rows whose titles do not contain them.
    func testAliasFindsRowsWhoseTitlesLackTheWord() {
        XCTAssertEqual(search("hotkey"), [.holdToDictate, .pasteLastTranscript, .holdToEditSelection])
        XCTAssertTrue(search("dark mode").contains(.theme))
        XCTAssertTrue(search("enter").contains(.pressEnterAfterPasting))
    }

    /// Every word of the query must match somewhere in the row.
    func testEveryWordMustMatch() {
        XCTAssertEqual(search("echo bluetooth"), [.echoCancellation])
        XCTAssertEqual(search("echo zebra"), [])
    }

    /// A hint is searched only for words of three letters or more, so short
    /// fragments do not match inside sentences.
    func testHintMatchesNeedThreeLetters() {
        XCTAssertTrue(search("rou").contains(.echoCancellation), "the hint says \"route\"")
        XCTAssertFalse(search("ro").contains(.echoCancellation))
    }

    func testMatchingIgnoresCaseAndAccents() {
        XCTAssertTrue(search("ÉCHO").contains(.echoCancellation))
    }

    /// The hint the row shows right now is what search reads.
    func testSearchReadsTheCurrentHint() {
        let rows: [SettingsRowID] = [.liveTranscriptionPreview]
        XCTAssertEqual(
            SettingsSearch.results(for: "apple", in: rows, info: { _ in "Not available with Apple Speech." }),
            [.liveTranscriptionPreview]
        )
        XCTAssertEqual(SettingsSearch.results(for: "apple", in: rows, info: { _ in nil }), [])
    }

    /// A model name shown on screen finds the rows that choose a model.
    func testModelNamesFindTheModelRows() {
        let results = search("Apple Speech")
        XCTAssertTrue(results.contains(.speechModel))
        XCTAssertTrue(results.contains(.transcriptModel))
        XCTAssertFalse(results.contains(.magicFormatEngine), "\"speech\" is not an engine word")
    }

    func testBlankQueryFindsNothing() {
        XCTAssertEqual(search("   "), [])
    }

    func testEmphasisCoversTheMatchedStartOfEachWord() {
        let title = SettingsSearch.emphasized("Transcript model", query: "mod")
        let bold = title.runs
            .filter { $0.inlinePresentationIntent == .stronglyEmphasized }
            .map { String(title[$0.range].characters) }

        XCTAssertEqual(bold, ["mod"])
    }

    /// Every row names a pane that Settings lists, or the Magic Format page.
    func testEveryRowHasATitleAndAPlace() {
        for row in SettingsRowID.allCases {
            XCTAssertFalse(row.title.isEmpty, "\(row)")
            if case let .pane(pane) = row.place {
                XCTAssertTrue(SettingsPane.allCases.contains(pane), "\(row)")
            }
        }
    }

    func testPermissionsPaneIsListedOnlyWhileAGrantIsMissing() {
        XCTAssertEqual(SettingsPane.listed(permissionsMissing: true).first, .permissions)
        XCTAssertFalse(SettingsPane.listed(permissionsMissing: false).contains(.permissions))
        XCTAssertEqual(SettingsPane.listed(permissionsMissing: false).count, SettingsPane.allCases.count - 1)
    }
}
