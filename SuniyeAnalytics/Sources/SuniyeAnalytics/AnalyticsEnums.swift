import Foundation

// Closed vocabularies. Because every categorical field on an AnalyticsEvent is
// one of these enums (or a sanitized SafeLabel), the app physically cannot pass
// transcript text, a file path, or any other free string as event data.

public enum DictationSource: String, Sendable, CaseIterable {
    case hotkey, manual, floatingIndicator, unknown
}

public enum DictationDestination: String, Sendable, CaseIterable {
    case systemInsertion, onboardingPractice, unknown
}

public enum InsertionMethod: String, Sendable, CaseIterable {
    case directAX = "direct_ax"
    case clipboard
    case unknown
}

/// Coarse category of the app text was inserted into. Derived locally from the
/// frontmost bundle id; the raw bundle id is never sent (that would be a usage
/// fingerprint).
public enum TargetCategory: String, Sendable, CaseIterable {
    case email, editor, browser, terminal, chat, notes, ide, office, other
}

public enum DictationBlockedReason: String, Sendable, CaseIterable {
    case wrongPhase = "wrong_phase"
    case micDenied = "mic_denied"
    case accessibilityDenied = "accessibility_denied"
    case unknown
}

public enum DictationCancelStage: String, Sendable, CaseIterable {
    case recording, transcribing, formatting, inserting, unknown
}

/// Terminal state of a Command Mode agent run.
public enum CommandOutcome: String, Sendable, CaseIterable {
    /// The agent reached a terminal tool (e.g. `finish`).
    case completed
    /// Repeat-guard fired — the model looped on an action instead of finishing.
    case stalled
    /// Ran out of steps before finishing.
    case stepLimit = "step_limit"
    /// The user hit the Esc kill-switch.
    case cancelled
    /// The model never produced a valid, parseable action.
    case brainFailure = "brain_failure"
    /// Nothing intelligible was said.
    case emptyCommand = "empty_command"
    case unknown
}

/// Why a Command Mode run couldn't start.
public enum CommandBlockedReason: String, Sendable, CaseIterable {
    case wrongPhase = "wrong_phase"
    case micDenied = "mic_denied"
    case accessibilityDenied = "accessibility_denied"
    case magicFormatUnavailable = "magic_format_unavailable"
    case unknown
}

public enum CleanupProvider: String, Sendable, CaseIterable {
    case automatic, appleFoundationModels = "apple", localGemma = "local_gemma", openAICompatible = "openai_compatible", unknown
}

public enum CleanupFallbackReason: String, Sendable, CaseIterable {
    case invalidEndpoint = "invalid_endpoint"
    case invalidModel = "invalid_model"
    case missingKey = "missing_key"
    case keyReadFailed = "key_read_failed"
    case invalidConfig = "invalid_config"
    case emptyOutput = "empty_output"
    case providerError = "provider_error"
    case malformedResponse = "malformed_response"
    case providerUnavailable = "provider_unavailable"
    case timeout, network, unauthorized, unknown
}

public enum AudioOutcome: String, Sendable, CaseIterable {
    case complete, tooShort = "too_short", silent, clipped, bufferOverflow = "buffer_overflow"
    case invalidSamples = "invalid_samples", interrupted, unknown
}

public enum AudioInterruptionReason: String, Sendable, CaseIterable {
    case deviceChanged = "device_changed"
    case deviceUnavailable = "device_unavailable"
    case formatChanged = "format_changed"
    case serviceRestarted = "service_restarted"
    case engineConfigChanged = "engine_config_changed"
    case inputMuted = "input_muted"
    case ioStoppedAbnormally = "io_stopped"
    case noAudioArriving = "no_audio"
    case maximumDurationReached = "max_duration"
    case systemSleep = "system_sleep"
    case unknown
}

public enum PermissionKind: String, Sendable, CaseIterable {
    case microphone, accessibility
}

public enum OnboardingStepName: String, Sendable, CaseIterable {
    case welcome, setup, magicFormat = "magic_format", practice, completed
}

public enum ModelKind: String, Sendable, CaseIterable {
    case asr, cleanup
}

public enum ModelDownloadOutcome: String, Sendable, CaseIterable {
    case started, completed, canceled, failed
}

public enum UpdateActionKind: String, Sendable, CaseIterable {
    case manualCheck = "manual_check", autoToggle = "auto_toggle", channelChange = "channel_change", completed
}

/// A small, closed set of feature toggles worth tracking adoption for.
public enum TrackableFeature: String, Sendable, CaseIterable {
    case magicFormat = "magic_format"
    case autoSubmit = "auto_submit"
    case echoCancellation = "echo_cancellation"
    case soundFeedback = "sound_feedback"
    case learnFromEdits = "learn_from_edits"
    case accessibilityDragHelper = "accessibility_drag_helper"
    case shareAnalytics = "share_analytics"
    case commandMode = "command_mode"
}

public enum AnalyticsErrorType: String, Sendable, CaseIterable {
    case transcription, insertion, audioCapture = "audio_capture", modelLoad = "model_load"
    case magicFormat = "magic_format", update, upload, unknown
}

/// Machine error codes only — never a message, path, or `localizedDescription`.
public enum AnalyticsErrorCode: String, Sendable, CaseIterable {
    case timeout, network, unauthorized, notFound = "not_found", cancelled
    case decoding, permissionDenied = "permission_denied", diskFull = "disk_full"
    case invalidState = "invalid_state", unknown
}
