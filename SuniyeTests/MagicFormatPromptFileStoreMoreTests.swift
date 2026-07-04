import XCTest
@testable import Suniye

final class MagicFormatPromptFileStoreMoreTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("suniye-prompt-store-more-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testSaveProviderPromptWritesFile() throws {
        let store = MagicFormatPromptFileStore(promptsDirectoryURL: temporaryDirectory)

        store.saveProviderPrompt(.apple, content: "edited apple prompt")

        XCTAssertEqual(
            try String(contentsOf: store.providerPromptURL(.apple), encoding: .utf8),
            "edited apple prompt"
        )
    }

    func testSaveAppPromptWritesFileForValidBundleID() throws {
        let store = MagicFormatPromptFileStore(promptsDirectoryURL: temporaryDirectory)

        store.saveAppPrompt(bundleID: "com.example.notes", content: "notes prompt")

        XCTAssertEqual(
            try String(contentsOf: store.appPromptURL(bundleID: "com.example.notes")!, encoding: .utf8),
            "notes prompt"
        )
    }

    func testSaveAppPromptIgnoresBlankBundleID() {
        let store = MagicFormatPromptFileStore(promptsDirectoryURL: temporaryDirectory)

        store.saveAppPrompt(bundleID: "   ", content: "orphan prompt")

        // Nothing may be written; the prompts directory is never even created.
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryDirectory.path))
    }

    func testAppPromptURLIsNilForBlankBundleID() {
        let store = MagicFormatPromptFileStore(promptsDirectoryURL: temporaryDirectory)

        XCTAssertNil(store.appPromptURL(bundleID: " \n "))
    }

    func testSyncAppPromptWithBlankBundleIDReturnsFallback() {
        let store = MagicFormatPromptFileStore(promptsDirectoryURL: temporaryDirectory)

        let prompt = store.syncAppPrompt(bundleID: "  ", fallback: "fallback prompt")

        XCTAssertEqual(prompt, "fallback prompt")
    }

    func testUnwritablePromptsDirectoryDegradesToSettingsMirror() throws {
        // A regular file where the prompts directory should be makes every
        // directory creation and file write fail.
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let blockerURL = temporaryDirectory.appendingPathComponent("blocker", isDirectory: false)
        try Data("not a directory".utf8).write(to: blockerURL)
        let store = MagicFormatPromptFileStore(
            promptsDirectoryURL: blockerURL.appendingPathComponent("prompts", isDirectory: true)
        )
        var settings = LLMSettings()
        settings.baseSystemPrompt = "API prompt"
        settings.appPromptBindings = [
            AppPromptBinding(bundleID: "com.example.notes", appDisplayName: "Notes", prompt: "Notes prompt"),
        ]

        let synced = store.syncPrompts(settings: settings)
        store.saveProviderPrompt(.api, content: "ignored")

        // Prompts stay as-configured; no files could be created.
        XCTAssertEqual(synced, settings)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.providerPromptURL(.api).path))
    }
}
