import XCTest
@testable import Suniye

final class TranscriptionServiceE2ETests: XCTestCase {
    func testLoadModelFailsFastForMissingFiles() async throws {
        let service = TranscriptionService()

        let missing = "/tmp/suniye-e2e-missing"
        let config = RecognizerConfig(
            encoderPath: missing + "/encoder.int8.onnx",
            decoderPath: missing + "/decoder.int8.onnx",
            joinerPath: missing + "/joiner.int8.onnx",
            tokensPath: missing + "/tokens.txt",
            numThreads: 4
        )

        do {
            try await service.loadModel(config: config)
            XCTFail("Expected loadModel to fail when model files are missing")
        } catch let error as TranscriptionService.ServiceError {
            switch error {
            case .missingModelFile:
                break
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
