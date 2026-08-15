import Foundation

/// The closed set of analytics events. This is the app's ONLY way to record
/// telemetry — there is no `track(name:props:)` escape hatch — so it is
/// impossible to emit an event the schema doesn't know about, and impossible to
/// attach free-text data (every associated value is a number, bool, enum, or
/// SafeLabel).
///
/// Cases are append-only: adding a case (or an optional field to one) is safe;
/// renaming/removing one is a breaking schema change. The wire `name` maps to
/// Analytics Engine `blob1`, and `props` map to the positional slots recorded
/// in the ingest Worker's field→slot registry.
public enum AnalyticsEvent: Sendable {
    case appLaunch(device: DeviceProfile, settings: SettingsSnapshot, firstLaunch: Bool)
    case sessionEnd(durationMs: Int, eventCount: Int, cleanExit: Bool)

    case dictationCompleted(DictationMetrics)
    case dictationBlocked(reason: DictationBlockedReason)
    case dictationCancelled(stage: DictationCancelStage)
    case dictationEmpty
    /// Emitted when an inserted dictation's edit-learning session finalizes. The
    /// bucket is a coarse % of the dictation the user corrected (0..100, content-
    /// free) — an ASR/cleanup accuracy proxy that arrives after `dictation_completed`.
    case dictationEdited(editRateBucket: Int)

    case audioCaptureFailed(outcome: AudioOutcome)
    case audioCaptureInterrupted(reason: AudioInterruptionReason)
    case audioBackendUsed(backend: SafeLabel, fallbackOccurred: Bool, rung: Int)

    case permissionTransition(kind: PermissionKind, granted: Bool)
    /// A permission was explicitly asked for (system prompt shown, Permiso overlay
    /// presented, or Settings deep-link offered after denial) and resolved.
    /// `permission_transition` stays the passive state-change signal; this one
    /// gives grant-rate-at-ask-time per surface.
    case permissionRequest(kind: PermissionKind, surface: PermissionAskSurface, outcome: PermissionAskOutcome)
    /// `resumed` is true when the step was re-shown by launch resume rather than
    /// reached by a user action in this session.
    case onboardingStep(step: OnboardingStepName, granted: Bool?, resumed: Bool?)
    /// One practice dictation attempt on the Speak screen. `attempt` is 1-based
    /// and capped by the caller; outcome is a closed enum — never content.
    case onboardingPracticeResult(outcome: PracticeOutcome, attempt: Int)
    /// Fired exactly once from finishOnboarding(): the state the user exited
    /// onboarding in, plus wall-clock duration of the final onboarding session.
    case onboardingOutcome(durationMs: Int?, practiced: Bool, micGranted: Bool, axGranted: Bool, modelReady: Bool)
    /// Post-onboarding Magic Format nudge card lifecycle (impressions are the
    /// denominator for nudge-conversion analysis).
    case mfNudge(action: MFNudgeAction)

    case modelChanged(kind: ModelKind, model: SafeLabel)
    case modelDownload(kind: ModelKind, model: SafeLabel, outcome: ModelDownloadOutcome, durationMs: Int?)
    case modelLoad(model: SafeLabel, loadMs: Int, evictedByKeepAlive: Bool)
    /// One user-facing local-LLM generation (polish / rewrite): llama-server's
    /// per-request counters. `cache_hit` = more of the prompt was reused from the KV
    /// cache than freshly processed — the prewarm probe primed it (a primed polish is
    /// ~2.4k cached / ~40 processed; a miss is ~0 / ~2.5k, and an unrelated previous
    /// request leaves only a few chat-template tokens cached). Counts and timings only.
    case llmGeneration(model: SafeLabel, promptTokens: Int, cachedTokens: Int, predictedTokens: Int, prefillMs: Int, decodeMs: Int)

    case vocabLearnedFromEdit(count: Int)
    case featureToggled(feature: TrackableFeature, enabled: Bool)
    case updateAction(kind: UpdateActionKind, fromVersion: SafeLabel?, toVersion: SafeLabel?)
    case error(type: AnalyticsErrorType, code: AnalyticsErrorCode)

    /// Self-observability of the analytics pipeline itself.
    case analyticsHealth(queueDepth: Int, uploadFailures: Int, evictedByTTL: Int, evictedBySize: Int)

    /// The wire event name (Analytics Engine `blob1`, snake_case, stable).
    public var name: String {
        switch self {
        case .appLaunch: return "app_launch"
        case .sessionEnd: return "session_end"
        case .dictationCompleted: return "dictation_completed"
        case .dictationBlocked: return "dictation_blocked"
        case .dictationCancelled: return "dictation_cancelled"
        case .dictationEmpty: return "dictation_empty"
        case .dictationEdited: return "dictation_edited"
        case .audioCaptureFailed: return "audio_capture_failed"
        case .audioCaptureInterrupted: return "audio_capture_interrupted"
        case .audioBackendUsed: return "audio_backend_used"
        case .permissionTransition: return "permission_transition"
        case .permissionRequest: return "permission_request"
        case .onboardingStep: return "onboarding_step"
        case .onboardingPracticeResult: return "onboarding_practice_result"
        case .onboardingOutcome: return "onboarding_outcome"
        case .mfNudge: return "mf_nudge"
        case .modelChanged: return "model_changed"
        case .modelDownload: return "model_download"
        case .modelLoad: return "model_load"
        case .llmGeneration: return "llm_generation"
        case .vocabLearnedFromEdit: return "vocab_learned_from_edit"
        case .featureToggled: return "feature_toggled"
        case .updateAction: return "update_action"
        case .error: return "error"
        case .analyticsHealth: return "analytics_health"
        }
    }

    /// Typed properties for this event. Keys are the canonical field names the
    /// ingest Worker maps to positional Analytics Engine slots.
    public var props: [String: AnalyticsValue] {
        switch self {
        case let .appLaunch(device, settings, firstLaunch):
            var out = device.props
            out.merge(settings.props) { current, _ in current }
            out["first_launch"] = .bool(firstLaunch)
            return out
        case let .sessionEnd(durationMs, eventCount, cleanExit):
            return ["duration_ms": .int(durationMs), "event_count": .int(eventCount), "clean_exit": .bool(cleanExit)]
        case let .dictationCompleted(metrics):
            return metrics.props
        case let .dictationBlocked(reason):
            return ["reason": .label(reason)]
        case let .dictationCancelled(stage):
            return ["stage": .label(stage)]
        case .dictationEmpty:
            return [:]
        case let .dictationEdited(editRateBucket):
            return ["edit_rate_bucket": .int(editRateBucket)]
        case let .audioCaptureFailed(outcome):
            return ["outcome": .label(outcome)]
        case let .audioCaptureInterrupted(reason):
            return ["reason": .label(reason)]
        case let .audioBackendUsed(backend, fallbackOccurred, rung):
            return ["backend": .label(backend), "fallback_occurred": .bool(fallbackOccurred), "rung": .int(rung)]
        case let .permissionTransition(kind, granted):
            return ["kind": .label(kind), "granted": .bool(granted)]
        case let .permissionRequest(kind, surface, outcome):
            // `kind` and `outcome` land in typed AE slots; `surface` rides the
            // blob20 props-JSON backstop until it earns a slot.
            return ["kind": .label(kind), "surface": .label(surface), "outcome": .label(outcome)]
        case let .onboardingStep(step, granted, resumed):
            var out: [String: AnalyticsValue] = ["step": .label(step)]
            if let granted { out["granted"] = .bool(granted) }
            if let resumed { out["resumed"] = .bool(resumed) }
            return out
        case let .onboardingPracticeResult(outcome, attempt):
            return ["outcome": .label(outcome), "attempt": .int(attempt)]
        case let .onboardingOutcome(durationMs, practiced, micGranted, axGranted, modelReady):
            var out: [String: AnalyticsValue] = [
                "practiced": .bool(practiced),
                "mic_granted": .bool(micGranted),
                "ax_granted": .bool(axGranted),
                "model_ready": .bool(modelReady),
            ]
            if let durationMs { out["duration_ms"] = .int(durationMs) }
            return out
        case let .mfNudge(action):
            return ["action": .label(action)]
        case let .modelChanged(kind, model):
            return ["kind": .label(kind), "model": .label(model)]
        case let .modelDownload(kind, model, outcome, durationMs):
            var out: [String: AnalyticsValue] = ["kind": .label(kind), "model": .label(model), "outcome": .label(outcome)]
            if let durationMs { out["duration_ms"] = .int(durationMs) }
            return out
        case let .modelLoad(model, loadMs, evicted):
            return ["model": .label(model), "load_ms": .int(loadMs), "evicted_by_keepalive": .bool(evicted)]
        case let .llmGeneration(model, promptTokens, cachedTokens, predictedTokens, prefillMs, decodeMs):
            return [
                "model": .label(model),
                "prompt_tokens": .int(promptTokens),
                "cached_tokens": .int(cachedTokens),
                "predicted_tokens": .int(predictedTokens),
                "prefill_ms": .int(prefillMs),
                "decode_ms": .int(decodeMs),
                "cache_hit": .bool(cachedTokens > promptTokens),
            ]
        case let .vocabLearnedFromEdit(count):
            return ["count": .int(count)]
        case let .featureToggled(feature, enabled):
            return ["feature": .label(feature), "enabled": .bool(enabled)]
        case let .updateAction(kind, fromVersion, toVersion):
            var out: [String: AnalyticsValue] = ["kind": .label(kind)]
            if let fromVersion { out["from_version"] = .label(fromVersion) }
            if let toVersion { out["to_version"] = .label(toVersion) }
            return out
        case let .error(type, code):
            return ["type": .label(type), "code": .label(code)]
        case let .analyticsHealth(queueDepth, uploadFailures, evictedByTTL, evictedBySize):
            return [
                "queue_depth": .int(queueDepth),
                "upload_failures": .int(uploadFailures),
                "evicted_by_ttl": .int(evictedByTTL),
                "evicted_by_size": .int(evictedBySize),
            ]
        }
    }
}
