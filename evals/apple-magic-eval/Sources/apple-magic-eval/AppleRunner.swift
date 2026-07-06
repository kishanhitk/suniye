import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

// Result of one generation attempt. Refusals are a distinct outcome the Gemma
// harness never had: Apple's guardrails can decline instead of returning text.
enum GenerationOutcome {
    case success(String)
    case refusal(String)
    case failure(String)
}

protocol AppleModelRunner {
    var availabilityDescription: String { get }
    var isAvailable: Bool { get }
    func generate(instructions: String, prompt: String, maxTokens: Int) async -> GenerationOutcome
}

// Mirrors LiveAppleFoundationModelsClient's model + generation config so the
// eval sees the same on-device behavior the app ships.
enum AppleModelRunnerFactory {
    static func make() -> AppleModelRunner {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return LiveRunner()
        }
        #endif
        return UnsupportedRunner()
    }
}

struct UnsupportedRunner: AppleModelRunner {
    var availabilityDescription: String { "FoundationModels unavailable (needs macOS 26)" }
    var isAvailable: Bool { false }
    func generate(instructions: String, prompt: String, maxTokens: Int) async -> GenerationOutcome {
        .failure(availabilityDescription)
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
struct LiveRunner: AppleModelRunner {
    private var model: SystemLanguageModel {
        SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
    }

    var isAvailable: Bool {
        if case .available = model.availability { return true }
        return false
    }

    var availabilityDescription: String {
        switch model.availability {
        case .available:
            return "available"
        case let .unavailable(reason):
            return "unavailable(\(reason))"
        @unknown default:
            return "unavailable(unknown)"
        }
    }

    func generate(instructions: String, prompt: String, maxTokens: Int) async -> GenerationOutcome {
        let session = LanguageModelSession(model: model, instructions: instructions)
        let options = GenerationOptions(
            sampling: .greedy,
            temperature: 0,
            maximumResponseTokens: maxTokens
        )
        do {
            let response = try await session.respond(to: prompt, options: options)
            return .success(response.content)
        } catch let error as LanguageModelSession.GenerationError {
            // Guardrail declines are refusals; everything else is a hard failure.
            if case .guardrailViolation = error {
                return .refusal(String(describing: error))
            }
            return .failure(String(describing: error))
        } catch {
            let text = String(describing: error).lowercased()
            if text.contains("guardrail") || text.contains("safety") || text.contains("unsafe") {
                return .refusal(String(describing: error))
            }
            return .failure(String(describing: error))
        }
    }
}
#endif
