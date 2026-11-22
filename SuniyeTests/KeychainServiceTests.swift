import XCTest
@testable import Suniye

final class KeychainServiceTests: XCTestCase {
    func testTheKeyIsSavedTrimmedAndADeleteRemovesIt() throws {
        let item = MemorySecretItem()
        let service = KeychainService(item: item)
        XCTAssertNil(try service.getLLMKey())

        try service.setLLMKey("  sk-test-123 \n")
        XCTAssertEqual(item.data, Data("sk-test-123".utf8))
        XCTAssertEqual(try service.getLLMKey(), "sk-test-123")

        try service.deleteLLMKey()
        XCTAssertNil(item.data)
        XCTAssertNil(try service.getLLMKey())
    }

    func testAnEmptyKeyIsRejectedAndTheSavedKeyStays() {
        let item = MemorySecretItem(Data("sk-saved".utf8))
        let service = KeychainService(item: item)

        XCTAssertThrowsError(try service.setLLMKey("  \n")) { error in
            guard case KeychainServiceError.invalidData = error else {
                return XCTFail("Expected invalidData, got \(error)")
            }
        }
        XCTAssertEqual(item.data, Data("sk-saved".utf8))
    }

    func testAnItemThatIsNotUTF8IsInvalid() {
        let service = KeychainService(item: MemorySecretItem(Data([0xFF, 0xFE, 0xFA])))

        XCTAssertThrowsError(try service.getLLMKey()) { error in
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
