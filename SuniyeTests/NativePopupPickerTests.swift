import XCTest
@testable import Suniye

final class NativePopupPickerTests: XCTestCase {
    func testMenuSyncBoundsModelIndicesToNativeMenuItems() {
        XCTAssertEqual(
            Array(
                NativePopupPickerMenuSync.validItemIndices(
                    itemCount: 3,
                    menuItemCount: 1
                )
            ),
            [0]
        )
        XCTAssertEqual(
            Array(
                NativePopupPickerMenuSync.validItemIndices(
                    itemCount: 0,
                    menuItemCount: 2
                )
            ),
            []
        )
        XCTAssertEqual(
            Array(
                NativePopupPickerMenuSync.validItemIndices(
                    itemCount: 2,
                    menuItemCount: 0
                )
            ),
            []
        )
    }

    func testSelectedIndexIsRejectedWhenNativeMenuDoesNotContainIt() {
        XCTAssertNil(
            NativePopupPickerMenuSync.validSelectedIndex(
                2,
                menuItemCount: 2
            )
        )
        XCTAssertEqual(
            NativePopupPickerMenuSync.validSelectedIndex(
                1,
                menuItemCount: 2
            ),
            1
        )
    }
}
