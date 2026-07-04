import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

protocol AppleFoundationModelsClient {
    var availability: AppleFoundationModelsAvailability { get }
    func generate(instructions: String, prompt: String, maxTokens: Int) async throws -> String
}

final class AppleFoundationModelsPostProcessor: AppleMagicFormatPostProcessor {
    private let client: AppleFoundationModelsClient

    init(client: AppleFoundationModelsClient = AppleFoundationModelsPostProcessor.makeDefaultClient()) {
        self.client = client
    }

    var availability: AppleFoundationModelsAvailability {
        client.availability
    }

    func polish(text: String, config: AppleMagicFormatConfig) async throws -> String {
        guard availability.isAvailable else {
            throw LLMPostProcessorError.invalidConfiguration(availability.logValue)
        }

        return try await MagicFormatPipeline.polish(
            text: text,
            systemPrompt: config.systemPrompt,
            keywords: config.keywords,
            maxTokens: config.maxTokens
        ) { request in
            do {
                return try await withTimeout(seconds: config.timeoutSeconds) {
                    try await self.client.generate(
                        instructions: request.instructions,
                        prompt: request.prompt,
                        maxTokens: request.maxTokens ?? config.maxTokens
                    )
                }
            } catch let error as LLMPostProcessorError {
                throw error
            } catch is TimeoutError {
                throw LLMPostProcessorError.timeout
            } catch {
                throw LLMPostProcessorError.provider(error.localizedDescription)
            }
        }
    }

    func generate(instructions: String, userText: String, config: AppleMagicFormatConfig) async throws -> String {
        guard availability.isAvailable else {
            throw LLMPostProcessorError.invalidConfiguration(availability.logValue)
        }

        do {
            let raw = try await withTimeout(seconds: config.timeoutSeconds) {
                try await self.client.generate(
                    instructions: instructions,
                    prompt: userText,
                    maxTokens: config.maxTokens
                )
            }
            let sanitized = MagicFormatOutputSanitizer.sanitize(raw)
            guard !sanitized.isEmpty else {
                throw LLMPostProcessorError.emptyOutput
            }
            return sanitized
        } catch let error as LLMPostProcessorError {
            throw error
        } catch is TimeoutError {
            throw LLMPostProcessorError.timeout
        } catch {
            throw LLMPostProcessorError.provider(error.localizedDescription)
        }
    }

    func testSetup(config: AppleMagicFormatConfig) async throws {
        guard availability.isAvailable else {
            throw LLMPostProcessorError.invalidConfiguration(availability.logValue)
        }
    }

    private static func makeDefaultClient() -> AppleFoundationModelsClient {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return LiveAppleFoundationModelsClient()
        }
        #endif

        return UnsupportedAppleFoundationModelsClient()
    }

    private struct TimeoutError: Error {}

    private func withTimeout<T: Sendable>(seconds: Double, operation: @escaping () async throws -> T) async throws -> T {
        let race = TimeoutRace<T>()
        let workTask = Task {
            do {
                race.finish(.success(try await operation()))
            } catch {
                race.finish(.failure(error))
            }
        }
        let timeoutTask = Task {
            do {
                let nanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanoseconds)
                race.finish(.failure(TimeoutError()))
            } catch {
                race.finish(.failure(error))
            }
        }

        return try await withTaskCancellationHandler {
            defer {
                workTask.cancel()
                timeoutTask.cancel()
            }
            return try await race.wait()
        } onCancel: {
            workTask.cancel()
            timeoutTask.cancel()
            race.finish(.failure(CancellationError()))
        }
    }
}

private final class TimeoutRace<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var result: Result<T, Error>?

    func finish(_ result: Result<T, Error>) {
        var continuationToResume: CheckedContinuation<T, Error>?

        lock.lock()
        if self.result == nil {
            self.result = result
            continuationToResume = continuation
            continuation = nil
        }
        lock.unlock()

        continuationToResume?.resume(with: result)
    }

    func wait() async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            var resultToResume: Result<T, Error>?

            lock.lock()
            if let result {
                resultToResume = result
            } else {
                self.continuation = continuation
            }
            lock.unlock()

            if let resultToResume {
                continuation.resume(with: resultToResume)
            }
        }
    }
}

struct UnsupportedAppleFoundationModelsClient: AppleFoundationModelsClient {
    var availability: AppleFoundationModelsAvailability {
        .unsupportedSDKOrRuntime
    }

    func generate(instructions: String, prompt: String, maxTokens: Int) async throws -> String {
        throw LLMPostProcessorError.invalidConfiguration(AppleFoundationModelsAvailability.unsupportedSDKOrRuntime.logValue)
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
private struct LiveAppleFoundationModelsClient: AppleFoundationModelsClient {
    var availability: AppleFoundationModelsAvailability {
        mapAvailability(model.availability)
    }

    private var model: SystemLanguageModel {
        SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
    }

    func generate(instructions: String, prompt: String, maxTokens: Int) async throws -> String {
        let activeModel = model
        let session = LanguageModelSession(model: activeModel, instructions: instructions)
        let options = GenerationOptions(
            sampling: .greedy,
            temperature: 0,
            maximumResponseTokens: maxTokens
        )
        let response = try await session.respond(to: prompt, options: options)
        return response.content
    }

    private func mapAvailability(_ availability: SystemLanguageModel.Availability) -> AppleFoundationModelsAvailability {
        switch availability {
        case .available:
            return .available
        case let .unavailable(reason):
            switch reason {
            case .deviceNotEligible:
                return .deviceNotEligible
            case .appleIntelligenceNotEnabled:
                return .appleIntelligenceNotEnabled
            case .modelNotReady:
                return .modelNotReady
            @unknown default:
                return .unsupportedSDKOrRuntime
            }
        }
    }
}
#endif
