import Foundation

enum LLMModelPreset: String, CaseIterable, Codable {
    case gemini25Flash
    case gpt41Mini
    case custom

    var displayName: String {
        switch self {
        case .gemini25Flash:
            return "google/gemini-2.5-flash"
        case .gpt41Mini:
            return "openai/gpt-4.1-mini"
        case .custom:
            return "Custom"
        }
    }

    var subtitle: String {
        switch self {
        case .gemini25Flash:
            return "Fast, cheap, good quality"
        case .gpt41Mini:
            return "OpenAI, balanced"
        case .custom:
            return "Use any provider model ID"
        }
    }

    var modelId: String {
        switch self {
        case .gemini25Flash:
            return "google/gemini-2.5-flash"
        case .gpt41Mini:
            return "openai/gpt-4.1-mini"
        case .custom:
            return ""
        }
    }
}

struct LLMSettings: Codable, Equatable {
    var isEnabled: Bool = false
    var selectedModelPreset: LLMModelPreset = .gemini25Flash
    var customModelId: String = ""
    var endpointURLString: String = LLMDefaults.defaultEndpointURLString
    var baseSystemPrompt: String = LLMDefaults.defaultBaseSystemPrompt
    var systemPrompt: String = ""
    var keywordsRaw: String = ""
    var timeoutSeconds: Double = 3
    var maxTokens: Int = 128

    enum CodingKeys: String, CodingKey {
        case isEnabled
        case selectedModelPreset
        case customModelId
        case endpointURLString
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
        endpointURLString: String = LLMDefaults.defaultEndpointURLString,
        baseSystemPrompt: String = LLMDefaults.defaultBaseSystemPrompt,
        systemPrompt: String = "",
        keywordsRaw: String = "",
        timeoutSeconds: Double = 3,
        maxTokens: Int = 128
    ) {
        self.isEnabled = isEnabled
        self.selectedModelPreset = selectedModelPreset
        self.customModelId = customModelId
        self.endpointURLString = endpointURLString
        self.baseSystemPrompt = baseSystemPrompt
        self.systemPrompt = systemPrompt
        self.keywordsRaw = keywordsRaw
        self.timeoutSeconds = LLMDefaults.clampTimeout(timeoutSeconds)
        self.maxTokens = LLMDefaults.clampMaxTokens(maxTokens)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        selectedModelPreset = try container.decodeIfPresent(LLMModelPreset.self, forKey: .selectedModelPreset) ?? .gemini25Flash
        customModelId = try container.decodeIfPresent(String.self, forKey: .customModelId) ?? ""
        endpointURLString = try container.decodeIfPresent(String.self, forKey: .endpointURLString) ?? LLMDefaults.defaultEndpointURLString
        baseSystemPrompt = try container.decodeIfPresent(String.self, forKey: .baseSystemPrompt) ?? LLMDefaults.defaultBaseSystemPrompt
        systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt) ?? ""
        keywordsRaw = try container.decodeIfPresent(String.self, forKey: .keywordsRaw) ?? ""
        timeoutSeconds = LLMDefaults.clampTimeout(try container.decodeIfPresent(Double.self, forKey: .timeoutSeconds) ?? 3)
        maxTokens = LLMDefaults.clampMaxTokens(try container.decodeIfPresent(Int.self, forKey: .maxTokens) ?? 128)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(selectedModelPreset, forKey: .selectedModelPreset)
        try container.encode(customModelId, forKey: .customModelId)
        try container.encode(endpointURLString, forKey: .endpointURLString)
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
        case .gemini25Flash, .gpt41Mini:
            return selectedModelPreset.modelId
        }
    }

    var validatedEndpointURL: URL? {
        LLMDefaults.endpointURL(from: endpointURLString)
    }

    var isEndpointValid: Bool {
        validatedEndpointURL != nil
    }

    var endpointValidationError: String? {
        guard !isEndpointValid else {
            return nil
        }
        return "Enter a valid http(s) endpoint URL."
    }
}

enum LLMDefaults {
    static let defaultEndpointURLString = "https://openrouter.ai/api/v1/chat/completions"
    static let minTimeoutSeconds = 1.0
    static let maxTimeoutSeconds = 15.0
    static let minMaxTokens = 32
    static let maxMaxTokens = 512

    static let defaultBaseSystemPrompt = """
Fix transcription errors, misspellings, and misheard words. Preserve the original meaning and tone. Return only the corrected text, nothing else.
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

    static func clampTimeout(_ value: Double) -> Double {
        min(max(value, minTimeoutSeconds), maxTimeoutSeconds)
    }

    static func clampMaxTokens(_ value: Int) -> Int {
        min(max(value, minMaxTokens), maxMaxTokens)
    }

    static func endpointURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let parsed = URL(string: trimmed),
              let scheme = parsed.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        let path = parsed.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.lowercased().hasSuffix("chat/completions") {
            return parsed
        }

        let normalizedPath = path.isEmpty ? "chat/completions" : "\(path)/chat/completions"
        var components = URLComponents(url: parsed, resolvingAgainstBaseURL: false)
        components?.path = "/" + normalizedPath
        return components?.url
    }
}
