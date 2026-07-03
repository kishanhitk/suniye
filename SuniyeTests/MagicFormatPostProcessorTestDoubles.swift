import Foundation
@testable import Suniye

final class FakeLLMPostProcessor: LLMPostProcessor {
    private let result: Result<String, Error>
    private let testSetupResult: Result<Void, Error>
    private(set) var callCount = 0
    private(set) var setupTestCallCount = 0

    init(result: Result<String, Error>, testSetupResult: Result<Void, Error> = .success(())) {
        self.result = result
        self.testSetupResult = testSetupResult
    }

    func polish(text: String, config: LLMConfig) async throws -> String {
        callCount += 1
        return try result.get()
    }

    func generate(instructions: String, userText: String, config: LLMConfig) async throws -> String {
        callCount += 1
        return try result.get()
    }

    func testSetup(config: LLMConfig) async throws {
        setupTestCallCount += 1
        try testSetupResult.get()
    }
}

final class CapturingLLMPostProcessor: LLMPostProcessor {
    private let result: Result<String, Error>
    private(set) var lastConfig: LLMConfig?
    private(set) var lastTestConfig: LLMConfig?
    private(set) var lastGenerateInstructions: String?
    private(set) var lastGenerateUserText: String?

    init(result: Result<String, Error>) {
        self.result = result
    }

    func polish(text: String, config: LLMConfig) async throws -> String {
        lastConfig = config
        return try result.get()
    }

    func generate(instructions: String, userText: String, config: LLMConfig) async throws -> String {
        lastConfig = config
        lastGenerateInstructions = instructions
        lastGenerateUserText = userText
        return try result.get()
    }

    func testSetup(config: LLMConfig) async throws {
        lastTestConfig = config
    }
}

final class CapturingAppleMagicFormatPostProcessor: AppleMagicFormatPostProcessor {
    var availability: AppleFoundationModelsAvailability
    private let result: Result<String, Error>
    private(set) var callCount = 0
    private(set) var lastConfig: AppleMagicFormatConfig?
    private(set) var lastGenerateInstructions: String?
    private(set) var lastGenerateUserText: String?

    init(availability: AppleFoundationModelsAvailability, result: Result<String, Error>) {
        self.availability = availability
        self.result = result
    }

    func polish(text: String, config: AppleMagicFormatConfig) async throws -> String {
        callCount += 1
        lastConfig = config
        return try result.get()
    }

    func generate(instructions: String, userText: String, config: AppleMagicFormatConfig) async throws -> String {
        callCount += 1
        lastConfig = config
        lastGenerateInstructions = instructions
        lastGenerateUserText = userText
        return try result.get()
    }

    func testSetup(config: AppleMagicFormatConfig) async throws {
        lastConfig = config
    }
}

final class CapturingLocalGemmaMagicFormatPostProcessor: LocalGemmaMagicFormatPostProcessor {
    var availability: LocalGemmaAvailability
    var runtimeWarm: Bool
    var prewarmBlocksUntilCanceled = false
    private let result: Result<String, Error>
    private(set) var callCount = 0
    private(set) var lastConfig: LocalGemmaMagicFormatConfig?
    private(set) var lastGenerateInstructions: String?
    private(set) var lastGenerateUserText: String?
    private(set) var stopRuntimeCallCount = 0
    private(set) var prewarmCallCount = 0
    private(set) var prewarmWasCanceled = false
    private(set) var lastPrewarmConfig: LocalGemmaMagicFormatConfig?

    init(
        availability: LocalGemmaAvailability,
        runtimeWarm: Bool = false,
        result: Result<String, Error>
    ) {
        self.availability = availability
        self.runtimeWarm = runtimeWarm
        self.result = result
    }

    func isRuntimeWarm() async -> Bool {
        runtimeWarm
    }

    func prewarm(config: LocalGemmaMagicFormatConfig) async {
        prewarmCallCount += 1
        lastPrewarmConfig = config
        if prewarmBlocksUntilCanceled {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            prewarmWasCanceled = true
        }
    }

    func polish(text: String, config: LocalGemmaMagicFormatConfig) async throws -> String {
        callCount += 1
        lastConfig = config
        return try result.get()
    }

    func generate(instructions: String, userText: String, config: LocalGemmaMagicFormatConfig) async throws -> String {
        callCount += 1
        lastConfig = config
        lastGenerateInstructions = instructions
        lastGenerateUserText = userText
        return try result.get()
    }

    func testSetup(config: LocalGemmaMagicFormatConfig) async throws {
        lastConfig = config
    }

    func stopRuntime() async {
        stopRuntimeCallCount += 1
    }
}

final class BlockingAppleMagicFormatPostProcessor: AppleMagicFormatPostProcessor {
    var availability: AppleFoundationModelsAvailability = .available
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var resumeContinuation: CheckedContinuation<String, Never>?
    private(set) var callCount = 0

    func polish(text: String, config: AppleMagicFormatConfig) async throws -> String {
        callCount += 1
        startedContinuation?.resume()
        startedContinuation = nil
        return await withCheckedContinuation { continuation in
            resumeContinuation = continuation
        }
    }

    func generate(instructions: String, userText: String, config: AppleMagicFormatConfig) async throws -> String {
        try await polish(text: userText, config: config)
    }

    func testSetup(config: AppleMagicFormatConfig) async throws {}

    func waitUntilStarted() async {
        if callCount > 0 {
            return
        }
        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func resume(output: String) {
        resumeContinuation?.resume(returning: output)
        resumeContinuation = nil
    }
}

final class BlockingLLMPostProcessor: LLMPostProcessor {
    private var continuation: CheckedContinuation<Void, Never>?
    private var startContinuation: CheckedContinuation<Void, Never>?
    var testSetupResult: Result<Void, Error> = .success(())

    func polish(text: String, config: LLMConfig) async throws -> String {
        text
    }

    func generate(instructions: String, userText: String, config: LLMConfig) async throws -> String {
        userText
    }

    func testSetup(config: LLMConfig) async throws {
        startContinuation?.resume()
        startContinuation = nil
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        try testSetupResult.get()
    }

    func waitUntilStarted() async {
        if continuation != nil {
            return
        }
        await withCheckedContinuation { continuation in
            startContinuation = continuation
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
