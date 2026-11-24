import XCTest
@testable import Suniye

/// Speech model downloads from Settings, with the download server stubbed.
@MainActor
final class ModelDownloadFlowTests: XCTestCase {
    func testADownloadedModelIsInstalledChosenAndUsedForDictation() async throws {
        let app = try FlowApp(self)
        await app.launch()
        let entry = ASRModelCatalog.entry(for: .senseVoice)
        guard case let .archive(archiveURL) = entry.downloadSource else {
            return XCTFail("SenseVoice downloads as one archive")
        }
        StubURLProtocol.serve([archiveURL: .init(body: try Self.archive(of: entry, in: app.root))])

        app.appState.downloadASRModel(.senseVoice, autoSelect: true)
        await waitUntil(timeout: 10) { app.appState.activeASRModelOperationID == nil }

        XCTAssertTrue(app.appState.isASRModelDownloaded(.senseVoice))
        XCTAssertEqual(app.appState.selectedASRModelID, .senseVoice)
        XCTAssertEqual(app.stubEngine.loadedConfigs.last?.modelID, .senseVoice)
        XCTAssertEqual(GeneralSettingsStore(userDefaults: app.defaults).load().selectedASRModelID, .senseVoice)
        await app.dictate(saying: "Hello from SenseVoice.")
        XCTAssertEqual(app.focusedApp.text, "Hello from SenseVoice.")
    }

    func testADownloadWithWrongBytesInstallsNothingAndKeepsTheModelInUse() async throws {
        let app = try FlowApp(self)
        await app.launch()
        StubURLProtocol.handler = { request in
            let body = Data("not the model".utf8)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Length": "\(body.count)"])!
            return (response, body)
        }

        app.appState.downloadASRModel(.cohereTranscribe, autoSelect: true)
        await waitUntil(timeout: 10) { app.appState.activeASRModelOperationID == nil }

        XCTAssertFalse(app.appState.isASRModelDownloaded(.cohereTranscribe))
        XCTAssertEqual(app.appState.lastFailedASRModelID, .cohereTranscribe)
        XCTAssertEqual(app.appState.selectedASRModelID, .parakeetV3)
        XCTAssertEqual(app.appState.phase, .ready)
        await app.dictate(saying: "Still works.")
        XCTAssertEqual(app.focusedApp.text, "Still works.")
    }

    private static func archive(of entry: ASRModelCatalogEntry, in root: URL) throws -> Data {
        let staging = root.appendingPathComponent("archive-\(UUID().uuidString)", isDirectory: true)
        let model = staging.appendingPathComponent(entry.directoryName, isDirectory: true)
        for path in entry.manifest.requiredRelativePaths {
            let file = model.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("model".utf8).write(to: file)
        }
        let archive = staging.appendingPathComponent("model.tar.bz2")
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-cjf", archive.path, "-C", staging.path, entry.directoryName]
        try tar.run()
        tar.waitUntilExit()
        XCTAssertEqual(tar.terminationStatus, 0)
        return try Data(contentsOf: archive)
    }
}
