import Foundation

struct LLMSettingsPromptMigrationResult: Equatable {
    let settings: LLMSettings
    let shouldPersist: Bool
}

extension LLMSettings {
    func normalizedForCurrentPromptSchema() -> LLMSettingsPromptMigrationResult {
        let mergedPrompt = Self.mergedMagicFormatPrompt(
            basePrompt: baseSystemPrompt,
            extraPrompt: systemPrompt
        )
        let providerPromptMigration = Self.legacyProviderPromptMigration(
            settings: self,
            mergedPrompt: mergedPrompt
        )
        let shouldMigrateProviderPrompts = providerPromptMigration != nil
            && (!hasExplicitAppleSystemPrompt || !hasExplicitGemmaSystemPrompt)
        let normalized = LLMSettings(
            isEnabled: isEnabled,
            provider: provider,
            selectedModelPreset: selectedModelPreset,
            customModelId: customModelId,
            endpointURLString: endpointURLString,
            baseSystemPrompt: mergedPrompt,
            appleSystemPrompt: Self.loadedProviderPrompt(
                explicitPrompt: composedAppleSystemPrompt,
                hasExplicitPrompt: hasExplicitAppleSystemPrompt,
                defaultPrompt: LLMDefaults.defaultAppleMagicFormatPrompt,
                migrationPrompt: providerPromptMigration
            ),
            gemmaSystemPrompt: Self.loadedProviderPrompt(
                explicitPrompt: composedGemmaSystemPrompt,
                hasExplicitPrompt: hasExplicitGemmaSystemPrompt,
                defaultPrompt: LLMDefaults.defaultGemmaMagicFormatPrompt,
                migrationPrompt: providerPromptMigration
            ),
            systemPrompt: "",
            keywordsRaw: keywordsRaw,
            autoLearnedKeywordsRaw: autoLearnedKeywordsRaw,
            learnFromEditsEnabled: learnFromEditsEnabled,
            timeoutSeconds: LLMDefaults.defaultTimeoutSeconds,
            maxTokens: LLMDefaults.defaultMaxTokens,
            localModelKeepAlive: localModelKeepAlive,
            appPromptBindings: appPromptBindings
        )
        let shouldPersist = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || timeoutSeconds != LLMDefaults.defaultTimeoutSeconds
            || maxTokens != LLMDefaults.defaultMaxTokens
            || shouldMigrateProviderPrompts
        return LLMSettingsPromptMigrationResult(settings: normalized, shouldPersist: shouldPersist)
    }

    private static func mergedMagicFormatPrompt(basePrompt: String, extraPrompt: String) -> String {
        let normalizedBase = basePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedExtra = extraPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let visiblePrompt = normalizedBase.isEmpty ? LLMDefaults.defaultBaseSystemPrompt : normalizedBase

        guard !normalizedExtra.isEmpty else {
            return visiblePrompt
        }

        if visiblePrompt == normalizedExtra || visiblePrompt.hasSuffix("\n\n\(normalizedExtra)") {
            return visiblePrompt
        }

        return "\(visiblePrompt)\n\n\(normalizedExtra)"
    }

    private static func legacyProviderPromptMigration(settings: LLMSettings, mergedPrompt: String) -> String? {
        let normalizedBase = settings.baseSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let visiblePrompt = normalizedBase.isEmpty ? LLMDefaults.defaultBaseSystemPrompt : normalizedBase
        let normalizedExtra = settings.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let legacyPromptWasCustomized = !normalizedExtra.isEmpty || visiblePrompt != LLMDefaults.defaultBaseSystemPrompt
        return legacyPromptWasCustomized ? mergedPrompt : nil
    }

    private static func loadedProviderPrompt(
        explicitPrompt: String,
        hasExplicitPrompt: Bool,
        defaultPrompt: String,
        migrationPrompt: String?
    ) -> String {
        guard !hasExplicitPrompt else {
            let normalized = explicitPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.isEmpty ? defaultPrompt : normalized
        }
        return migrationPrompt ?? defaultPrompt
    }
}
