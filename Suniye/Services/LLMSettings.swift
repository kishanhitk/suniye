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
    var baseSystemPrompt: String = LLMDefaults.defaultBaseSystemPrompt
    var systemPrompt: String = ""
    var keywordsRaw: String = ""
    var timeoutSeconds: Double = 3
    var maxTokens: Int = 128

    enum CodingKeys: String, CodingKey {
        case isEnabled
        case selectedModelPreset
        case customModelId
        case baseSystemPrompt
        case systemPrompt
        case keywordsRaw
        case timeoutSeconds
        case maxTokens
    }

    init() {}

    init(
        isEnabled: Bool = false,
        selectedModelPreset: LLMModelPreset = .gemini25Flash,
        customModelId: String = "",
        baseSystemPrompt: String = LLMDefaults.defaultBaseSystemPrompt,
        systemPrompt: String = "",
        keywordsRaw: String = "",
        timeoutSeconds: Double = 3,
        maxTokens: Int = 128
    ) {
        self.isEnabled = isEnabled
        self.selectedModelPreset = selectedModelPreset
        self.customModelId = customModelId
        self.baseSystemPrompt = baseSystemPrompt
        self.systemPrompt = systemPrompt
        self.keywordsRaw = keywordsRaw
        self.timeoutSeconds = timeoutSeconds
        self.maxTokens = maxTokens
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        selectedModelPreset = try container.decodeIfPresent(LLMModelPreset.self, forKey: .selectedModelPreset) ?? .gemini25Flash
        customModelId = try container.decodeIfPresent(String.self, forKey: .customModelId) ?? ""
        baseSystemPrompt = try container.decodeIfPresent(String.self, forKey: .baseSystemPrompt) ?? LLMDefaults.defaultBaseSystemPrompt
        systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt) ?? ""
        keywordsRaw = try container.decodeIfPresent(String.self, forKey: .keywordsRaw) ?? ""
        timeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .timeoutSeconds) ?? 3
        maxTokens = try container.decodeIfPresent(Int.self, forKey: .maxTokens) ?? 128
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(selectedModelPreset, forKey: .selectedModelPreset)
        try container.encode(customModelId, forKey: .customModelId)
        try container.encode(baseSystemPrompt, forKey: .baseSystemPrompt)
        try container.encode(systemPrompt, forKey: .systemPrompt)
        try container.encode(keywordsRaw, forKey: .keywordsRaw)
        try container.encode(timeoutSeconds, forKey: .timeoutSeconds)
        try container.encode(maxTokens, forKey: .maxTokens)
    }

    var keywords: [String] {
        LLMDefaults.parseKeywords(from: keywordsRaw)
    }

    var composedSystemPrompt: String {
        let normalizedBase = baseSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUser = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)

        var sections: [String] = []
        sections.append(normalizedBase.isEmpty ? LLMDefaults.defaultBaseSystemPrompt : normalizedBase)

        if !normalizedUser.isEmpty {
            sections.append("User customization:\n\(normalizedUser)")
        }

        return sections.joined(separator: "\n\n")
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
    static let defaultBaseSystemPrompt = """
You are a context-aware dictation repair assistant for a software engineer.
Infer intended meaning when transcription is fragmented or incorrect.
Fix punctuation, capitalization, and grammar while preserving intent and brevity.
Remove filler words and disfluencies when they do not add meaning.
Preserve technical tokens exactly when possible.
Return plain text only.
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
