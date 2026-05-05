import Foundation

enum LLMModelPreset: String, CaseIterable, Codable {
    case gemini25Flash
    case gpt41Mini
    case custom

    var displayName: String {
        switch self {
        case .gemini25Flash:
            return "Gemini 2.5 Flash"
        case .gpt41Mini:
            return "GPT-4.1 Mini"
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

    var magicFormatLabel: String {
        switch self {
        case .gemini25Flash:
            return "Fast"
        case .gpt41Mini:
            return "Balanced"
        case .custom:
            return "Custom"
        }
    }

    var magicFormatDescription: String {
        switch self {
        case .gemini25Flash:
            return "Quick fixes with lower cost."
        case .gpt41Mini:
            return "Best default for most dictation."
        case .custom:
            return "Use the exact model ID supported by your endpoint."
        }
    }

    var modelId: String {
        modelId(for: .openRouter)
    }

    func modelId(for endpointProvider: LLMEndpointProvider) -> String {
        switch self {
        case .gemini25Flash:
            switch endpointProvider {
            case .openRouter:
                return "google/gemini-2.5-flash"
            case .generic:
                return "gemini-2.5-flash"
            }
        case .gpt41Mini:
            switch endpointProvider {
            case .openRouter:
                return "openai/gpt-4.1-mini"
            case .generic:
                return "gpt-4.1-mini"
            }
        case .custom:
            return ""
        }
    }
}

enum LLMEndpointProvider {
    case openRouter
    case generic
}

enum MagicFormatMode: String, CaseIterable, Codable {
    case raw
    case cleanDictation
    case message
    case email
    case notes
    case custom

    var displayName: String {
        switch self {
        case .raw:
            return "Raw"
        case .cleanDictation:
            return "Clean Dictation"
        case .message:
            return "Message"
        case .email:
            return "Email"
        case .notes:
            return "Notes"
        case .custom:
            return "Custom"
        }
    }

    var menuLabel: String {
        switch self {
        case .raw:
            return "Raw"
        case .cleanDictation:
            return "Clean"
        case .message:
            return "Message"
        case .email:
            return "Email"
        case .notes:
            return "Notes"
        case .custom:
            return "Custom"
        }
    }

    var description: String {
        switch self {
        case .raw:
            return "Paste the local transcription exactly as Suniye heard it."
        case .cleanDictation:
            return "Fix obvious transcription errors while preserving your wording and tone."
        case .message:
            return "Make dictated text feel natural for chat, Slack, and quick replies."
        case .email:
            return "Polish dictation into clear, respectful email-ready prose."
        case .notes:
            return "Shape longer dictation into readable notes with light structure."
        case .custom:
            return "Use your own instructions for rewriting dictated text."
        }
    }

    var usesLLM: Bool {
        self != .raw
    }

    var defaultPrompt: String {
        switch self {
        case .raw:
            return ""
        case .cleanDictation:
            return LLMDefaults.defaultBaseSystemPrompt
        case .message:
            return """
Fix transcription errors and make the text sound like a concise, natural message. Preserve the user's meaning, keep the tone casual, and do not add new facts. Return only the rewritten message, nothing else.
"""
        case .email:
            return """
Fix transcription errors and rewrite the text as polished email-ready prose. Preserve the user's meaning, keep the tone warm and professional, and do not add new facts. Return only the rewritten text, nothing else.
"""
        case .notes:
            return """
Fix transcription errors and format the text as clear notes. Use short paragraphs or bullets only when they make the dictation easier to scan. Preserve the user's meaning and do not add new facts. Return only the formatted notes, nothing else.
"""
        case .custom:
            return LLMDefaults.defaultBaseSystemPrompt
        }
    }
}

struct LLMSettings: Codable, Equatable {
    var isEnabled: Bool = false
    var selectedMagicFormatMode: MagicFormatMode = .cleanDictation
    var promptOverridesByMode: [String: String] = [:]
    var selectedModelPreset: LLMModelPreset = .gemini25Flash
    var customModelId: String = ""
    var endpointURLString: String = LLMDefaults.defaultEndpointURLString
    var baseSystemPrompt: String = LLMDefaults.defaultBaseSystemPrompt
    var systemPrompt: String = ""
    var keywordsRaw: String = ""
    var timeoutSeconds: Double = LLMDefaults.defaultTimeoutSeconds
    var maxTokens: Int = LLMDefaults.defaultMaxTokens

    enum CodingKeys: String, CodingKey {
        case isEnabled
        case selectedMagicFormatMode
        case promptOverridesByMode
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
        selectedMagicFormatMode: MagicFormatMode = .cleanDictation,
        promptOverridesByMode: [String: String] = [:],
        selectedModelPreset: LLMModelPreset = .gemini25Flash,
        customModelId: String = "",
        endpointURLString: String = LLMDefaults.defaultEndpointURLString,
        baseSystemPrompt: String = LLMDefaults.defaultBaseSystemPrompt,
        systemPrompt: String = "",
        keywordsRaw: String = "",
        timeoutSeconds: Double = LLMDefaults.defaultTimeoutSeconds,
        maxTokens: Int = LLMDefaults.defaultMaxTokens
    ) {
        self.isEnabled = isEnabled
        self.selectedMagicFormatMode = selectedMagicFormatMode
        self.promptOverridesByMode = Self.normalizedPromptOverrides(promptOverridesByMode)
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
        let decodedMode = try container.decodeIfPresent(MagicFormatMode.self, forKey: .selectedMagicFormatMode)
        promptOverridesByMode = Self.normalizedPromptOverrides(try container.decodeIfPresent([String: String].self, forKey: .promptOverridesByMode) ?? [:])
        selectedModelPreset = try container.decodeIfPresent(LLMModelPreset.self, forKey: .selectedModelPreset) ?? .gemini25Flash
        customModelId = try container.decodeIfPresent(String.self, forKey: .customModelId) ?? ""
        endpointURLString = try container.decodeIfPresent(String.self, forKey: .endpointURLString) ?? LLMDefaults.defaultEndpointURLString
        baseSystemPrompt = try container.decodeIfPresent(String.self, forKey: .baseSystemPrompt) ?? LLMDefaults.defaultBaseSystemPrompt
        systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt) ?? ""
        keywordsRaw = try container.decodeIfPresent(String.self, forKey: .keywordsRaw) ?? ""
        timeoutSeconds = LLMDefaults.clampTimeout(try container.decodeIfPresent(Double.self, forKey: .timeoutSeconds) ?? LLMDefaults.defaultTimeoutSeconds)
        maxTokens = LLMDefaults.clampMaxTokens(try container.decodeIfPresent(Int.self, forKey: .maxTokens) ?? LLMDefaults.defaultMaxTokens)

        if let decodedMode {
            selectedMagicFormatMode = decodedMode
        } else {
            let legacyPrompt = Self.legacyMergedPromptForMigration(basePrompt: baseSystemPrompt, systemPrompt: systemPrompt)
            if legacyPrompt == LLMDefaults.defaultBaseSystemPrompt {
                selectedMagicFormatMode = .cleanDictation
            } else {
                selectedMagicFormatMode = .custom
                promptOverridesByMode[MagicFormatMode.custom.rawValue] = legacyPrompt
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(selectedMagicFormatMode, forKey: .selectedMagicFormatMode)
        try container.encode(promptOverridesByMode, forKey: .promptOverridesByMode)
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
        if promptOverridesByMode.isEmpty,
           selectedMagicFormatMode == .cleanDictation,
           (baseSystemPrompt != LLMDefaults.defaultBaseSystemPrompt || !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            return Self.legacyComposedPrompt(basePrompt: baseSystemPrompt, systemPrompt: systemPrompt)
        }

        return effectivePrompt(for: selectedMagicFormatMode)
    }

    func effectivePrompt(for mode: MagicFormatMode) -> String {
        let override = promptOverride(for: mode)
        if let override {
            return override
        }
        return mode.defaultPrompt
    }

    func promptOverride(for mode: MagicFormatMode) -> String? {
        guard let value = promptOverridesByMode[mode.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    func hasPromptOverride(for mode: MagicFormatMode) -> Bool {
        promptOverride(for: mode) != nil
    }

    private static func legacyComposedPrompt(basePrompt: String, systemPrompt: String) -> String {
        let normalizedBase = basePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUser = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)

        var sections: [String] = []
        sections.append(normalizedBase.isEmpty ? LLMDefaults.defaultBaseSystemPrompt : normalizedBase)

        if !normalizedUser.isEmpty {
            sections.append("User customization:\n\(normalizedUser)")
        }

        return sections.joined(separator: "\n\n")
    }

    private static func legacyMergedPromptForMigration(basePrompt: String, systemPrompt: String) -> String {
        let normalizedBase = basePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedExtra = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let visiblePrompt = normalizedBase.isEmpty ? LLMDefaults.defaultBaseSystemPrompt : normalizedBase

        guard !normalizedExtra.isEmpty else {
            return visiblePrompt
        }

        if visiblePrompt == normalizedExtra || visiblePrompt.hasSuffix("\n\n\(normalizedExtra)") {
            return visiblePrompt
        }

        return "\(visiblePrompt)\n\n\(normalizedExtra)"
    }

    private static func normalizedPromptOverrides(_ overrides: [String: String]) -> [String: String] {
        var normalized: [String: String] = [:]
        for mode in MagicFormatMode.allCases {
            guard let value = overrides[mode.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else {
                continue
            }
            normalized[mode.rawValue] = value
        }
        return normalized
    }

    var endpointProvider: LLMEndpointProvider {
        LLMDefaults.endpointProvider(for: validatedEndpointURL)
    }

    var validatedModelId: String? {
        switch selectedModelPreset {
        case .custom:
            return LLMDefaults.normalizedModelId(customModelId)
        case .gemini25Flash, .gpt41Mini:
            return selectedModelPreset.modelId(for: endpointProvider)
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
        return "Enter a valid service URL."
    }

    var modelValidationError: String? {
        guard selectedModelPreset == .custom, validatedModelId == nil else {
            return nil
        }
        return "Enter a valid custom model name."
    }

    func displayModelId(for preset: LLMModelPreset) -> String {
        switch preset {
        case .custom:
            return "Custom model ID"
        case .gemini25Flash, .gpt41Mini:
            return preset.modelId(for: endpointProvider)
        }
    }
}

enum LLMDefaults {
    static let defaultEndpointURLString = "https://openrouter.ai/api/v1/chat/completions"
    static let defaultTimeoutSeconds = 3.0
    static let defaultMaxTokens = 128
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
        if trimmed.contains("\n") || trimmed.contains("\r") || trimmed.contains("\t") {
            return false
        }
        return true
    }

    static func normalizedModelId(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidModelId(trimmed) else {
            return nil
        }
        return trimmed
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
              var components = URLComponents(url: parsed, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty else {
            return nil
        }

        let path = parsed.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.lowercased().hasSuffix("chat/completions") {
            return parsed
        }

        let normalizedPath = path.isEmpty ? "chat/completions" : "\(path)/chat/completions"
        components.path = "/" + normalizedPath
        return components.url
    }

    static func endpointProvider(for endpointURL: URL?) -> LLMEndpointProvider {
        guard let host = endpointURL?.host?.lowercased() else {
            return .openRouter
        }
        if host == "openrouter.ai" || host.hasSuffix(".openrouter.ai") {
            return .openRouter
        }
        return .generic
    }
}
