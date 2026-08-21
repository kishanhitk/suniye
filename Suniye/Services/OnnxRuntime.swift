import Foundation

/// Minimal Swift face over the ONNX Runtime C API exported by the bundled
/// `libonnxruntime.dylib` (the same library sherpa-onnx links against). Covers
/// only what the Cohere engine needs: CPU sessions, float/int64 tensors, and a
/// blocking `run`.
enum OnnxRuntime {
    struct RuntimeError: LocalizedError {
        let message: String

        var errorDescription: String? {
            "ONNX Runtime: \(message)"
        }
    }

    static let api: UnsafePointer<OrtApi> = {
        guard let api = OrtGetApiBase().pointee.GetApi(UInt32(ORT_API_VERSION)) else {
            preconditionFailure("libonnxruntime does not provide ORT API version \(ORT_API_VERSION)")
        }
        return api
    }()

    /// One environment per process; ORT requires it to outlive every session.
    private static let environment: Result<OpaquePointer, RuntimeError> = {
        var env: OpaquePointer?
        do {
            try check(api.pointee.CreateEnv(ORT_LOGGING_LEVEL_WARNING, "suniye", &env))
            return .success(env!)
        } catch let error as RuntimeError {
            return .failure(error)
        } catch {
            return .failure(RuntimeError(message: error.localizedDescription))
        }
    }()

    static func sharedEnvironment() throws -> OpaquePointer {
        try environment.get()
    }

    static func defaultAllocator() throws -> UnsafeMutablePointer<OrtAllocator> {
        var allocator: UnsafeMutablePointer<OrtAllocator>?
        try check(api.pointee.GetAllocatorWithDefaultOptions(&allocator))
        return allocator!
    }

    static func check(_ status: OrtStatusPtr?) throws {
        guard let status else {
            return
        }
        defer {
            api.pointee.ReleaseStatus(status)
        }
        let message = api.pointee.GetErrorMessage(status).map { String(cString: $0) } ?? "unknown error"
        throw RuntimeError(message: message)
    }
}

/// An `OrtValue` tensor owned by ONNX Runtime's default CPU allocator.
final class OrtTensor {
    let handle: OpaquePointer

    private init(handle: OpaquePointer) {
        self.handle = handle
    }

    deinit {
        OnnxRuntime.api.pointee.ReleaseValue(handle)
    }

    /// Wraps a value returned by `OrtSession.run`; takes over its release.
    fileprivate static func adopt(_ handle: OpaquePointer) -> OrtTensor {
        OrtTensor(handle: handle)
    }

    static func float(shape: [Int64], values: [Float]) throws -> OrtTensor {
        let tensor = try allocate(shape: shape, type: ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, elementSize: 4)
        try tensor.withMutableData(as: Float.self) { buffer in
            guard buffer.count == values.count else {
                throw OnnxRuntime.RuntimeError(message: "shape \(shape) does not hold \(values.count) floats")
            }
            _ = buffer.initialize(from: values)
        }
        return tensor
    }

    static func zeros(shape: [Int64]) throws -> OrtTensor {
        let tensor = try allocate(shape: shape, type: ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, elementSize: 4)
        try tensor.withMutableData(as: Float.self) { buffer in
            buffer.update(repeating: 0)
        }
        return tensor
    }

    static func int64(shape: [Int64], values: [Int64]) throws -> OrtTensor {
        let tensor = try allocate(shape: shape, type: ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64, elementSize: 8)
        try tensor.withMutableData(as: Int64.self) { buffer in
            guard buffer.count == values.count else {
                throw OnnxRuntime.RuntimeError(message: "shape \(shape) does not hold \(values.count) int64s")
            }
            _ = buffer.initialize(from: values)
        }
        return tensor
    }

    private static func allocate(shape: [Int64], type: ONNXTensorElementDataType, elementSize: Int) throws -> OrtTensor {
        let allocator = try OnnxRuntime.defaultAllocator()
        var value: OpaquePointer?
        try shape.withUnsafeBufferPointer { dims in
            try OnnxRuntime.check(
                OnnxRuntime.api.pointee.CreateTensorAsOrtValue(allocator, dims.baseAddress, dims.count, type, &value)
            )
        }
        return OrtTensor(handle: value!)
    }

    var shape: [Int64] {
        get throws {
            var info: OpaquePointer?
            try OnnxRuntime.check(OnnxRuntime.api.pointee.GetTensorTypeAndShape(handle, &info))
            defer {
                OnnxRuntime.api.pointee.ReleaseTensorTypeAndShapeInfo(info)
            }
            var count = 0
            try OnnxRuntime.check(OnnxRuntime.api.pointee.GetDimensionsCount(info, &count))
            var dims = [Int64](repeating: 0, count: count)
            try dims.withUnsafeMutableBufferPointer { buffer in
                try OnnxRuntime.check(OnnxRuntime.api.pointee.GetDimensions(info, buffer.baseAddress, count))
            }
            return dims
        }
    }

    func withData<Element, Result>(
        as type: Element.Type,
        _ body: (UnsafeBufferPointer<Element>) throws -> Result
    ) throws -> Result {
        try withMutableData(as: type) { buffer in
            try body(UnsafeBufferPointer(buffer))
        }
    }

    private func withMutableData<Element, Result>(
        as type: Element.Type,
        _ body: (UnsafeMutableBufferPointer<Element>) throws -> Result
    ) throws -> Result {
        var elementCount = 0
        var info: OpaquePointer?
        try OnnxRuntime.check(OnnxRuntime.api.pointee.GetTensorTypeAndShape(handle, &info))
        defer {
            OnnxRuntime.api.pointee.ReleaseTensorTypeAndShapeInfo(info)
        }
        try OnnxRuntime.check(OnnxRuntime.api.pointee.GetTensorShapeElementCount(info, &elementCount))

        var raw: UnsafeMutableRawPointer?
        try OnnxRuntime.check(OnnxRuntime.api.pointee.GetTensorMutableData(handle, &raw))
        let typed = raw?.bindMemory(to: Element.self, capacity: elementCount)
        return try body(UnsafeMutableBufferPointer(start: typed, count: elementCount))
    }
}

/// A loaded ONNX model. `run` blocks the calling thread for the duration of
/// the inference; callers own the threading decision. ORT documents `Run` as
/// thread-safe, hence the unchecked conformance.
final class OrtSession: @unchecked Sendable {
    private let handle: OpaquePointer

    init(modelPath: String, intraOpThreads: Int) throws {
        let api = OnnxRuntime.api.pointee
        let environment = try OnnxRuntime.sharedEnvironment()

        var options: OpaquePointer?
        try OnnxRuntime.check(api.CreateSessionOptions(&options))
        defer {
            api.ReleaseSessionOptions(options)
        }
        try OnnxRuntime.check(api.SetIntraOpNumThreads(options, Int32(max(1, intraOpThreads))))
        try OnnxRuntime.check(api.SetSessionGraphOptimizationLevel(options, ORT_ENABLE_ALL))

        var session: OpaquePointer?
        try OnnxRuntime.check(api.CreateSession(environment, modelPath, options, &session))
        handle = session!
    }

    deinit {
        OnnxRuntime.api.pointee.ReleaseSession(handle)
    }

    func run(inputs: [(name: String, tensor: OrtTensor)], outputNames: [String]) throws -> [OrtTensor] {
        let inputNames = inputs.map { strdup($0.name) }
        let outputCNames = outputNames.map { strdup($0) }
        defer {
            inputNames.forEach { free($0) }
            outputCNames.forEach { free($0) }
        }

        let inputNamePointers = inputNames.map { UnsafePointer($0) }
        let outputNamePointers = outputCNames.map { UnsafePointer($0) }
        let inputValues: [OpaquePointer?] = inputs.map(\.tensor.handle)
        var outputValues = [OpaquePointer?](repeating: nil, count: outputNames.count)

        try OnnxRuntime.check(
            OnnxRuntime.api.pointee.Run(
                handle,
                nil,
                inputNamePointers,
                inputValues,
                inputs.count,
                outputNamePointers,
                outputNames.count,
                &outputValues
            )
        )
        return try outputValues.map { value in
            guard let value else {
                throw OnnxRuntime.RuntimeError(message: "Run returned a nil output without an error status")
            }
            return OrtTensor.adopt(value)
        }
    }
}
