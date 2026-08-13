# Always-listening Computer Use — implementation plan

Date: 2026-08-13
Status: proposed. Companion to `always-listening-ux-plan.md` (UX contract). No code written yet.
Branch strategy: stacked PR — `kis-169-always-listening` on top of `kis-169-computer-use-parity` (PR #93).

Per product decision, safety gates (deterministic spoken-stop carve-out, per-action guards) are
**deferred until pre-release**. This plan builds the full experience first.

## 1. Feasibility — validated today

The bundled sherpa-onnx dylib (`Suniye/Frameworks/libsherpa-onnx-c-api.dylib`, v1.12.25) exports
`SherpaOnnxCreateKeywordSpotter` and `SherpaOnnxCreateVoiceActivityDetector`. A throwaway C
harness against the pretrained English KWS model
(`sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01`, int8 files ≈ 5 MB total) gave:

- **3/3 positives detected** — `say`-synthesized "Hey Suniye" (two voices, with and without a
  trailing task sentence).
- **0/6 false alarms** — including the near-misses "hey sunny day", "hey sonny", "hey so nice",
  "hey seriously".

Working configuration:

- Keywords passed in-memory via `keywords_buf` (no keywords file on disk).
- Keyword lines are pre-computed BPE token sequences (computed once with the model's `bpe.model`;
  hardcoded as constants — no tokenizer at runtime). The set that works:

  ```
  ▁HE Y ▁SU N I Y E :3.0 #0.05
  ▁HE Y ▁SO ON I Y E :3.0 #0.05
  ▁HE Y ▁SU N I Y A Y :3.0 #0.05
  ▁HE Y ▁SO ON I Y A Y :3.0 #0.05
  ▁HE Y ▁SU NE E Y E :3.0 #0.05
  ▁HE Y ▁SU N I :3.0 #0.05        <- the variant that actually fires; keep the others for coverage
  ```

- Spotter config: `max_active_paths 4`, `num_trailing_blanks 1`, `keywords_score 2.0`,
  `keywords_threshold 0.25`, per-keyword boost/threshold overrides as above.
- After each detection, call `SherpaOnnxResetKeywordStream` and keep feeding.

Caveats: validation used TTS audio only. Real-mic thresholds need a live tuning pass — that is
what the Settings "Try wake phrase" flow is for. The KWS model is English-acoustic; it spots the
fixed phrase, it is not general ASR, so CPU cost is a 3.3M-param streaming zipformer (negligible).

## 2. Architecture

### New components

```
Suniye/Services/
  WakeWordDetector.swift          actor; wraps SherpaOnnxKeywordSpotter (pattern: TranscriptionService)
  VoiceTurnEndpointer.swift       pure logic: speech-end detection over level/VAD frames
  VoiceActivationStateMachine.swift  pure value type: Off/Ready/Listening/Working/NeedsInput/Terminal
  VoiceActivationController.swift @MainActor @Observable; owns the loop, bridges everything
  SpeechOutputService.swift       protocol; Chatterbox (local MLX helper) + AVSpeech + Fish impls
```


- `WakeWordDetector` — `protocol WakeWordDetecting` + sherpa impl. API:
  `start()`, `accept(samples:[Float], sampleRate:) -> WakeWordHit?`, `reset()`, `stop()`.
  Follows the `TranscriptionServiceProtocol` DI pattern so tests use a stub.
- `VoiceTurnEndpointer` — decides "turn finished" from a frame stream. Primary signal: sherpa
  silero VAD (`SherpaOnnxCreateVoiceActivityDetector`, silero model ≈ 1.7 MB); fallback signal:
  the existing 22-band level meter energy. Tunables: min-speech 300 ms, trailing-silence 900 ms,
  max-turn 30 s, no-speech-after-wake timeout 5 s (UX plan: silent wake-up returns to Ready).
  Pure and fully unit-testable.
- `VoiceActivationStateMachine` — encodes the seven UX states and legal transitions; emits
  effects (start turn capture, submit turn, show indicator state). Pure, exhaustively tested.
- `VoiceActivationController` — glue. Subscribes to audio, drives detector + endpointer + state
  machine, calls `ComputerUseCoordinator.submitVoiceTask`, maps states to the floating indicator
  via AppState callbacks. Constructor-injected seams: detector, endpointer clock, coordinator
  (as `ComputerUseVoiceTaskHandling`), capture service, transcription service, settings store.

### Audio: one engine, a tap — not a second capture

`AudioCaptureService` enforces exactly one `ActiveCapture` (`startCapture` discards the previous
one) and a 10-minute session cap. Rather than fight that, add a **listen tap**:

- New API on `AudioCaptureServiceProtocol`:
  `startListenTap(onFrames: @Sendable ([Float], Double) -> Void) async throws` /
  `stopListenTap() async`.
- The tap keeps the engine + ring-buffer drain running continuously and streams ~20 ms frames to
  one subscriber. It does **not** accumulate samples (no 10-min cap, no unbounded memory) and it
  coexists with a normal capture session: when hold-to-talk `startCapture` begins, the tap pauses
  (detector reset); when the session ends, the tap resumes. This satisfies the UX rule "never two
  microphone captures" with zero engine churn, and inherits the existing device-change /
  sleep-wake / engine-restart machinery for free.
- Turn capture after wake-up: `VoiceActivationController` buffers tap frames itself from the
  wake-hit timestamp (bounded ring, 35 s) — no `startCapture` call, so the drain path stays
  simple. Live preview reuses the `PartialTranscriptionScheduler` shape over that buffer.
- Final transcription: existing `transcriptionService.transcribe(samples:sampleRate:purpose:.final)`.

### Turn flow

```
Ready:      tap frames -> WakeWordDetector
wake hit:   play cue, indicator .voiceActivationListening, start turn buffer + endpointer
            (+ PartialTranscriptionScheduler for the live preview tail)
endpoint:   transcribe(final) -> brief transcript flash (UX plan) -> submitVoiceTask(text)
              .started / .queued  -> indicator .computerUseWorking (existing state)
              .intervened         -> same; turn already appended to the running conversation
              .rejected(message)  -> transient indicator error (existing path)
no speech:  5 s timeout -> back to Ready, no chat turn
```

Mid-run turns need **no new plumbing**: `submitVoiceTask` already routes to
`ComputerUseInterventionChannel` when running, and `ComputerUseAgent.run` drains interventions
twice per iteration (before the model call and after the response, discarding stale responses).
"Hey Suniye, use Chrome instead" and "Hey Suniye, stop" both become interventions; the model
interprets "stop" semantically, per the UX plan. (Deterministic stop carve-out: deferred, see
Safety note above.)

### Wake / sleep / device changes

- Reuse `handleSystemSleep()/handleSystemWake()` forwarding (`AppState.handleSystemDidWake`):
  sleep stops the tap and moves the state machine to a suspended flavor of Off; wake restores
  Ready only if the tap restarts cleanly (UX plan §Mac sleeps or locks).
- `ComputerUseRuntimeGuard` already gates on screen lock for the agent side.

### Model packaging

Bundle both models in app resources (no download flow, offline-first, tiny next to the 33 MB
onnxruntime dylib):

- KWS int8: encoder 4.6 MB + decoder 272 KB + joiner 160 KB + `tokens.txt` ≈ 5.0 MB
- silero VAD: ≈ 1.7 MB

`project.yml` resources addition + `xcodegen generate`. If bundle-size pressure appears later,
move to `ModelManager`-style download; not worth the flow now.

## 3. Integration inventory (exact seams, from code audit)

| Surface | Change |
|---|---|
| `GeneralSettings` (`SettingsModels.swift`) | `voiceActivationEnabled: Bool = false`, `voiceActivationSoundFeedback: Bool = true`, `voiceActivationToggleHotkey: HotkeyConfiguration?` — property + init + CodingKeys + tolerant decode, mirrored in `AppState` observable properties with persisting `didSet`, hydrated in `applyGeneralSettings`, written in `persistGeneralSettings`. |
| `HotkeyService` | New slot (4) `voiceActivationToggle` + `onVoiceActivationToggle` callback; collision checks against the three existing hotkeys in `AppState`. |
| `FloatingIndicatorState` | New cases `voiceActivationListening(levels:preview:)`, `voiceActivationNeedsInput`, plus terminal flashes reusing `.computerUseCompleted` / transient error. Touch every exhaustive switch: `layoutAnimationKey`, `logValue`, `tracksPointerScreen`, controller `panelShouldCaptureMouseEvents` / `canDragCurrentState` / `size(for:)`, view `capsuleContent` / `isInteractive` / `pillWidth` / `pillHeight` / colors. Ready state lives in the **menu bar only** (UX plan) — no new idle panel. |
| `StatusItemController` | Items: "Voice Activation On/Off" toggle, "Open Conversation", "Stop Task" (enabled iff `coordinator.isRunning`). Field → `configureMenu()` → `refresh()` → `@objc` handler → `AppState` method, per existing pattern. Menu-bar icon variant while Ready (mic-in-use visibility, UX plan §Privacy). |
| `ComputerUseSettingsDisclosure` | New "Voice Activation" section: toggle, wake-phrase display ("Hey Suniye"), Try-wake-phrase flow, toggle-shortcut recorder, sound toggle, mic picker link. First-enable one-time notice sheet (mic stays in use while waiting). |
| `ComputerUseCoordinator` | No structural change. Add an `onNeedsInput` signal only if the agent gains an ask-user tool later — v1 maps `completed/failed/cancelled` phases to terminal indicator states via the existing `onPhaseChange`. |
| Agent step status | The Working label shows agent-emitted one-line statuses ("Opening Chrome…", "Checking your last 5 emails…"). Mechanism: add a required short `status` string to each tool call in `ComputerUseModelToolContract` (system prompt instructs the model to phrase it as a user-visible action, ≤ 6 words, no tool/transport terms). It flows through the existing `ComputerUseActivitySink` → coordinator → `setFloatingIndicatorState`. Fallback when absent or invalid: derive from the tool name ("Taking a look…", "Typing…") or plain **Working…**. Statuses also render as the collapsed activity rows' titles in chat, so both surfaces stay consistent. |
| Escape gap | Today `hotkeyService.onCancel` only cancels an in-progress voice **recording**; it does not stop a running agent, and the Escape monitor is only installed when a Computer Use hotkey is configured. Close both while here: Escape stops the active run (`coordinator.stop()`), monitor installed whenever Voice Activation is on **or** a hotkey is set. |
| `MainWindowSection` / launch args | Optional `--e2e-voice-activation` style hooks for scripted e2e, matching `--e2e-llm-*` precedent. |

## 4. Testing strategy (95% gate)

All new logic is behind seams that already have stub patterns in `SuniyeTests/TestDoubles.swift`
(`StubAudioCaptureService`, `StubTranscriptionService`, `StubHotkeyService`,
`makeTestAppState(...)` — new services get parameters there).

- `VoiceActivationStateMachineTests` — exhaustive transition table, incl. false wake-up, no-speech
  timeout, wake-during-working, sleep/lock suspension, toggle-off during each state.
- `VoiceTurnEndpointerTests` — synthetic frame sequences: normal turn, mid-thought pause under
  the trailing-silence window, max-turn cap, no-speech timeout.
- `VoiceActivationControllerTests` — stub detector emits scripted hits; verify submit routing for
  all four `ComputerUseVoiceTaskSubmission` outcomes, indicator state sequence, tap pause/resume
  around a hold-to-talk session.
- `WakeWordDetector` (sherpa-backed) cannot run headless → `coverage_exclusions.txt` with reason,
  same as the real `TranscriptionService` decode path; keep the wrapper thin so exclusion is small.
- Extend `AppStateComputerUseVoiceTests` with the always-listening path;
  `GeneralSettingsStoreTests` round-trip for the three new fields;
  `FloatingIndicatorStateTests` / `LayoutTests` for new cases.
- Live validation: `scripts/e2e_voice_activation.sh` (speaker-plays-wav variant of the existing
  physical voice e2e recorded in `phase-21-background-voice-resilience-and-e2e-2026-08-12.md`).

## 5. Implementation slices (each keeps the build green)

1. **Settings + state machine + menu bar** — settings fields, `VoiceActivationStateMachine`,
   menu-bar toggle showing state; no audio yet. Tests land with it.
2. **Listen tap** — `AudioCaptureService` tap API + pause/resume around sessions; stub-driven
   tests for coexistence rules.
3. **Wake word** — bundle models, `WakeWordDetector`, wire tap → detector → state machine;
   "Try wake phrase" flow in settings.
4. **Turn capture** — endpointer, turn buffer, live preview, final transcribe,
   `submitVoiceTask` routing; floating indicator states.
5. **Voice Output** — `SpeechOutputService` speaking Done / Couldn't finish / Needs-input text
   at turn boundaries. **Engine decision (2026-08-13): Chatterbox Turbo, local, MLX 8-bit.**
   Chosen over Kokoro for expressiveness (emotion control, blind-test wins over ElevenLabs) after
   measured evals on an M-series Mac:

   | | Chatterbox Turbo 8-bit | Kokoro (runner-up) |
   |---|---|---|
   | Latency/sentence (warm) | 0.92 s (Metal) | 1.05 s (CPU) |
   | Peak memory footprint | ~2.3 GB (with `mx.set_cache_limit(256MB)`) | ~0.69 GB |
   | Model load | 1.5 s | 0.3 s |
   | Disk | 675 MB | 330 MB |
   | Platforms | Apple Silicon only | AS + Intel |

   Best-practice config (measured): 8-bit quant (4-bit is *slower* — dequant cost — and barely
   smaller in peak footprint), warm resident model, `mx.set_cache_limit(256 MB)`,
   `mx.clear_cache()` after each utterance.

   **Integration cost (the real work):** no native Swift runtime exists for Chatterbox — MLX is
   the only maintained path. Options, in recommended order:
   1. Helper process over HTTP, like the Gemma `llama-server` precedent — a frozen (PyInstaller
      or similar) `mlx-audio` server bundle. Ships large (~300–500 MB) but decouples the app
      from Python and lands fastest.
   2. Port to `mlx-swift` in-process — cleanest long-term, but the model stack (T3 + S3 tokenizer
      + flow decoder) is a multi-week port. Not v1.
   RAM gating like the Gemma helper: enable only when the machine has headroom; unload after a
   configurable idle period (load is 1.5 s — acceptable to re-warm on first speech of a session).

   **Fallbacks:** Intel Macs and low-RAM machines get `AVSpeechSynthesizer` (flat but functional);
   it is also the runtime failure fallback. Fish `s2.1-pro` stays as an optional
   bring-your-own-key cloud tier (settings + Keychain per the earlier design). Kokoro remains
   documented as the drop-in replacement if Chatterbox's RAM draws complaints — the sherpa TTS
   rebuild that would enable it also unlocks ZipVoice cloning.

   Barge-in: wake hit, Escape, or a new turn cancels playback and stops the MLX eval loop; the
   wake detector is suppressed while Suniye speaks (self-wake guard, same mechanism as the
   cue-sound suppression). Settings rows + one-time disclosure. Voice cloning ("speak in my
   voice", ~5 s reference) is a natural later feature this engine gets for free.
6. **Lifecycle + polish** — sleep/wake, device-change resilience, Escape-stops-run fix, sounds,
   first-enable notice, e2e script, docs.

Slices 1–2 and 3–4 pair naturally into two PRs if review size matters; otherwise one stacked PR
on `kis-169-computer-use-parity`.

## 6. Open questions / risks

- **Real-mic wake accuracy.** TTS-validated only; thresholds (`#0.05` per keyword) must be tuned
  with live audio early in slice 3. The truncated `▁HE Y ▁SU N I` keyword carries recall today;
  false-alarm behavior on real ambient audio is the thing to watch.
- **Voice Output RAM and platform split.** Chatterbox Turbo peaks at ~2.3 GB in unified memory on
  top of ASR + Gemma, and MLX is Apple Silicon-only — Intel users silently get the flat AVSpeech
  fallback. Mitigations: RAM-gated enablement, idle unload, and Kokoro (0.69 GB, AS+Intel) as the
  documented downgrade path. The default remains fully local; only the optional Fish tier sends
  response text to a cloud provider.
- **Echo self-trigger.** Media playback or Suniye's own cue sounds could contain wake-like audio.
  Suniye's own TTS playback is the worst case — the wake detector must be suppressed during it.
  Existing echo-cancellation path (`echoCancellationEnabled`) applies to the engine; verify the
  tap inherits it. Mitigation: suppress detector for ~1 s after our own cue sounds.
- **Power/privacy.** Mic stays hot in Ready — the orange mic indicator is permanent while
  enabled. This is by design (UX plan makes it a visible promise) but worth a battery sanity
  check; the KWS compute itself is negligible.
- **Stop latency.** Semantic stop rides the intervention channel: worst case one full model
  round-trip + one atomic action. Escape/Stop are the fast path. Deterministic spoken-stop is
  the flagged pre-release safety item.
- **Conversation staleness.** UX plan says the next wake-up continues the conversation with no
  time bound. Flagged for a future staleness rule; out of scope here.
- **English-only wake model.** Fine for the fixed English-adjacent phrase; a localized wake
  phrase would need the zh-en model or a retrain. Out of scope.
