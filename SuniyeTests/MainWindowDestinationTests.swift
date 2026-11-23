import XCTest
@testable import Suniye

final class MainWindowDestinationTests: XCTestCase {
    func testLaunchArgumentsRouteToExpectedSections() {
        XCTAssertEqual(MainWindowDestination.initial(arguments: ["Suniye", "--open-dashboard"]), .section(.dashboard))
        XCTAssertEqual(MainWindowDestination.initial(arguments: ["Suniye", "--open-meetings"]), .section(.meetings))
        XCTAssertEqual(MainWindowDestination.initial(arguments: ["Suniye", "--open-style"]), .section(.style))
        XCTAssertEqual(MainWindowDestination.initial(arguments: ["Suniye", "--open-settings"]), .settings())
    }

    /// Speech Model and General were sections before they became Settings
    /// panes; scripts still pass their arguments.
    func testFormerSectionArgumentsOpenTheirPanes() {
        XCTAssertEqual(MainWindowDestination.initial(arguments: ["Suniye", "--open-model"]), .settings(.speechModel))
        XCTAssertEqual(MainWindowDestination.initial(arguments: ["Suniye", "--open-general"]), .settings(.general))
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
