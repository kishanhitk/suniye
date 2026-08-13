# Always-listening Computer Use: implementation plan

Date: 2026-08-13
Status: Proposed. No code written. Companion document: `always-listening-ux-plan.md`.
Branch: `kis-169-always-listening`, stacked on `kis-169-computer-use-parity` (PR #93).

Safety controls (deterministic spoken stop, per-action guards) are deferred until pre-release
by product decision. This plan covers the full feature without them.

## 1. Feasibility

The bundled sherpa-onnx dylib (`Suniye/Frameworks/libsherpa-onnx-c-api.dylib`, version 1.12.25)
exports `SherpaOnnxCreateKeywordSpotter` and `SherpaOnnxCreateVoiceActivityDetector`.

A test harness ran the pretrained English keyword-spotting model
(`sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01`, int8 files, 5 MB total) against
synthesized speech. Results:

- 3 of 3 positive samples detected. Samples were "Hey Suniye" synthesized with two voices,
  with and without a trailing task sentence.
- 0 of 6 negative samples produced a false alarm. Negatives included "hey sunny day",
  "hey sonny", "hey so nice", and "hey seriously".

### Working configuration

Keywords are passed in memory through `keywords_buf`. No keywords file is written to disk.
Keyword lines are BPE token sequences. They are computed once with the model's `bpe.model` and
stored as constants. No tokenizer runs at runtime.

```
▁HE Y ▁SU N I Y E :3.0 #0.05
▁HE Y ▁SO ON I Y E :3.0 #0.05
▁HE Y ▁SU N I Y A Y :3.0 #0.05
▁HE Y ▁SO ON I Y A Y :3.0 #0.05
▁HE Y ▁SU NE E Y E :3.0 #0.05
▁HE Y ▁SU N I :3.0 #0.05
```

In testing, the final variant (`▁HE Y ▁SU N I`) produced all detections. Keep the other
variants for coverage.

Spotter configuration: `max_active_paths` 4, `num_trailing_blanks` 1, `keywords_score` 2.0,
`keywords_threshold` 0.25, with per-keyword boost and threshold overrides as shown above.
After each detection, call `SherpaOnnxResetKeywordStream` and continue feeding samples.

### Known limits of this validation

- All test audio was synthesized. Thresholds must be tuned with live microphone audio. The
  "Try wake phrase" flow in Settings supports this.
- The model is English-acoustic. It detects the fixed phrase only; it is not general ASR.
- CPU cost is a 3.3M-parameter streaming zipformer. It is negligible.

## 2. Architecture

### New components

```
Suniye/Services/
  WakeWordDetector.swift             actor; wraps SherpaOnnxKeywordSpotter
  VoiceTurnEndpointer.swift          pure logic; detects end of speech from frames
  VoiceActivationStateMachine.swift  pure value type; the seven UX states
  VoiceActivationController.swift    @MainActor @Observable; owns the loop
  SpeechOutputService.swift          protocol; Chatterbox (local MLX helper) implementation
```

**WakeWordDetector.** Defines `protocol WakeWordDetecting` with a sherpa-backed implementation.
API: `start()`, `accept(samples:sampleRate:) -> WakeWordHit?`, `reset()`, `stop()`. Follows the
`TranscriptionServiceProtocol` dependency-injection pattern so tests use a stub.

**VoiceTurnEndpointer.** Decides when a spoken turn has ended. Primary signal: sherpa silero VAD
(`SherpaOnnxCreateVoiceActivityDetector`, model size 1.7 MB). Fallback signal: the existing
22-band level meter energy. Tunable parameters: minimum speech 300 ms, trailing silence 900 ms,
maximum turn 30 s, no-speech timeout after wake 5 s. The type is pure and unit-testable.

**VoiceActivationStateMachine.** Encodes the user-visible states from the UX plan and their
legal transitions, including the manual-handoff state ("Your turn") and the optional follow-up
window after completion. Emits effects: start turn capture, submit turn, set indicator state.
The type is pure and unit-testable.

One behavior sits in `VoiceActivationController` rather than the conversation path:

- **Follow-up window.** When enabled in Settings and a run ends in Done, the controller keeps
  the endpointer armed for about 6 seconds without requiring a wake hit. Captured speech in the
  window submits as a normal turn; silence returns to Ready. Off by default.

Mode control by voice goes through the model (decision 2026-08-14; an earlier local
phrase-matcher design was dropped). Add a `set_voice_activation` tool to
`ComputerUseModelToolContract` with a single `enabled: false` action; the system prompt
describes when to call it. This handles any phrasing and any language the model understands.
The tool result confirms, the coordinator forwards it to `AppState`, and the state machine
moves to Off with the indicator flash and cue sound. During a provider outage the spoken
off-switch is unavailable; the physical routes (menu bar, shortcut, Settings) are the
guaranteed exits.

**VoiceActivationController.** Connects the other components. It subscribes to audio frames,
drives the detector, endpointer, and state machine, calls
`ComputerUseCoordinator.submitVoiceTask`, and maps states to the floating indicator through
AppState callbacks. Constructor-injected dependencies: detector, endpointer clock, coordinator
(as `ComputerUseVoiceTaskHandling`), capture service, transcription service, settings store.

### Audio capture: listen tap

`AudioCaptureService` allows exactly one `ActiveCapture`. `startCapture` discards any previous
capture, and sessions have a 10-minute cap. The always-listening path therefore does not use
capture sessions. Instead, add a tap API:

```swift
func startListenTap(onFrames: @Sendable ([Float], Double) -> Void) async throws
func stopListenTap() async
```

Behavior:

- The tap keeps the audio engine and ring-buffer drain running continuously and delivers
  frames of about 20 ms to one subscriber.
- The tap does not accumulate samples. There is no duration cap and no unbounded memory.
- The tap coexists with normal capture sessions. When a hold-to-talk `startCapture` begins,
  the tap pauses and the detector resets. When the session ends, the tap resumes. This
  satisfies the UX rule that two microphone captures never run at once.
- The tap inherits the existing device-change, sleep-wake, and engine-restart handling.

Turn capture after a wake hit: `VoiceActivationController` buffers tap frames itself from the
wake timestamp in a bounded ring (35 s). It does not call `startCapture`. Live preview reuses
the `PartialTranscriptionScheduler` pattern over this buffer. Final transcription uses the
existing `transcriptionService.transcribe(samples:sampleRate:purpose: .final)`.

### Turn flow

```
Ready:      tap frames -> WakeWordDetector
wake hit:   play cue, set indicator to listening, start turn buffer and endpointer,
            start PartialTranscriptionScheduler for the live preview
endpoint:   transcribe(final) -> show transcript flash -> submitVoiceTask(text)
              .started / .queued  -> indicator shows the working state
              .intervened         -> same; the turn is already in the running conversation
              .rejected(message)  -> transient indicator error (existing path)
no speech:  5 s timeout -> return to Ready; no chat turn is created
```

Mid-run turns need no new plumbing. `submitVoiceTask` already routes to
`ComputerUseInterventionChannel` when a run is active, and `ComputerUseAgent.run` drains
interventions twice per iteration: before the model call, and after the response arrives
(discarding stale responses). "Hey Suniye, use Chrome instead" and "Hey Suniye, stop" both
become interventions. The model interprets "stop" from conversation context, per the UX plan.
The deterministic stop carve-out is deferred; see the safety note at the top.

### Sleep, wake, and device changes

- Reuse the `handleSystemSleep()` and `handleSystemWake()` forwarding in
  `AppState.handleSystemDidWake`. Sleep stops the tap and moves the state machine to a
  suspended variant of Off. Wake restores Ready only if the tap restarts cleanly.
- `ComputerUseRuntimeGuard` already gates agent actions on screen lock.

### Model packaging

Bundle both wake-path models in app resources. No download flow is needed at these sizes:

- Keyword spotting, int8: encoder 4.6 MB, decoder 272 KB, joiner 160 KB, `tokens.txt`. Total
  about 5 MB.
- Silero VAD: about 1.7 MB.

Add the resources in `project.yml` and run `xcodegen generate`. If bundle size becomes a
concern later, move these to a `ModelManager`-style download.

The voice output model is not bundled. See section 5, slice 5.

## 3. Integration points

| Surface | Change |
|---|---|
| `GeneralSettings` (`SettingsModels.swift`) | Add `voiceActivationEnabled: Bool = false`, `voiceActivationSoundFeedback: Bool = true`, `voiceActivationToggleHotkey: HotkeyConfiguration?`. Each field needs: property, init parameter, `CodingKeys` entry, tolerant decode, a mirrored `AppState` observable property with a persisting `didSet`, hydration in `applyGeneralSettings`, and a write in `persistGeneralSettings`. |
| `HotkeyService` | Add slot 5 `voiceActivationToggle` and the `onVoiceActivationToggle` callback. Slot 4 is taken by `pasteLastTranscript`. The parity branch now routes registration through `HotkeySlotAssignments`, which owns the collision policy; extend that type with the new slot instead of adding checks in `AppState`. |
| `FloatingIndicatorState` | Add cases `voiceActivationListening(levels:preview:)` and `voiceActivationNeedsInput`. Terminal flashes reuse `.computerUseCompleted` and the transient error path. Every exhaustive switch must be updated: `layoutAnimationKey`, `logValue`, `tracksPointerScreen`; controller `panelShouldCaptureMouseEvents`, `canDragCurrentState`, `size(for:)`; view `capsuleContent`, `isInteractive`, `pillWidth`, `pillHeight`, and the color properties. The Ready state appears in the menu bar only. There is no idle floating panel. |
| `StatusItemController` | Add menu items: a Voice Activation on/off toggle, "Open Conversation", and "Stop Task" (enabled only while `coordinator.isRunning`). Follow the existing pattern: field, `configureMenu()`, `refresh()`, `@objc` handler, `AppState` method. Add a menu-bar icon variant for the Ready state so microphone use stays visible. |
| `ComputerUseSettingsDisclosure` | Add a "Voice Activation" section: enable toggle, wake-phrase display ("Hey Suniye"), try-wake-phrase flow, toggle-shortcut recorder, sound toggle, and a microphone settings link. Show a one-time notice on first enable explaining that the microphone stays in use while waiting. |
| `ComputerUseCoordinator` | Version 1 maps the `completed`, `failed`, and `cancelled` phases to terminal indicator states through the existing `onPhaseChange`. Add an `onNeedsInput` signal only if the agent gains an ask-user tool later. |
| Manual handoff (auth walls) | New `paused` phase on the coordinator. The agent reports a blocked-on-user condition (login, CAPTCHA, 2FA) through a structured tool result; the coordinator pauses the run, stops observation, and sets the indicator to "Your turn" with the reason. Resume paths: "Hey Suniye, continue" (submits as an intervention that unpauses), the indicator's Continue control, or a typed message. Resuming forces a fresh observation. A paused run does not time out. |
| `FloatingIndicatorState` (additions) | `voiceActivationYourTurn(reason:)` with a Continue control, following the same exhaustive-switch checklist as the other new cases. |
| Agent step status | The working indicator shows one-line statuses emitted by the agent, such as "Opening Chrome" or "Checking your last 5 emails". Mechanism: add a required `status` string to each tool call in `ComputerUseModelToolContract`. The system prompt instructs the model to phrase it as a user-visible action of at most six words, with no tool or transport terms. The status flows through the existing `ComputerUseActivitySink` to the coordinator and then to `setFloatingIndicatorState`. If the status is absent or invalid, derive a label from the tool name, or show "Working…". The same statuses title the collapsed activity rows in chat, so both surfaces stay consistent. |
| Escape handling | Today, `hotkeyService.onCancel` cancels an in-progress voice recording only. It does not stop a running agent, and the Escape monitor is installed only when a Computer Use hotkey is configured. Fix both: Escape stops the active run through `coordinator.stop()`, and the monitor is installed whenever Voice Activation is on or a hotkey is set. |
| `MainWindowSection`, launch args | Add `--e2e-voice-activation` hooks for scripted end-to-end tests, matching the `--e2e-llm-*` precedent. |

## 4. Testing

All new logic sits behind seams that already have stub patterns in
`SuniyeTests/TestDoubles.swift`: `StubAudioCaptureService`, `StubTranscriptionService`,
`StubHotkeyService`, and the `makeTestAppState(...)` factory. New services get parameters
there.

Planned test files:

- `VoiceActivationStateMachineTests`: the full transition table, including false wake-up,
  no-speech timeout, wake during a running task, sleep and lock suspension, toggling off from
  each state, the manual-handoff pause and resume, and the follow-up window (opens only after
  Done, closes on silence, never opens after Stopped or failure).
- Mode-control tests: a `set_voice_activation` tool call from the agent turns Voice Activation
  off, flashes confirmation, and preserves the conversation; the physical routes work with a
  stub coordinator that rejects submissions (provider-outage case).
- `VoiceTurnEndpointerTests`: synthetic frame sequences for a normal turn, a mid-turn pause
  shorter than the trailing-silence window, the maximum-turn cap, and the no-speech timeout.
- `VoiceActivationControllerTests`: a stub detector emits scripted hits. Verify submit routing
  for all four `ComputerUseVoiceTaskSubmission` outcomes, the indicator state sequence, and
  tap pause and resume around a hold-to-talk session.
- The sherpa-backed `WakeWordDetector` cannot run headless. List it in
  `coverage_exclusions.txt` with a reason, as with the real `TranscriptionService` decode
  path. Keep the wrapper thin so the exclusion stays small.
- Extend `AppStateComputerUseVoiceTests` with the always-listening path. Add round-trip
  coverage for the three new fields in `GeneralSettingsStoreTests`. Add the new cases to
  `FloatingIndicatorStateTests` and `FloatingIndicatorLayoutTests`.
- Live validation: `scripts/e2e_voice_activation.sh`, a speaker-plays-audio variant of the
  physical voice test recorded in `phase-21-background-voice-resilience-and-e2e-2026-08-12.md`.

The CI coverage gate is 95% on the app target and must stay green after every slice.

## 5. Implementation slices

Each slice keeps the build green.

1. **Settings, state machine, menu bar.** Settings fields, `VoiceActivationStateMachine`, and
   the menu-bar toggle with state display. No audio yet. Tests land with the slice.
2. **Listen tap.** The `AudioCaptureService` tap API and pause/resume around capture
   sessions, with stub-driven tests for the coexistence rules.
3. **Wake word.** Bundle the models, implement `WakeWordDetector`, and wire tap to detector to
   state machine. Add the try-wake-phrase flow in Settings. This slice includes a live
   microphone tuning pass; treat its results as a go/no-go gate for the following slices.
4. **Turn capture.** Endpointer, turn buffer, live preview, final transcription,
   `submitVoiceTask` routing, and the new floating indicator states.
5. **Voice output.** `SpeechOutputService` speaks the Done, Couldn't-finish, and Needs-input
   text at turn boundaries.

   Engine decision (2026-08-13): Chatterbox Turbo, local, MLX 8-bit. Chosen over Kokoro for
   expressiveness: it has emotion control and won blind listening comparisons against
   ElevenLabs in vendor tests. Measurements from an M-series Mac:

   | | Chatterbox Turbo 8-bit | Kokoro (runner-up) |
   |---|---|---|
   | Latency per sentence, warm | 0.92 s (Metal) | 1.05 s (CPU) |
   | Peak memory footprint | 2.3 GB with `mx.set_cache_limit(256 MB)` | 0.69 GB |
   | Model load | 1.5 s | 0.3 s |
   | Disk | 675 MB | 330 MB |
   | Platforms | Apple Silicon only | Apple Silicon and Intel |

   Measured best-practice configuration: 8-bit quantization, warm resident model,
   `mx.set_cache_limit(256 MB)`, and `mx.clear_cache()` after each utterance. Do not use
   4-bit: it is slower because of dequantization cost, and its peak footprint is only
   slightly smaller.

   Integration: no native Swift runtime exists for Chatterbox. MLX is the only maintained
   path. Options, in recommended order:

   1. A helper process over HTTP, following the Gemma `llama-server` precedent: a frozen
      `mlx-audio` server bundle (PyInstaller or similar). The bundle is large, roughly
      300 to 500 MB, but it decouples the app from Python and is the fastest to land.
   2. An in-process port to `mlx-swift`. This is cleaner long-term, but the model stack
      (T3, S3 tokenizer, flow decoder) is a multi-week port. Not version 1.

   Apply RAM gating as with the Gemma helper: enable only when the machine has headroom, and
   unload after a configurable idle period. Model load takes 1.5 s, so re-warming on the
   first speech of a session is acceptable.

   Chatterbox is the only engine (decision 2026-08-14; the Fish Audio cloud tier and the
   AVSpeech fallback were cut for v1). Consequences: Voice Output is unavailable on Intel
   Macs and on machines without enough free memory — the settings subsection is hidden
   there; a synthesis failure skips speech for that turn, which the UX plan already permits
   because speech is additive. Kokoro (0.69 GB, both architectures, sherpa) remains the
   documented replacement if Chatterbox's memory use becomes a problem.

   Barge-in: a wake hit, Escape, or a new turn cancels playback and stops the MLX evaluation
   loop. The wake detector is suppressed while Suniye speaks, using the same mechanism as the
   cue-sound suppression. This slice also adds the Voice Output settings rows and the
   one-time disclosure. Voice cloning from a short reference recording is a possible later
   feature; the engine supports it.

   Latency budget (from the UX plan): speech starts within 1 second of the terminal state,
   target 500 ms; if synthesis has not started within 2 seconds, skip speech for that turn.
   Measured Chatterbox warm latency is 0.92 s per sentence, so the 1-second bound holds only
   with the model resident; a cold start (1.5 s load) exceeds the skip threshold, which is
   acceptable by design.

6. **Lifecycle and polish.** Sleep and wake handling, device-change resilience, the
   Escape-stops-run fix, sounds, the first-enable notice, the end-to-end script, and
   documentation.

Slices 1–2 and 3–4 can pair into two PRs if review size matters. Otherwise, one stacked PR on
`kis-169-computer-use-parity`.

## 6. Open questions and risks

- **Wake accuracy on real microphones.** Validation used synthesized audio only. The
  per-keyword thresholds (`#0.05`) must be tuned with live audio early in slice 3. One
  truncated keyword currently produces all detections; false-alarm behavior on real ambient
  audio is unmeasured.
- **Voice output memory and platform split.** Chatterbox Turbo peaks at about 2.3 GB of
  unified memory on top of the ASR model and Gemma, and MLX requires Apple Silicon. Intel
  and low-memory users have no Voice Output. Mitigations: RAM-gated enablement, idle unload,
  and Kokoro (0.69 GB, both architectures) as the documented downgrade path. Speech synthesis is
  local and adds no new network destination; the spoken text is the model response, which
  already transited the user's configured model provider (OpenRouter or similar).
- **Echo self-trigger.** Media playback or Suniye's own audio could contain wake-like sounds.
  Suniye's own speech playback is the worst case, so the wake detector is suppressed during
  it. The existing `echoCancellationEnabled` path applies to the audio engine; verify the tap
  inherits it. Also suppress the detector for about one second after cue sounds.
- **Power and privacy.** The microphone stays active in Ready, and the system microphone
  indicator stays visible. This is by design, but battery impact needs a sanity check. The
  keyword-spotting compute itself is negligible.
- **Stop latency.** A spoken stop rides the intervention channel. The worst case is one full
  model round-trip plus one atomic action. Escape and the Stop control are the fast path. The
  deterministic spoken stop is the flagged pre-release safety item.
- **Conversation staleness.** The UX plan continues the conversation on the next wake-up with
  no time bound. A staleness rule is flagged for later and is out of scope here.
- **English-only wake model.** Acceptable for the fixed phrase. A localized wake phrase would
  need the zh-en model or a retrain. Out of scope.
- **English-only voice output.** Chatterbox speaks English. Dictation supports 25 languages,
  so spoken replies do not match the user's dictation language. Accepted for version 1;
  recorded here so it is a decision rather than an oversight.
