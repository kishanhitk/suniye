import XCTest
@testable import Suniye

final class ModelManagerE2ETests: XCTestCase {
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
}
