import XCTest
@testable import Suniye

final class KeychainServiceTests: XCTestCase {
    func testFileBackedKeyStoreRoundTrip() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("suniye-key-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: directory) }

        let service = KeychainService(baseDirectoryURL: directory)

        XCTAssertFalse(service.hasLLMKey())

        try service.setLLMKey("  sk-test-123 \n")
        XCTAssertTrue(service.hasLLMKey())
        XCTAssertEqual(try service.getLLMKey(), "sk-test-123")

        let keyPath = directory.appendingPathComponent("llm_api_key.txt").path
        let attributes = try fileManager.attributesOfItem(atPath: keyPath)
        let permissions = attributes[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)

        try service.deleteLLMKey()
        XCTAssertFalse(service.hasLLMKey())
        XCTAssertNil(try service.getLLMKey())
    }

    func testSetLLMKeyRejectsEmptyValues() {
        let service = KeychainService(baseDirectoryURL: FileManager.default.temporaryDirectory)

        XCTAssertThrowsError(try service.setLLMKey("  \n")) { error in
            guard case KeychainServiceError.invalidData = error else {
                return XCTFail("Expected invalidData, got \(error)")
            }
        }
    }

    func testGetLLMKeyFallsBackToLegacyFilename() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("suniye-key-store-legacy-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: directory) }

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacyFile = directory.appendingPathComponent("openrouter_api_key.txt")
        try Data("legacy-key".utf8).write(to: legacyFile)

        let service = KeychainService(baseDirectoryURL: directory)
        XCTAssertEqual(try service.getLLMKey(), "legacy-key")
    }
}
