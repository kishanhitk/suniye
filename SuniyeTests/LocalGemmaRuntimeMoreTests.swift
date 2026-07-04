import XCTest
@testable import Suniye

final class LocalGemmaRuntimeMoreTests: XCTestCase {
    func testResolveFailsOnUnsupportedHardware() {
        let manager = StubLocalLLMModelManager()
        manager.isHardwareSupported = false
        manager.installedModelIDs.insert(.gemma4E2BQ4KM)
        let locator = LocalGemmaRuntimeLocator(modelManager: manager)

        guard case let .failure(availability) = locator.resolve() else {
            XCTFail("Expected failure for unsupported hardware")
            return
        }
        XCTAssertEqual(availability, .unsupportedHardware)
    }

    func testResolveFailsWhenModelNotInstalled() {
        let manager = StubLocalLLMModelManager()
        manager.isHardwareSupported = true
        manager.installedModelIDs = []
        let locator = LocalGemmaRuntimeLocator(modelManager: manager)

        guard case let .failure(availability) = locator.resolve() else {
            XCTFail("Expected failure for missing model")
            return
        }
        XCTAssertEqual(availability, .modelNotInstalled)
    }
}
