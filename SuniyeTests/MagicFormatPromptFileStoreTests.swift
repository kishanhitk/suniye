import XCTest
@testable import Suniye

final class MagicFormatPromptFileStoreTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("suniye-prompt-store-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testSyncMigratesSettingsPromptsIntoFiles() throws {
        let store = MagicFormatPromptFileStore(promptsDirectoryURL: temporaryDirectory)
        var settings = LLMSettings()
        settings.baseSystemPrompt = "API prompt"
        settings.appleSystemPrompt = "Apple prompt"
        settings.gemmaSystemPrompt = "Gemma prompt"
        settings.appPromptBindings = [
            AppPromptBinding(bundleID: "com.example.notes", appDisplayName: "Notes", prompt: "Notes prompt")
        ]

        let synced = store.syncPrompts(settings: settings)

        XCTAssertEqual(synced, settings)
        XCTAssertEqual(try String(contentsOf: store.providerPromptURL(.api), encoding: .utf8), "API prompt")
        XCTAssertEqual(try String(contentsOf: store.providerPromptURL(.apple), encoding: .utf8), "Apple prompt")
        XCTAssertEqual(try String(contentsOf: store.providerPromptURL(.localGemma), encoding: .utf8), "Gemma prompt")
        XCTAssertEqual(try String(contentsOf: store.appPromptURL(bundleID: "com.example.notes")!, encoding: .utf8), "Notes prompt")
    }

    func testSyncReadsExistingFilesBackIntoSettingsMirror() throws {
        let store = MagicFormatPromptFileStore(promptsDirectoryURL: temporaryDirectory)
        var settings = LLMSettings()
        settings.baseSystemPrompt = "old API"
        settings.appPromptBindings = [
            AppPromptBinding(bundleID: "com.example.notes", appDisplayName: "Notes", prompt: "old app")
        ]

        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        try "file API".write(to: store.providerPromptURL(.api), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: temporaryDirectory.appendingPathComponent("apps", isDirectory: true), withIntermediateDirectories: true)
        try "file app".write(to: store.appPromptURL(bundleID: "com.example.notes")!, atomically: true, encoding: .utf8)

        let synced = store.syncPrompts(settings: settings)

        XCTAssertEqual(synced.baseSystemPrompt, "file API")
        XCTAssertEqual(synced.appPromptBindings.first?.prompt, "file app")
    }

    func testDeletedPromptFileIsRecreatedFromSettingsMirror() throws {
        let store = MagicFormatPromptFileStore(promptsDirectoryURL: temporaryDirectory)
        var settings = LLMSettings()
        settings.baseSystemPrompt = "restored API"

        _ = store.syncPrompts(settings: settings)
        try FileManager.default.removeItem(at: store.providerPromptURL(.api))

        let synced = store.syncPrompts(settings: settings)

        XCTAssertEqual(synced.baseSystemPrompt, "restored API")
        XCTAssertEqual(try String(contentsOf: store.providerPromptURL(.api), encoding: .utf8), "restored API")
    }

    func testPerAppPromptPathUsesBundleIDUnderAppsDirectory() {
        let store = MagicFormatPromptFileStore(promptsDirectoryURL: temporaryDirectory)

        XCTAssertEqual(
            store.appPromptURL(bundleID: "com.example.notes")?.path,
            temporaryDirectory.appendingPathComponent("apps/com.example.notes.md").path
        )
    }

    func testSyncAppPromptReusesExistingPromptFile() throws {
        let store = MagicFormatPromptFileStore(promptsDirectoryURL: temporaryDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory.appendingPathComponent("apps", isDirectory: true), withIntermediateDirectories: true)
        try "existing app prompt".write(to: store.appPromptURL(bundleID: "com.example.notes")!, atomically: true, encoding: .utf8)

        let prompt = store.syncAppPrompt(bundleID: "com.example.notes", fallback: "")

        XCTAssertEqual(prompt, "existing app prompt")
    }
}
