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
        let trimmedInput = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
            throw LLMPostProcessorError.emptyOutput
        }
        guard availability.isAvailable else {
            throw LLMPostProcessorError.invalidConfiguration(availability.logValue)
        }

        var lastInvalidOutputWasEmpty = false
        for attempt in 0 ..< 2 {
            let instructions = makeInstructions(config: config, text: trimmedInput, retrying: attempt > 0)
            let prompt = makePrompt(text: trimmedInput)

            do {
                let raw = try await withTimeout(seconds: config.timeoutSeconds) {
                    try await self.client.generate(
                        instructions: instructions,
                        prompt: prompt,
                        maxTokens: config.maxTokens
                    )
                }
                let sanitized = MagicFormatOutputSanitizer.sanitize(raw)
                if MagicFormatOutputSanitizer.isValidPlainText(sanitized, for: trimmedInput) {
                    return sanitized
                }
                lastInvalidOutputWasEmpty = sanitized.isEmpty
            } catch let error as LLMPostProcessorError {
                throw error
            } catch is TimeoutError {
                throw LLMPostProcessorError.timeout
            } catch {
                throw LLMPostProcessorError.provider(error.localizedDescription)
            }
        }

        throw lastInvalidOutputWasEmpty ? LLMPostProcessorError.emptyOutput : LLMPostProcessorError.malformedResponse
    }

    func testSetup(config: AppleMagicFormatConfig) async throws {
        guard availability.isAvailable else {
            throw LLMPostProcessorError.invalidConfiguration(availability.logValue)
        }
    }

    private func makeInstructions(config: AppleMagicFormatConfig, text: String, retrying: Bool) -> String {
        var sections = [config.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)]

        if !config.keywords.isEmpty {
            sections.append("Vocabulary terms to preserve exactly when present: \(config.keywords.joined(separator: ", ")).")
        }

        if MagicFormatOutputSanitizer.allowsMultilineOutput(for: text) {
            sections.append("Formatting intent detected: return a plain-text multi-line list with one item per line. Use plain hyphen bullets for unordered item lists, including \"list of ...\" requests where items are separated by commas, pauses, or \"and\". Use numbered lines only for ordered actions, steps, or explicit numbered lists. Do not add headings or extra items.")
        }

        if retrying {
            if MagicFormatOutputSanitizer.allowsMultilineOutput(for: text) {
                sections.append("Retry correction: return only the cleaned transcript text as a plain-text list. Do not add wrapper text, markdown, quotes around the answer, or extra commentary.")
            } else {
                sections.append("Retry correction: return only the cleaned transcript text. One line. Do not add wrapper text, markdown, quotes around the answer, or extra commentary.")
            }
        }

        return sections
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private func makePrompt(text: String) -> String {
        """
        <transcript>
        \(text)
        </transcript>
        """
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

private struct UnsupportedAppleFoundationModelsClient: AppleFoundationModelsClient {
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
