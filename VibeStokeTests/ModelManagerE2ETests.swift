import XCTest
@testable import VibeStoke

final class ModelManagerE2ETests: XCTestCase {
    func testModelDirectoryResolvesInsideApplicationSupport() throws {
        let manager = ModelManager()
        let modelDir = try manager.modelDirectoryURL()

        XCTAssertTrue(modelDir.path.contains("/Library/Application Support/VibeStoke/models/"))
    }

    func testRecognizerConfigUsesExpectedFileNames() throws {
        let manager = ModelManager()
        let config = try manager.makeRecognizerConfig()

        XCTAssertTrue(config.encoderPath.hasSuffix("encoder.int8.onnx"))
        XCTAssertTrue(config.decoderPath.hasSuffix("decoder.int8.onnx"))
        XCTAssertTrue(config.joinerPath.hasSuffix("joiner.int8.onnx"))
        XCTAssertTrue(config.tokensPath.hasSuffix("tokens.txt"))
        XCTAssertEqual(config.numThreads, 4)
    }
}
