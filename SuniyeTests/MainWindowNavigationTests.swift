import XCTest
@testable import Suniye

final class MainWindowNavigationTests: XCTestCase {
    func testSettingsOpensOnPermissionsWhileAGrantIsMissing() {
        var navigation = MainWindowNavigation(destination: .section(.dashboard), permissionsMissing: true)

        navigation.open(.settings(), permissionsMissing: true)

        XCTAssertEqual(navigation.selection, .settings)
        XCTAssertEqual(navigation.settingsPane, .permissions)
    }

    func testSettingsReopensOnThePaneUsedLast() {
        var navigation = MainWindowNavigation(destination: .section(.dashboard), permissionsMissing: false)
        navigation.open(.settings(.general), permissionsMissing: false)
        navigation.open(.section(.meetings), permissionsMissing: false)

        navigation.open(.settings(), permissionsMissing: false)

        XCTAssertEqual(navigation.settingsPane, .general)
    }

    /// Settings lists the Permissions pane only while a grant is missing, so
    /// nothing opens it after the last grant.
    func testPermissionsPaneClosesOnceEveryGrantIsIn() {
        var navigation = MainWindowNavigation(destination: .settings(), permissionsMissing: true)
        XCTAssertEqual(navigation.settingsPane, .permissions)

        navigation.permissionsChanged(missing: false)
        XCTAssertEqual(navigation.settingsPane, .microphone)

        navigation.open(.settings(.permissions), permissionsMissing: false)
        XCTAssertEqual(navigation.settingsPane, .microphone)
    }

    func testBackReturnsToThePageSettingsWasOpenedFrom() {
        var navigation = MainWindowNavigation(destination: .section(.meetings), permissionsMissing: false)

        navigation.open(.settings(), permissionsMissing: false)
        navigation.open(.row(.theme), permissionsMissing: false)
        navigation.open(.settings(.shortcuts), permissionsMissing: false)

        XCTAssertEqual(navigation.sectionBeforeSettings, .meetings)
        XCTAssertEqual(navigation.settingsPane, .shortcuts)
    }

    /// A Magic Format result leaves Settings with the query. ⌘K brings that
    /// search back; any other way into Settings starts on the panes.
    func testOnlyCommandKBringsTheLastSearchBack() {
        var navigation = MainWindowNavigation(destination: .settingsSearch, permissionsMissing: false)
        navigation.searchFocusPending = false
        navigation.settingsQuery = "vocab"

        navigation.open(.row(.vocabulary), permissionsMissing: false)
        XCTAssertEqual(navigation.selection, .style)

        navigation.open(.settingsSearch, permissionsMissing: false)
        XCTAssertEqual(navigation.settingsQuery, "vocab")
        XCTAssertTrue(navigation.searchFocusPending)

        navigation.open(.section(.dashboard), permissionsMissing: false)
        navigation.open(.settings(), permissionsMissing: false)
        XCTAssertEqual(navigation.settingsQuery, "")
    }

    func testAResultInsideSettingsKeepsTheQueryAndPointsAtTheRow() {
        var navigation = MainWindowNavigation(destination: .settingsSearch, permissionsMissing: false)
        navigation.settingsQuery = "theme"

        navigation.open(.row(.theme), permissionsMissing: false)

        XCTAssertEqual(navigation.settingsQuery, "theme")
        XCTAssertEqual(navigation.settingsPane, .general)
        XCTAssertEqual(navigation.highlight?.row, .theme)
    }

    /// Opening the same row twice tints it twice; the timer of the first tint
    /// must not end the second.
    func testOnlyTheNewestHighlightEnds() throws {
        var navigation = MainWindowNavigation(destination: .section(.dashboard), permissionsMissing: false)
        navigation.open(.row(.theme), permissionsMissing: false)
        let first = try XCTUnwrap(navigation.highlight)
        navigation.open(.row(.theme), permissionsMissing: false)
        let second = try XCTUnwrap(navigation.highlight)

        navigation.endHighlight(first)
        XCTAssertEqual(navigation.highlight, second)

        navigation.endHighlight(second)
        XCTAssertNil(navigation.highlight)
    }
}
