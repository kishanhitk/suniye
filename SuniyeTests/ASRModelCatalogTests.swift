import XCTest
@testable import Suniye

final class ASRModelCatalogTests: XCTestCase {
    func testCatalogHasEntryForEveryModelID() {
        for modelID in ASRModelID.allCases {
            XCTAssertEqual(ASRModelCatalog.entry(for: modelID).id, modelID)
        }
    }

}
