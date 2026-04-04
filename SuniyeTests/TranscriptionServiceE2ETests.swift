import XCTest
@testable import Suniye

final class TranscriptionServiceE2ETests: XCTestCase {
    func testLoadModelFailsFastForMissingFiles() async throws {
        let service = TranscriptionService()

        let missing = "/tmp/suniye-e2e-missing"
        let config = RecognizerConfig(
            tokensPath: missing + "/tokens.txt",
            numThreads: 4,
            encoderPath: missing + "/encoder.int8.onnx",
            decoderPath: missing + "/decoder.int8.onnx",
            joinerPath: missing + "/joiner.int8.onnx",
            modelType: "nemo_transducer"
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

    func testLoadMoonshineFailsFastForMissingFiles() async throws {
        let service = TranscriptionService()

        let missing = "/tmp/suniye-e2e-missing-moonshine"
        let config = RecognizerConfig(
            modelID: .moonshineBase,
            family: .moonshine,
            tokensPath: missing + "/tokens.txt",
            numThreads: 4,
            encoderPath: missing + "/encode.int8.onnx",
            preprocessorPath: missing + "/preprocess.onnx",
            uncachedDecoderPath: missing + "/uncached_decode.int8.onnx",
            cachedDecoderPath: missing + "/cached_decode.int8.onnx"
        )

        do {
            try await service.loadModel(config: config)
            XCTFail("Expected loadModel to fail when moonshine model files are missing")
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
