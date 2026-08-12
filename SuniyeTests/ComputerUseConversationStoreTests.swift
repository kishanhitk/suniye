import XCTest
@testable import Suniye

final class ComputerUseConversationStoreTests: XCTestCase {
    func testRoundTripsConversationIncludingRawToolOutput() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ComputerUseConversationStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ComputerUseConversationStore(
            fileURL: directory.appendingPathComponent("current-session.json")
        )
        let activity = ComputerUseActivity(
            toolName: "get_app_state",
            arguments: #"{"app":"Calculator"}"#,
            output: #"{"app":"Calculator","text":"0 AXStaticText: 42"}"#
        )
        let conversation = [
            ComputerUseConversationMessage(role: .user, text: "Inspect Calculator"),
            ComputerUseConversationMessage(activity: activity),
            ComputerUseConversationMessage(role: .assistant, text: "Calculator shows 42."),
        ]

        store.save(conversation)

        XCTAssertEqual(store.load(), conversation)
    }

    func testEmptyConversationRemovesPersistedSession() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ComputerUseConversationStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("current-session.json")
        let store = ComputerUseConversationStore(fileURL: fileURL)
        store.save([ComputerUseConversationMessage(role: .user, text: "A task")])

        store.save([])

        XCTAssertTrue(store.load().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }
}
