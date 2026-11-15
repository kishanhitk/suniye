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

    func testSetLLMKeyThrowsWriteFailedWhenBaseDirectoryIsAFile() throws {
        // A regular file where the config directory should be makes directory
        // creation (and therefore the write) fail.
        let blockingFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("suniye-key-store-blocking-\(UUID().uuidString)")
        try Data("not a directory".utf8).write(to: blockingFile)
        defer { try? FileManager.default.removeItem(at: blockingFile) }

        let service = KeychainService(baseDirectoryURL: blockingFile)

        XCTAssertThrowsError(try service.setLLMKey("sk-test")) { error in
            guard case KeychainServiceError.writeFailed = error else {
                return XCTFail("Expected writeFailed, got \(error)")
            }
        }
    }

    func testGetLLMKeyThrowsInvalidDataForNonUTF8FileAndHasKeyReturnsFalse() throws {
        let directory = try makeDirectory("utf8")
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data([0xFF, 0xFE, 0xFA]).write(to: directory.appendingPathComponent("llm_api_key.txt"))

        let service = KeychainService(baseDirectoryURL: directory)

        XCTAssertThrowsError(try service.getLLMKey()) { error in
            guard case KeychainServiceError.invalidData = error else {
                return XCTFail("Expected invalidData, got \(error)")
            }
        }
        XCTAssertFalse(service.hasLLMKey())
    }

    func testGetLLMKeyThrowsReadFailedForUnreadableFile() throws {
        let directory = try makeDirectory("unreadable")
        let keyFile = directory.appendingPathComponent("llm_api_key.txt")
        try Data("sk-test".utf8).write(to: keyFile)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: keyFile.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyFile.path)
            try? FileManager.default.removeItem(at: directory)
        }

        let service = KeychainService(baseDirectoryURL: directory)

        XCTAssertThrowsError(try service.getLLMKey()) { error in
            guard case KeychainServiceError.readFailed = error else {
                return XCTFail("Expected readFailed, got \(error)")
            }
        }
        XCTAssertFalse(service.hasLLMKey())
    }

    func testDeleteLLMKeyRemovesLegacyFileWhenOnlyLegacyExists() throws {
        let directory = try makeDirectory("legacy-delete")
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacyFile = directory.appendingPathComponent("openrouter_api_key.txt")
        try Data("legacy-key".utf8).write(to: legacyFile)

        let service = KeychainService(baseDirectoryURL: directory)
        try service.deleteLLMKey()

        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyFile.path))
        XCTAssertNil(try service.getLLMKey())
    }

    func testDeleteLLMKeyThrowsDeleteFailedWhenDirectoryIsReadOnly() throws {
        let directory = try makeDirectory("readonly")
        let keyFile = directory.appendingPathComponent("llm_api_key.txt")
        try Data("sk-test".utf8).write(to: keyFile)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }

        let service = KeychainService(baseDirectoryURL: directory)

        XCTAssertThrowsError(try service.deleteLLMKey()) { error in
            guard case KeychainServiceError.deleteFailed = error else {
                return XCTFail("Expected deleteFailed, got \(error)")
            }
        }
    }

    private func makeDirectory(_ suffix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("suniye-key-store-\(suffix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
