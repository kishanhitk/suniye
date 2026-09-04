import Foundation

struct LLMConfig: Equatable {
    let modelId: String
    let endpointURL: URL
    let systemPrompt: String
    let keywords: [String]
    let timeoutSeconds: Double
    let apiKey: String
}

struct AppleMagicFormatConfig: Equatable {
    let systemPrompt: String
    let keywords: [String]
    let timeoutSeconds: Double
}

struct LocalGemmaMagicFormatConfig: Equatable {
    let systemPrompt: String
    let keywords: [String]
    let startupTimeoutSeconds: Double
    let generationTimeoutSeconds: Double
    let idleTimeoutSeconds: Double
}

/// Wall-clock budget for one uncapped generation: the configured floor plus one
/// second per 80 input characters (~20 tokens, a slow Mac's decode rate), so a
/// legitimate long polish finishes and a runaway is still bounded near twice
/// the legitimate decode. Timing out falls back to the untouched input.
enum MagicFormatGenerationBudget {
    static func timeoutSeconds(floor: Double, inputCharacterCount: Int) -> Double {
        floor + Double(inputCharacterCount) / 80
    }
}

protocol LLMPostProcessor {
    func polish(text: String, config: LLMConfig) async throws -> String
    func testSetup(config: LLMConfig) async throws
    /// Freeform generation used by Edit Mode; bypasses Magic Format's dictation
    /// output policy (length/multiline validation). Provider sanitizers still run.
    func generate(instructions: String, userText: String, config: LLMConfig) async throws -> String
}

protocol AppleMagicFormatPostProcessor {
    var availability: AppleFoundationModelsAvailability { get }
    func polish(text: String, config: AppleMagicFormatConfig) async throws -> String
    func testSetup(config: AppleMagicFormatConfig) async throws
    func generate(instructions: String, userText: String, config: AppleMagicFormatConfig) async throws -> String
}

protocol LocalGemmaMagicFormatPostProcessor {
    var availability: LocalGemmaAvailability { get }
    func isRuntimeWarm() async -> Bool
    func prewarm(config: LocalGemmaMagicFormatConfig) async
    func polish(text: String, config: LocalGemmaMagicFormatConfig) async throws -> String
    func testSetup(config: LocalGemmaMagicFormatConfig) async throws
    func generate(instructions: String, userText: String, config: LocalGemmaMagicFormatConfig) async throws -> String
    func stopRuntime() async
}

extension LocalGemmaMagicFormatPostProcessor {
    func isRuntimeWarm() async -> Bool { false }
    func prewarm(config: LocalGemmaMagicFormatConfig) async {}
    func stopRuntime() async {}
}

enum AppleFoundationModelsAvailability: Equatable {
    case available
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unsupportedSDKOrRuntime

    var isAvailable: Bool {
        self == .available
    }

    var statusText: String {
        switch self {
        case .available:
            return "Apple Intelligence ready."
        case .deviceNotEligible:
            return "Apple Intelligence is not available on this Mac."
        case .appleIntelligenceNotEnabled:
            return "Turn on Apple Intelligence in System Settings."
        case .modelNotReady:
            return "Apple Intelligence model is downloading or preparing."
        case .unsupportedSDKOrRuntime:
            return "Apple Intelligence requires macOS 26 or newer."
        }
    }

    var logValue: String {
        switch self {
        case .available:
            return "available"
        case .deviceNotEligible:
            return "device_not_eligible"
        case .appleIntelligenceNotEnabled:
            return "apple_intelligence_not_enabled"
        case .modelNotReady:
            return "model_not_ready"
        case .unsupportedSDKOrRuntime:
            return "unsupported_sdk_or_runtime"
        }
    }
}

enum LocalGemmaAvailability: Equatable {
    case available
    case unsupportedHardware
    case runtimeUnavailable
    case modelNotInstalled

    var isAvailable: Bool {
        self == .available
    }

    var statusText: String {
        switch self {
        case .available:
            return "Local model ready."
        case .unsupportedHardware:
            return "Local model requires Apple Silicon."
        case .runtimeUnavailable:
            return "Local model runtime is not available."
        case .modelNotInstalled:
            return "Local model is not installed."
        }
    }

    var logValue: String {
        switch self {
        case .available:
            return "available"
        case .unsupportedHardware:
            return "unsupported_hardware"
        case .runtimeUnavailable:
            return "runtime_unavailable"
        case .modelNotInstalled:
            return "model_not_installed"
        }
    }
}

enum LLMPostProcessorError: LocalizedError {
    case invalidConfiguration(String)
    case timeout
    case unauthorized
    case provider(String)
    case malformedResponse
    case emptyOutput
    /// The provider stopped on a length limit, so the output is only a prefix
    /// of the answer. Callers fall back to the untouched input.
    case outputTruncated
    case network(String)

    var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(reason):
            return "Invalid LLM configuration: \(reason)"
        case .timeout:
            return "LLM request timed out"
        case .unauthorized:
            return "LLM authorization failed"
        case let .provider(reason):
            return "LLM provider error: \(reason)"
        case .malformedResponse:
            return "LLM provider returned malformed response"
        case .emptyOutput:
            return "LLM returned empty output"
        case .outputTruncated:
            return "LLM output stopped at a length limit"
        case let .network(reason):
            return "Network error: \(reason)"
        }
    }

    var logValue: String {
        switch self {
        case .invalidConfiguration:
            return "invalid_config"
        case .timeout:
            return "timeout"
        case .unauthorized:
            return "unauthorized"
        case .provider:
            return "provider_error"
        case .malformedResponse:
            return "malformed_response"
        case .emptyOutput:
            return "empty_output"
        case .outputTruncated:
            return "output_truncated"
        case .network:
            return "network"
        }
    }
}
