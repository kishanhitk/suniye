import XCTest
@testable import Suniye

/// The bundled libonnxruntime is linked into the test host, so the environment
/// and tensor helpers run headless; only `OrtSession` needs a model.
final class OnnxRuntimeTests: XCTestCase {
    func testSharedEnvironmentIsCreatedOnceAndAllocatorIsAvailable() throws {
        let first = try OnnxRuntime.sharedEnvironment()
        let second = try OnnxRuntime.sharedEnvironment()
        XCTAssertEqual(first, second)
        _ = try OnnxRuntime.defaultAllocator()
    }

    func testFloatTensorRoundTripsValuesAndShape() throws {
        let tensor = try OrtTensor.float(shape: [2, 3], values: [1, 2, 3, 4, 5, 6])

        XCTAssertEqual(try tensor.shape, [2, 3])
        XCTAssertEqual(try tensor.withData(as: Float.self) { Array($0) }, [1, 2, 3, 4, 5, 6])
    }

    func testInt64TensorSupportsScalarShape() throws {
        let tensor = try OrtTensor.int64(shape: [], values: [42])

        XCTAssertEqual(try tensor.shape, [])
        XCTAssertEqual(try tensor.withData(as: Int64.self) { Array($0) }, [42])
    }

    func testZerosTensorIsZeroFilled() throws {
        let tensor = try OrtTensor.zeros(shape: [4, 8])

        XCTAssertEqual(try tensor.shape, [4, 8])
        XCTAssertEqual(try tensor.withData(as: Float.self) { $0.reduce(0, +) }, 0)
        XCTAssertEqual(try tensor.withData(as: Float.self) { $0.count }, 32)
    }

    func testShapeValueMismatchThrows() {
        XCTAssertThrowsError(try OrtTensor.float(shape: [2, 2], values: [1, 2, 3])) { error in
            XCTAssertTrue(error.localizedDescription.contains("does not hold 3 floats"), error.localizedDescription)
        }
        XCTAssertThrowsError(try OrtTensor.int64(shape: [1], values: []))
    }

    func testRuntimeErrorDescription() {
        XCTAssertEqual(OnnxRuntime.RuntimeError(message: "boom").errorDescription, "ONNX Runtime: boom")
    }
}
