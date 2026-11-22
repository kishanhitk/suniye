import XCTest
@testable import Suniye

final class KeychainServiceTests: XCTestCase {
    func testTheKeyIsSavedTrimmedAndADeleteRemovesIt() async throws {
        let item = MemorySecretItem()
        let service = KeychainService(item: item)
        let before = try await service.getLLMKey()
        XCTAssertNil(before)

        try await service.setLLMKey("  sk-test-123 \n")
        let saved = try await service.getLLMKey()
        XCTAssertEqual(item.data, Data("sk-test-123".utf8))
        XCTAssertEqual(saved, "sk-test-123")

        try await service.deleteLLMKey()
        let after = try await service.getLLMKey()
        XCTAssertNil(item.data)
        XCTAssertNil(after)
    }

    func testAnEmptyKeyIsRejectedAndTheSavedKeyStays() async {
        let item = MemorySecretItem(Data("sk-saved".utf8))
        let service = KeychainService(item: item)

        do {
            try await service.setLLMKey("  \n")
            XCTFail("An empty key was saved")
        } catch {
            guard case KeychainServiceError.invalidData = error else {
                return XCTFail("Expected invalidData, got \(error)")
            }
        }
        XCTAssertEqual(item.data, Data("sk-saved".utf8))
    }

    func testAnItemThatIsNotUTF8IsInvalid() async {
        let service = KeychainService(item: MemorySecretItem(Data([0xFF, 0xFE, 0xFA])))

        do {
            _ = try await service.getLLMKey()
            XCTFail("A non-UTF-8 item was read as a key")
        } catch {
            guard case KeychainServiceError.invalidData = error else {
                return XCTFail("Expected invalidData, got \(error)")
            }
        }
    }

    func testThePlainTextKeyFilesAreRemovedAndOtherFilesStay() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("suniye-plain-key-files-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for filename in ["llm_api_key.txt", "openrouter_api_key.txt", "other.txt"] {
            try Data("x".utf8).write(to: directory.appendingPathComponent(filename))
        }

        KeychainService.removePlainTextKeyFiles(from: directory)

        let remaining = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(remaining, ["other.txt"])
    }
}
