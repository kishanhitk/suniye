# Always-listening Computer Use: implementation plan

Date: 2026-08-13
Status: Proposed. No code is written yet.
Companion document: `always-listening-ux-plan.md` defines the UX contract.
Branch: `kis-169-always-listening`, stacked on `kis-169-computer-use-parity` (PR #93).

Safety gates (a deterministic spoken-stop path and per-action guards) are deferred until before
release. This decision is recorded in the project notes. The plan builds the full feature first.

## 1. Feasibility

The bundled sherpa-onnx dylib (`Suniye/Frameworks/libsherpa-onnx-c-api.dylib`, version 1.12.25)
exports `SherpaOnnxCreateKeywordSpotter` and `SherpaOnnxCreateVoiceActivityDetector`.

A test harness was run on 2026-08-13 against the pretrained English keyword-spotting model
`sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01` (int8 files, about 5 MB total). Results:

- 3 of 3 positive samples detected. Samples were synthesized with `say` in two voices, with and
  without a trailing task sentence.
- 0 of 6 negative samples triggered a detection. Negatives included "hey sunny day", "hey sonny",
  "hey so nice", and "hey seriously".

Working configuration:

- Pass keywords in memory through `keywords_buf`. Do not write a keywords file to disk.
- Keyword lines are BPE token sequences. Compute them once with the model's `bpe.model` and store
  them as constants. No tokenizer runs at runtime. The validated set:

  ```
  ▁HE Y ▁SU N I Y E :3.0 #0.05
  ▁HE Y ▁SO ON I Y E :3.0 #0.05
  ▁HE Y ▁SU N I Y A Y :3.0 #0.05
  ▁HE Y ▁SO ON I Y A Y :3.0 #0.05
  ▁HE Y ▁SU NE E Y E :3.0 #0.05
  ▁HE Y ▁SU N I :3.0 #0.05
  ```

  In testing, the last line produced the detections. Keep the other lines for coverage.
- Spotter configuration: `max_active_paths 4`, `num_trailing_blanks 1`, `keywords_score 2.0`,
  `keywords_threshold 0.25`, with the per-keyword overrides shown above.
- After each detection, call `SherpaOnnxResetKeywordStream` and continue feeding samples.

Limitations of this validation:

- All test audio was synthesized. Thresholds must be tuned with live microphone audio during
  implementation. The Settings "Try wake phrase" flow exists for this purpose.
- The model is English-acoustic and detects only the fixed phrase. It is not general ASR.
  The model is a 3.3M-parameter streaming zipformer. CPU cost is negligible.

## 2. Architecture

### New components

```
Suniye/Services/
  WakeWordDetector.swift            actor; wraps SherpaOnnxKeywordSpotter
  VoiceTurnEndpointer.swift         speech-end detection over level/VAD frames
  VoiceActivationStateMachine.swift the seven UX states and their transitions
  VoiceActivationController.swift   @MainActor @Observable; owns the loop
  SpeechOutputService.swift         protocol; Chatterbox, AVSpeech, and Fish implementations
```

**WakeWordDetector.** A `WakeWordDetecting` protocol with a sherpa-backed implementation. API:
`start()`, `accept(samples:sampleRate:) -> WakeWordHit?`, `reset()`, `stop()`. It follows the
`TranscriptionServiceProtocol` dependency-injection pattern. Tests use a stub.

**VoiceTurnEndpointer.** Decides when a spoken turn has ended, from a stream of frames. The
primary signal is the sherpa silero VAD (`SherpaOnnxCreateVoiceActivityDetector`, model size
about 1.7 MB). The fallback signal is the existing 22-band level meter. Tunable parameters:
minimum speech 300 ms, trailing silence 900 ms, maximum turn 30 s, no-speech timeout after wake
5 s. The type contains no I/O and is unit-testable.

**VoiceActivationStateMachine.** Encodes the seven user-visible states from the UX plan and the
legal transitions between them. It emits effects: start turn capture, submit turn, set indicator
state. The type is pure and is tested exhaustively.

**VoiceActivationController.** Connects the other components. It subscribes to audio frames,
drives the detector, endpointer, and state machine, calls
`ComputerUseCoordinator.submitVoiceTask`, and maps states to the floating indicator through
AppState callbacks. All dependencies are constructor-injected: detector, clock, coordinator (as
`ComputerUseVoiceTaskHandling`), capture service, transcription service, and settings store.

### Audio capture

`AudioCaptureService` allows exactly one active capture. `startCapture` discards the previous
session, and sessions have a 10-minute cap. The always-listening path does not use capture
sessions. It adds a listen tap:

- New API on `AudioCaptureServiceProtocol`:
  `startListenTap(onFrames: @Sendable ([Float], Double) -> Void) async throws` and
  `stopListenTap() async`.
- The tap keeps the audio engine and ring-buffer drain running and delivers frames of about
  20 ms to one subscriber. It does not accumulate samples, so the 10-minute cap and memory
  growth do not apply.
- The tap coexists with normal capture sessions. When a hold-to-talk `startCapture` begins, the
  tap pauses and the detector resets. When the session ends, the tap resumes. This satisfies the
  UX rule that two microphone captures never run at once.
- The tap inherits the existing device-change, sleep-wake, and engine-restart handling.
- After a wake hit, `VoiceActivationController` buffers tap frames in a bounded ring (35 s). It
  does not call `startCapture`. Live preview reuses the `PartialTranscriptionScheduler` pattern
  over this buffer.
- Final transcription uses the existing
  `transcriptionService.transcribe(samples:sampleRate:purpose: .final)`.

### Turn flow

```
Ready:      tap frames -> WakeWordDetector
wake hit:   play cue, set indicator to .voiceActivationListening,
            start turn buffer + endpointer + live preview
endpoint:   transcribe(final) -> transcript flash -> submitVoiceTask(text)
              .started / .queued  -> indicator .computerUseWorking
              .intervened         -> same; the turn is already in the running conversation
              .rejected(message)  -> transient indicator error
no speech:  5 s timeout -> return to Ready; no chat turn is created
```

Mid-run turns require no new conversation plumbing. `submitVoiceTask` already routes to
`ComputerUseInterventionChannel` while a run is active, and `ComputerUseAgent.run` drains
interventions twice per iteration: before the model call, and after the response, discarding a
stale response. Corrections such as "use Chrome instead" and stop requests are both
interventions. The model interprets "stop" from context, per the UX plan. The deterministic stop
path is deferred; see the note at the top of this document.

### Sleep, wake, and device changes

- Reuse the `handleSystemSleep()` and `handleSystemWake()` forwarding in
  `AppState.handleSystemDidWake`. Sleep stops the tap and moves the state machine to a suspended
  variant of Off. Wake restores Ready only if the tap restarts without error. See the UX plan,
  "Mac sleeps or locks".
- `ComputerUseRuntimeGuard` already gates the agent on screen lock.

### Model packaging

Bundle both detection models in app resources. No download flow is needed:

- Keyword-spotting model (int8): encoder 4.6 MB, decoder 272 KB, joiner 160 KB, `tokens.txt`.
  Total about 5.0 MB.
- silero VAD model: about 1.7 MB.

Add the resources in `project.yml` and run `xcodegen generate`. If bundle size becomes a concern
later, move these to a `ModelManager`-style download.

## 3. Integration points

| Surface | Change |
|---|---|
| `GeneralSettings` (`SettingsModels.swift`) | Add `voiceActivationEnabled: Bool = false`, `voiceActivationSoundFeedback: Bool = true`, `voiceActivationToggleHotkey: HotkeyConfiguration?`. Each field needs the property, the init parameter, the CodingKeys case, and a tolerant decode. Mirror each field as an `AppState` observable property with a persisting `didSet`. Hydrate in `applyGeneralSettings` and write in `persistGeneralSettings`. |
| `HotkeyService` | Add slot 5 `voiceActivationToggle` and an `onVoiceActivationToggle` callback. Slot 4 is used by the Paste Last Transcript shortcut. Add collision checks against the four existing hotkeys in `AppState`. |
| `FloatingIndicatorState` | Add cases `voiceActivationListening(levels:preview:)` and `voiceActivationNeedsInput`. Terminal flashes reuse `.computerUseCompleted` and the transient error path. Update every exhaustive switch: `layoutAnimationKey`, `logValue`, `tracksPointerScreen`; in the controller, `panelShouldCaptureMouseEvents`, `canDragCurrentState`, `size(for:)`; in the view, `capsuleContent`, `isInteractive`, `pillWidth`, `pillHeight`, and the color properties. The Ready state appears in the menu bar only. There is no idle floating panel. |
| `StatusItemController` | Add menu items: a Voice Activation on/off toggle, "Open Conversation", and "Stop Task" (enabled only while `coordinator.isRunning`). Follow the existing pattern: field, `configureMenu()`, `refresh()`, `@objc` handler, `AppState` method. Add a menu-bar icon variant for the Ready state, per the UX plan's privacy section. |
| `ComputerUseSettingsDisclosure` | Add a "Voice Activation" section: enable toggle, wake-phrase display, "Try wake phrase" flow, toggle-shortcut recorder, sound toggle, and a microphone settings link. Show a one-time notice on first enable that the microphone stays in use. |
| `ComputerUseCoordinator` | No structural change. Version 1 maps the `completed`, `failed`, and `cancelled` phases to terminal indicator states through the existing `onPhaseChange`. Add an `onNeedsInput` signal only if the agent gains an ask-user tool. |
| Agent step status | The Working label shows one-line statuses that the agent emits, such as "Opening Chrome…". Add a required `status` string to each tool call in `ComputerUseModelToolContract`. The system prompt instructs the model to phrase the status as a user-visible action of six words or fewer, with no tool or transport terms. The status flows through the existing `ComputerUseActivitySink` to the coordinator and then to `setFloatingIndicatorState`. If the status is absent or invalid, derive a label from the tool name, or show "Working…". The same statuses become the titles of the collapsed activity rows in chat, so both surfaces stay consistent. |
| Escape handling | Today, `hotkeyService.onCancel` cancels an in-progress voice recording only. It does not stop a running agent, and the Escape monitor is installed only when a Computer Use hotkey is configured. Change both: Escape stops the active run through `coordinator.stop()`, and the monitor is installed whenever Voice Activation is on or a hotkey is set. |
| `MainWindowSection`, launch arguments | Add `--e2e-voice-activation` hooks for scripted end-to-end tests, following the `--e2e-llm-*` pattern. |

## 4. Testing

All new logic sits behind seams that have stub patterns in `SuniyeTests/TestDoubles.swift`
(`StubAudioCaptureService`, `StubTranscriptionService`, `StubHotkeyService`,
`makeTestAppState(...)`). New services get parameters there. The CI coverage gate is 95%.

- `VoiceActivationStateMachineTests`: the full transition table, including false wake-up,
  no-speech timeout, wake during a run, sleep and lock suspension, and toggle-off from each
  state.
- `VoiceTurnEndpointerTests`: synthetic frame sequences for a normal turn, a mid-turn pause
  shorter than the trailing-silence window, the maximum-turn cap, and the no-speech timeout.
- `VoiceActivationControllerTests`: a stub detector emits scripted hits. Verify submit routing
  for all four `ComputerUseVoiceTaskSubmission` outcomes, the indicator state sequence, and tap
  pause and resume around a hold-to-talk session.
- The sherpa-backed `WakeWordDetector` cannot run headless. List it in
  `coverage_exclusions.txt` with a reason, as the real `TranscriptionService` decode path is
  listed. Keep the wrapper thin so the exclusion stays small.
- Extend `AppStateComputerUseVoiceTests` with the always-listening path. Add round-trip coverage
  for the three new fields in `GeneralSettingsStoreTests`. Add the new cases to
  `FloatingIndicatorStateTests` and `FloatingIndicatorLayoutTests`.
- Live validation: add `scripts/e2e_voice_activation.sh`, a speaker-plays-audio variant of the
  physical voice test recorded in `phase-21-background-voice-resilience-and-e2e-2026-08-12.md`.

## 5. Implementation slices

Each slice keeps the build green.

1. **Settings, state machine, menu bar.** Settings fields, `VoiceActivationStateMachine`, and
   the menu-bar toggle with state display. No audio. Tests land with the slice.
2. **Listen tap.** The `AudioCaptureService` tap API and pause/resume around capture sessions.
   Stub-driven tests for the coexistence rules.
3. **Wake word.** Bundle the models, implement `WakeWordDetector`, and wire tap → detector →
   state machine. Implement the "Try wake phrase" flow. Tune thresholds with live microphone
   audio in this slice.
4. **Turn capture.** Endpointer, turn buffer, live preview, final transcription,
   `submitVoiceTask` routing, and the new floating indicator states.
5. **Voice Output.** `SpeechOutputService` speaks the Done, Couldn't-finish, and Needs-input
   text at turn boundaries.

   Engine decision (2026-08-13): Chatterbox Turbo, local, MLX 8-bit. It was chosen over Kokoro
   for expressiveness: it has an emotion-control parameter and won blind listening tests against
   ElevenLabs in vendor studies. Measurements from an M-series Mac:

   | | Chatterbox Turbo 8-bit | Kokoro (runner-up) |
   |---|---|---|
   | Latency per sentence (warm) | 0.92 s (Metal) | 1.05 s (CPU) |
   | Peak memory footprint | ~2.3 GB with `mx.set_cache_limit(256MB)` | ~0.69 GB |
   | Model load | 1.5 s | 0.3 s |
   | Disk | 675 MB | 330 MB |
   | Platforms | Apple Silicon only | Apple Silicon and Intel |

   Measured configuration guidance: use the 8-bit quantization. The 4-bit variant is slower
   because of dequantization cost and its peak footprint is only slightly smaller. Keep the
   model resident while Voice Output is active. Set `mx.set_cache_limit(256 MB)` and call
   `mx.clear_cache()` after each utterance.

   Integration: no Swift runtime exists for Chatterbox. MLX is the only maintained path. Two
   options, in order of preference for version 1:

   1. A helper process over HTTP, following the Gemma `llama-server` pattern: a frozen
      `mlx-audio` server bundle (PyInstaller or similar). The bundle is large (about
      300–500 MB) but decouples the app from Python and is the fastest to build.
   2. An in-process port to `mlx-swift`. This is cleaner but the model stack (T3, S3 tokenizer,
      flow decoder) is a multi-week port. Not in version 1.

   Gate enablement on available RAM, as the Gemma helper does. Unload the model after a
   configurable idle period; reload takes 1.5 s.

   Fallbacks: Intel Macs and low-RAM machines use `AVSpeechSynthesizer`, which is also the
   runtime failure fallback. Fish Audio `s2.1-pro` is an optional cloud tier with a user-provided
   API key stored in the Keychain. Kokoro is the documented replacement if Chatterbox's memory
   use becomes a problem; the sherpa rebuild that enables Kokoro also enables ZipVoice, which
   supports voice cloning.

   Barge-in: a wake hit, Escape, or a new turn cancels playback and stops the MLX evaluation
   loop. The wake detector is suppressed while Suniye speaks, using the same mechanism as the
   cue-sound suppression. Add the settings rows and the one-time disclosure. Voice cloning from
   a short reference sample is a possible later feature; the engine supports it.

6. **Lifecycle and polish.** Sleep and wake handling, device-change resilience, the
   Escape-stops-run change, sounds, the first-enable notice, the end-to-end script, and
   documentation.

Slices 1–2 and 3–4 can pair into two PRs if review size matters. Otherwise, one stacked PR on
`kis-169-computer-use-parity`.

## 6. Open questions and risks

- **Wake accuracy on real microphones.** Validation used synthesized audio only. The
  per-keyword thresholds (`#0.05`) must be tuned with live audio in slice 3. Detection currently
  depends on the truncated `▁HE Y ▁SU N I` keyword. Measure the false-alarm rate on real
  ambient audio.
- **Voice Output memory use and platform split.** Chatterbox Turbo peaks at about 2.3 GB of
  unified memory, in addition to the ASR model and Gemma. MLX requires Apple Silicon, so Intel
  users get the AVSpeech fallback. Mitigations: RAM-gated enablement, idle unload, and Kokoro
  (0.69 GB, both architectures) as the documented downgrade path. The default engine is local.
  Only the optional Fish tier sends response text to a cloud provider.
- **Echo self-trigger.** Media playback or Suniye's own audio could contain wake-like sounds.
  Suniye's own TTS playback is the most likely trigger; the wake detector must be suppressed
  during playback. The existing `echoCancellationEnabled` path applies to the engine; verify
  that the tap inherits it. Suppress the detector for about one second after cue sounds.
- **Power.** The microphone stays active in the Ready state, and the system microphone
  indicator stays visible. This is intended behavior per the UX plan. Run a battery check;
  the keyword-spotting compute itself is negligible.
- **Stop latency.** A semantic stop travels through the intervention channel. The worst case is
  one model round-trip plus one atomic action. Escape and the Stop control are the fast paths.
  The deterministic spoken-stop path is the flagged pre-release safety item.
- **Conversation staleness.** The UX plan continues the conversation at the next wake-up with no
  time limit. A staleness rule is flagged for later and is out of scope here.
- **English-only wake model.** Acceptable for the fixed phrase. A localized wake phrase would
  require the zh-en model or retraining. Out of scope.
