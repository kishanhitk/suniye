import XCTest
@testable import VibeStoke

final class KeychainServiceTests: XCTestCase {
    func testFileBackedKeyStoreRoundTrip() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("vibestroke-key-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: directory) }

        let service = KeychainService(baseDirectoryURL: directory)

        XCTAssertFalse(service.hasOpenRouterKey())

        try service.setOpenRouterKey("  sk-test-123 \n")
        XCTAssertTrue(service.hasOpenRouterKey())
        XCTAssertEqual(try service.getOpenRouterKey(), "sk-test-123")

        let keyPath = directory.appendingPathComponent("openrouter_api_key.txt").path
        let attributes = try fileManager.attributesOfItem(atPath: keyPath)
        let permissions = attributes[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)

        try service.deleteOpenRouterKey()
        XCTAssertFalse(service.hasOpenRouterKey())
        XCTAssertNil(try service.getOpenRouterKey())
    }

    func testSetOpenRouterKeyRejectsEmptyValues() {
        let service = KeychainService(baseDirectoryURL: FileManager.default.temporaryDirectory)

        XCTAssertThrowsError(try service.setOpenRouterKey("  \n")) { error in
            guard case KeychainServiceError.invalidData = error else {
                return XCTFail("Expected invalidData, got \(error)")
            }
        }
    }
}
