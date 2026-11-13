import Foundation

// Closed vocabularies. Because every categorical field on an AnalyticsEvent is
// one of these enums (or a sanitized SafeLabel), the app physically cannot pass
// transcript text, a file path, or any other free string as event data.

public enum DictationSource: String, Sendable, CaseIterable {
    case hotkey, manual, floatingIndicator, unknown
    /// A double tap of the shortcut locked the recording. `hotkey` is a hold.
    case hotkeyLock = "hotkey_lock"
}

public enum DictationDestination: String, Sendable, CaseIterable {
    case systemInsertion, clipboard, onboardingPractice, unknown
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
    /// The key came up while a permission prompt held the start open, so the
    /// recording was cancelled instead of starting with no key held.
    case releasedDuringPrompt = "released_during_prompt"
}

/// Whether a fresh install could start on a built-in, download-free speech model.
public enum SystemDefaultModelOutcome: String, Sendable, CaseIterable {
    case adopted, unavailable, failed
}

/// Why the built-in model was not adopted. Closed set: never raw error text.
public enum SystemDefaultModelReason: String, Sendable, CaseIterable {
    case osTooOld = "os_too_old"
    case transcriberUnavailable = "transcriber_unavailable"
    case unsupportedLanguage = "unsupported_language"
    case assetUnavailable = "asset_unavailable"
    case loadFailed = "load_failed"
    case decodeFailed = "decode_failed"
}

/// What moved onboarding to a step.
public enum OnboardingAdvance: String, Sendable, CaseIterable {
    /// The step's primary button.
    case button
    /// A dictation landed in another app while on the Accessibility step.
    case insertion
}

/// How onboarding ended.
public enum OnboardingEnd: String, Sendable, CaseIterable {
    case finishButton = "finish_button"
    case windowClosed = "window_closed"
}

public enum DictationCancelStage: String, Sendable, CaseIterable {
    case recording, transcribing, formatting, inserting, unknown
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
    case outputTruncated = "output_truncated"
    case providerError = "provider_error"
    case malformedResponse = "malformed_response"
    case providerUnavailable = "provider_unavailable"
    case timeout, network, unauthorized, unknown
}

public enum AudioOutcome: String, Sendable, CaseIterable {
    case complete, tooShort = "too_short", silent, clipped, bufferOverflow = "buffer_overflow"
    case invalidSamples = "invalid_samples", interrupted, unknown
}

/// Why a capture used a microphone other than the saved one or the system default.
public enum InputStandInReason: String, Sendable, CaseIterable {
    case preferredMissing = "preferred_missing"
    case lidClosed = "lid_closed"
    case bluetoothDefault = "bluetooth_default"
}

public enum DictationEmptyReason: String, Sendable, CaseIterable {
    /// The speech detector found no speech, so no engine ran.
    case noSpeech = "no_speech"
    case emptyTranscript = "empty_transcript"
}

/// Whether a double tap of the shortcut can lock a recording. The Globe key
/// cannot while macOS also runs an action on each Globe tap.
public enum DoubleTapAvailability: String, Sendable, CaseIterable {
    case available
    case globeChangesInputSource = "globe_changes_input_source"
    case globeShowsEmoji = "globe_shows_emoji"
    case globeStartsDictation = "globe_starts_dictation"
}

public enum RawTranscriptAction: String, Sendable, CaseIterable {
    case opened, copied
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
    // Appended (append-only wire contract) for the 3-screen flow: `speak` is the
    // mic + first-dictation screen, `type_anywhere` the deferred Accessibility ask.
    // `setup`/`magic_format`/`practice` remain for historical rows only.
    case speak
    case typeAnywhere = "type_anywhere"
    /// The closing screen that names Magic Format, Speech Model and edit-by-voice.
    case more
}

/// Which UI surface initiated an explicit permission ask.
public enum PermissionAskSurface: String, Sendable, CaseIterable {
    case onboarding, settings, dashboard
    case dictationAttempt = "dictation_attempt"
    case insertion
    case meetingStart = "meeting_start"
}

/// How an explicit permission ask ended. Overlay cases are Permiso-specific:
/// the user backed out of the drag helper, or its safety timeout fired.
public enum PermissionAskOutcome: String, Sendable, CaseIterable {
    case granted, denied
    case overlayDismissed = "overlay_dismissed"
    case overlayTimeout = "overlay_timeout"
}

/// Outcome of one onboarding practice dictation attempt. Content-free.
public enum PracticeOutcome: String, Sendable, CaseIterable {
    case success
    case emptyAudio = "empty_audio"
    case error
}

/// Lifecycle of the post-onboarding Magic Format nudge card.
public enum MFNudgeAction: String, Sendable, CaseIterable {
    case shown, dismissed, opened
}

public enum ModelKind: String, Sendable, CaseIterable {
    case asr, cleanup
}

public enum ModelDownloadOutcome: String, Sendable, CaseIterable {
    case started, completed, canceled, failed
}

public enum UpdateActionKind: String, Sendable, CaseIterable {
    case manualCheck = "manual_check", autoToggle = "auto_toggle", channelChange = "channel_change", completed
    case restartToUpdate = "restart_to_update"
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

/// How a meeting recording started.
public enum MeetingSource: String, Sendable, CaseIterable {
    case manual, offer, automatic
}

/// Why a meeting recording stopped.
public enum MeetingStopReason: String, Sendable, CaseIterable {
    case user
    case callEnded = "call_ended"
    case sleep
    case timeLimit = "time_limit"
    case noSpeech = "no_speech"
    case diskFull = "disk_full"
    case writeFailed = "write_failed"
    case quit
}

/// The tracks that recorded until a meeting stopped: the microphone ("you")
/// and the audio of other apps ("them").
public enum MeetingTracks: String, Sendable, CaseIterable {
    case you, them
    case youThem = "you_them"
    case noTrack = "none"
}

/// How a meeting's transcript or summary ended.
public enum MeetingOutcome: String, Sendable, CaseIterable {
    case done
    case noSpeech = "no_speech"
    case failed
}

public enum MeetingSummaryEngine: String, Sendable, CaseIterable {
    case appleIntelligence = "apple_intelligence"
    case localModel = "local_model"
}

/// The card about a call at the top right of the screen.
public enum MeetingCallCardKind: String, Sendable, CaseIterable {
    case offer
    case started
    case callEnded = "call_ended"
}

/// How a call card closed. `timeout`: it closed by itself; on the call-ended
/// card that stops the recording. `callEnded`: the call ended before an
/// answer to the offer.
public enum MeetingCallCardAction: String, Sendable, CaseIterable {
    case record
    case notNow = "not_now"
    case never
    case timeout
    case callEnded = "call_ended"
    case cancel
    case stopNow = "stop_now"
    case keepRecording = "keep_recording"
}
