import XCTest
@testable import Suniye

final class KeychainServiceMoreTests: XCTestCase {
    private let fileManager = FileManager.default

    private func makeDirectory(_ suffix: String) throws -> URL {
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("suniye-more-key-store-\(suffix)-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func testErrorDescriptionsCoverAllCases() {
        XCTAssertEqual(KeychainServiceError.invalidData.errorDescription, "Invalid API key data")
        XCTAssertEqual(KeychainServiceError.writeFailed.errorDescription, "Failed to save API key")
        XCTAssertEqual(KeychainServiceError.readFailed.errorDescription, "Failed to read API key")
        XCTAssertEqual(KeychainServiceError.deleteFailed.errorDescription, "Failed to clear API key")
    }

    func testSetLLMKeyThrowsWriteFailedWhenBaseDirectoryIsAFile() throws {
        // A regular file where the config directory should be makes directory
        // creation (and therefore the write) fail.
        let blockingFile = fileManager.temporaryDirectory
            .appendingPathComponent("suniye-more-key-store-blocking-\(UUID().uuidString)")
        try Data("not a directory".utf8).write(to: blockingFile)
        defer { try? fileManager.removeItem(at: blockingFile) }

        let service = KeychainService(baseDirectoryURL: blockingFile)

        XCTAssertThrowsError(try service.setLLMKey("sk-test")) { error in
            guard case KeychainServiceError.writeFailed = error else {
                return XCTFail("Expected writeFailed, got \(error)")
            }
        }
    }

    func testGetLLMKeyThrowsInvalidDataForNonUTF8FileAndHasKeyReturnsFalse() throws {
        let directory = try makeDirectory("utf8")
        defer { try? fileManager.removeItem(at: directory) }
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
        try fileManager.setAttributes([.posixPermissions: 0o000], ofItemAtPath: keyFile.path)
        defer {
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyFile.path)
            try? fileManager.removeItem(at: directory)
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
        defer { try? fileManager.removeItem(at: directory) }
        let legacyFile = directory.appendingPathComponent("openrouter_api_key.txt")
        try Data("legacy-key".utf8).write(to: legacyFile)

        let service = KeychainService(baseDirectoryURL: directory)
        try service.deleteLLMKey()

        XCTAssertFalse(fileManager.fileExists(atPath: legacyFile.path))
        XCTAssertNil(try service.getLLMKey())
    }

    func testDeleteLLMKeyThrowsDeleteFailedWhenDirectoryIsReadOnly() throws {
        let directory = try makeDirectory("readonly")
        let keyFile = directory.appendingPathComponent("llm_api_key.txt")
        try Data("sk-test".utf8).write(to: keyFile)
        try fileManager.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer {
            try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? fileManager.removeItem(at: directory)
        }

        let service = KeychainService(baseDirectoryURL: directory)

        XCTAssertThrowsError(try service.deleteLLMKey()) { error in
            guard case KeychainServiceError.deleteFailed = error else {
                return XCTFail("Expected deleteFailed, got \(error)")
            }
        }
    }
}
