import Foundation

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
