import XCTest
@testable import Suniye

final class MainWindowDestinationTests: XCTestCase {
    func testLaunchArgumentsRouteToExpectedSections() {
        XCTAssertEqual(MainWindowDestination.initial(arguments: ["Suniye", "--open-dashboard"]), .section(.dashboard))
        XCTAssertEqual(MainWindowDestination.initial(arguments: ["Suniye", "--open-meetings"]), .section(.meetings))
        XCTAssertEqual(MainWindowDestination.initial(arguments: ["Suniye", "--open-style"]), .section(.style))
        XCTAssertEqual(MainWindowDestination.initial(arguments: ["Suniye", "--open-settings"]), .settings())
    }

    func testPaneArgumentsOpenTheirSettingsPane() {
        XCTAssertEqual(MainWindowDestination.initial(arguments: ["Suniye", "--open-settings-speechModel"]), .settings(.speechModel))
        XCTAssertEqual(MainWindowDestination.initial(arguments: ["Suniye", "--open-settings-general"]), .settings(.general))
    }

    /// A row opens the page that holds it: its Settings pane, or Magic Format.
    func testRowsOpenThePlaceThatHoldsThem() {
        XCTAssertEqual(MainWindowDestination.row(.holdToDictate).section, .settings)
        XCTAssertEqual(MainWindowDestination.row(.holdToDictate).pane, .shortcuts)
        XCTAssertEqual(MainWindowDestination.row(.vocabulary).section, .style)
        XCTAssertNil(MainWindowDestination.row(.vocabulary).pane)
    }

    /// History merged into Transcripts; the old argument must keep working.
    func testOpenHistoryAliasRoutesToTranscripts() {
        XCTAssertEqual(MainWindowDestination.initial(arguments: ["Suniye", "--open-history"]), .section(.dashboard))
    }

    func testVocabularyAndLLMCompatibilityAliasesRouteToStyle() {
        XCTAssertEqual(MainWindowDestination.initial(arguments: ["Suniye", "--open-vocabulary"]), .section(.style))
        XCTAssertEqual(MainWindowDestination.initial(arguments: ["Suniye", "--open-llm"]), .section(.style))
    }

    func testDefaultSelectionIsDashboard() {
        XCTAssertEqual(MainWindowDestination.initial(arguments: ["Suniye"]), .section(.dashboard))
    }
}
