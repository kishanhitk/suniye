import XCTest
@testable import Suniye

final class MainWindowIATests: XCTestCase {
    func testPrimarySectionOrder() {
        XCTAssertEqual(SidebarView.primarySections, [.home, .dictionary, .style, .notes, .settings])
    }

    func testPrimarySectionTitles() {
        XCTAssertEqual(MainWindowSection.home.title, "Home")
        XCTAssertEqual(MainWindowSection.dictionary.title, "Dictionary")
        XCTAssertEqual(MainWindowSection.style.title, "Style")
        XCTAssertEqual(MainWindowSection.notes.title, "Notes")
        XCTAssertEqual(MainWindowSection.settings.title, "Settings")
    }

    func testSettingsSectionOrderAndDefault() {
        XCTAssertEqual(SettingsSection.allCases, [.general, .system, .vibeCoding])
        XCTAssertEqual(SettingsSection.allCases.first, .general)
    }
}
