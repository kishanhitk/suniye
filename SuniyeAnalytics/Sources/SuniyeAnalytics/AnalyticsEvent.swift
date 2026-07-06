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
    case onboardingStep(step: OnboardingStepName, granted: Bool?)

    case modelChanged(kind: ModelKind, model: SafeLabel)
    case modelDownload(kind: ModelKind, model: SafeLabel, outcome: ModelDownloadOutcome, durationMs: Int?)
    case modelLoad(model: SafeLabel, loadMs: Int, evictedByKeepAlive: Bool)

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
        case .onboardingStep: return "onboarding_step"
        case .modelChanged: return "model_changed"
        case .modelDownload: return "model_download"
        case .modelLoad: return "model_load"
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
        case let .onboardingStep(step, granted):
            var out: [String: AnalyticsValue] = ["step": .label(step)]
            if let granted { out["granted"] = .bool(granted) }
            return out
        case let .modelChanged(kind, model):
            return ["kind": .label(kind), "model": .label(model)]
        case let .modelDownload(kind, model, outcome, durationMs):
            var out: [String: AnalyticsValue] = ["kind": .label(kind), "model": .label(model), "outcome": .label(outcome)]
            if let durationMs { out["duration_ms"] = .int(durationMs) }
            return out
        case let .modelLoad(model, loadMs, evicted):
            return ["model": .label(model), "load_ms": .int(loadMs), "evicted_by_keepalive": .bool(evicted)]
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
