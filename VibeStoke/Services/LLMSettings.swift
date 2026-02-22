import Foundation

enum LLMModelPreset: String, CaseIterable, Codable {
    case gemini25Flash
    case gptOss20b
    case custom

    var displayName: String {
        switch self {
        case .gemini25Flash:
            return "Gemini 2.5 Flash"
        case .gptOss20b:
            return "GPT-OSS 20B"
        case .custom:
            return "Custom"
        }
    }

    var modelId: String {
        switch self {
        case .gemini25Flash:
            return "google/gemini-2.5-flash"
        case .gptOss20b:
            return "openai/gpt-oss-20b"
        case .custom:
            return ""
        }
    }
}

struct LLMSettings: Codable, Equatable {
    var isEnabled: Bool = false
    var selectedModelPreset: LLMModelPreset = .gemini25Flash
    var customModelId: String = ""
    var systemPrompt: String = LLMDefaults.defaultSystemPrompt
    var keywordsRaw: String = ""
    var timeoutSeconds: Double = 3
    var maxTokens: Int = 128

    var keywords: [String] {
        LLMDefaults.parseKeywords(from: keywordsRaw)
    }

    var effectiveModelId: String {
        switch selectedModelPreset {
        case .custom:
            let custom = customModelId.trimmingCharacters(in: .whitespacesAndNewlines)
            if LLMDefaults.isValidModelId(custom) {
                return custom
            }
            return LLMModelPreset.gemini25Flash.modelId
        case .gemini25Flash, .gptOss20b:
            return selectedModelPreset.modelId
        }
    }
}

enum LLMDefaults {
    static let defaultSystemPrompt = """
You are a conservative text-polishing assistant for speech-to-text output.
Fix punctuation, capitalization, and obvious grammar issues while preserving original wording and intent.
Do not add new facts.
Return only the final polished plain text.
"""

    static func parseKeywords(from raw: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",\n")
        let parts = raw
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var seen = Set<String>()
        var result: [String] = []
        for keyword in parts {
            let key = keyword.lowercased()
            if seen.insert(key).inserted {
                result.append(keyword)
            }
        }
        return result
    }

    static func isValidModelId(_ modelId: String) -> Bool {
        let trimmed = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }
        if trimmed.contains("\n") || trimmed.contains("\t") {
            return false
        }
        return trimmed.contains("/")
    }
}
