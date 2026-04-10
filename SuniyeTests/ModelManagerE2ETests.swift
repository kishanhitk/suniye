import XCTest
@testable import Suniye

final class ModelManagerE2ETests: XCTestCase {
    private let fileManager = FileManager.default

    func testProgressEstimatorUsesReportedTotalWhenAvailable() {
        let progress = ModelDownloadProgressEstimator.estimate(
            totalBytesWritten: 340,
            totalBytesExpectedToWrite: 680,
            responseExpectedLength: nil,
            fallbackExpectedSize: 1_000
        )

        XCTAssertEqual(progress, 0.5)
    }

    func testProgressEstimatorFallsBackToResponseLengthWhenTaskTotalUnknown() {
        let progress = ModelDownloadProgressEstimator.estimate(
            totalBytesWritten: 250,
            totalBytesExpectedToWrite: NSURLSessionTransferSizeUnknown,
            responseExpectedLength: 1_000,
            fallbackExpectedSize: 2_000
        )

        XCTAssertEqual(progress, 0.25)
    }

    func testProgressEstimatorFallsBackToConfiguredExpectedSize() {
        let progress = ModelDownloadProgressEstimator.estimate(
            totalBytesWritten: 340_000_000,
            totalBytesExpectedToWrite: NSURLSessionTransferSizeUnknown,
            responseExpectedLength: NSURLSessionTransferSizeUnknown,
            fallbackExpectedSize: 680_000_000
        )

        XCTAssertEqual(progress, 0.5)
    }

    func testModelDirectoryResolvesInsideApplicationSupport() throws {
        let manager = ModelManager()
        let modelDir = try manager.modelDirectoryURL(for: .parakeetV3)

        XCTAssertTrue(modelDir.path.contains("/Library/Application Support/Suniye/models/"))
    }

    func testRecognizerConfigUsesExpectedFileNames() throws {
        let manager = ModelManager()
        let config = try manager.makeRecognizerConfig(for: .parakeetV3)

        XCTAssertTrue(config.encoderPath?.hasSuffix("encoder.int8.onnx") == true)
        XCTAssertTrue(config.decoderPath?.hasSuffix("decoder.int8.onnx") == true)
        XCTAssertTrue(config.joinerPath?.hasSuffix("joiner.int8.onnx") == true)
        XCTAssertTrue(config.tokensPath.hasSuffix("tokens.txt"))
        XCTAssertEqual(config.numThreads, 4)
    }

    func testParakeetV2RecognizerConfigUsesExpectedFiles() throws {
        let manager = ModelManager()
        let config = try manager.makeRecognizerConfig(for: .parakeetV2English)

        XCTAssertEqual(config.family, .nemoTransducer)
        XCTAssertTrue(config.encoderPath?.hasSuffix("encoder.int8.onnx") == true)
        XCTAssertTrue(config.decoderPath?.hasSuffix("decoder.int8.onnx") == true)
        XCTAssertTrue(config.joinerPath?.hasSuffix("joiner.int8.onnx") == true)
        XCTAssertTrue(config.tokensPath.hasSuffix("tokens.txt"))
    }

    func testMoonshineRecognizerConfigUsesExpectedFiles() throws {
        let manager = ModelManager()
        let config = try manager.makeRecognizerConfig(for: .moonshineBase)

        XCTAssertEqual(config.family, .moonshine)
        XCTAssertTrue(config.preprocessorPath?.hasSuffix("preprocess.onnx") == true)
        XCTAssertTrue(config.encoderPath?.hasSuffix("encode.int8.onnx") == true)
        XCTAssertTrue(config.uncachedDecoderPath?.hasSuffix("uncached_decode.int8.onnx") == true)
        XCTAssertTrue(config.cachedDecoderPath?.hasSuffix("cached_decode.int8.onnx") == true)
    }

    func testSenseVoiceRecognizerConfigUsesExpectedFiles() throws {
        let manager = ModelManager()
        let config = try manager.makeRecognizerConfig(for: .senseVoice)

        XCTAssertEqual(config.family, .senseVoice)
        XCTAssertTrue(config.modelPath?.hasSuffix("model.int8.onnx") == true)
        XCTAssertTrue(config.tokensPath.hasSuffix("tokens.txt"))
    }

    func testWhisperTurboRecognizerConfigUsesExpectedFiles() throws {
        let manager = ModelManager()
        let config = try manager.makeRecognizerConfig(for: .whisperLargeV3Turbo)

        XCTAssertEqual(config.family, .whisper)
        XCTAssertTrue(config.encoderPath?.hasSuffix("turbo-encoder.int8.onnx") == true)
        XCTAssertTrue(config.decoderPath?.hasSuffix("turbo-decoder.int8.onnx") == true)
        XCTAssertTrue(config.tokensPath.hasSuffix("turbo-tokens.txt"))
    }

    func testWhisperDistilLargeV3RecognizerConfigUsesExpectedFiles() throws {
        let manager = ModelManager()
        let config = try manager.makeRecognizerConfig(for: .whisperDistilLargeV3)

        XCTAssertEqual(config.family, .whisper)
        XCTAssertTrue(config.encoderPath?.hasSuffix("distil-large-v3-encoder.int8.onnx") == true)
        XCTAssertTrue(config.decoderPath?.hasSuffix("distil-large-v3-decoder.int8.onnx") == true)
        XCTAssertTrue(config.tokensPath.hasSuffix("distil-large-v3-tokens.txt"))
    }

    func testValidateInstallFailsBeforeLiveDirectoryIsTouched() throws {
        let entry = ASRModelCatalog.entry(for: .parakeetV3)
        let rootDirectory = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootDirectory) }

        let liveDirectory = rootDirectory.appendingPathComponent(entry.directoryName, isDirectory: true)
        let stagedDirectory = rootDirectory.appendingPathComponent(".staging", isDirectory: true)
            .appendingPathComponent(entry.directoryName, isDirectory: true)

        try createParakeetInstall(at: liveDirectory, marker: "live")
        try fileManager.createDirectory(at: stagedDirectory, withIntermediateDirectories: true)
        try writeFile(
            at: stagedDirectory.appendingPathComponent(entry.manifest.tokens),
            contents: "staged"
        )

        XCTAssertThrowsError(try ModelManager.validateInstall(entry, at: stagedDirectory))
        XCTAssertEqual(try String(contentsOf: liveDirectory.appendingPathComponent(entry.manifest.tokens)), "live")
        XCTAssertTrue(fileManager.fileExists(atPath: liveDirectory.appendingPathComponent("encoder.int8.onnx").path))
    }

    func testReplaceInstalledModelSwapsInValidatedDirectory() throws {
        let entry = ASRModelCatalog.entry(for: .parakeetV3)
        let rootDirectory = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootDirectory) }

        let liveDirectory = rootDirectory.appendingPathComponent(entry.directoryName, isDirectory: true)
        let stagedDirectory = rootDirectory.appendingPathComponent(".staging", isDirectory: true)
            .appendingPathComponent(entry.directoryName, isDirectory: true)

        try createParakeetInstall(at: liveDirectory, marker: "old")
        try createParakeetInstall(at: stagedDirectory, marker: "new")

        try ModelManager.validateInstall(entry, at: stagedDirectory)
        try ModelManager.replaceInstalledModel(at: liveDirectory, with: stagedDirectory)

        XCTAssertEqual(try String(contentsOf: liveDirectory.appendingPathComponent(entry.manifest.tokens)), "new")
        XCTAssertFalse(fileManager.fileExists(atPath: stagedDirectory.path))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("suniye-model-manager-tests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func createParakeetInstall(at directory: URL, marker: String) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try writeFile(at: directory.appendingPathComponent("tokens.txt"), contents: marker)
        try writeFile(at: directory.appendingPathComponent("encoder.int8.onnx"), contents: marker)
        try writeFile(at: directory.appendingPathComponent("decoder.int8.onnx"), contents: marker)
        try writeFile(at: directory.appendingPathComponent("joiner.int8.onnx"), contents: marker)
    }

    private func writeFile(at url: URL, contents: String) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
    }
}
