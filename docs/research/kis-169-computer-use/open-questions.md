# KIS-169 open questions

## DMG questions

- `[Resolved]` The user/client-selected model slug, static prompts, request schema, and runtime
  message ordering are recovered in `runtime-request-and-model-selection-recovery-2026-08-08.md`.
- `[Resolved in observable behavior]` The native ten-tool schema, app resolution inputs,
  background observation, AX rendering, window-discovery primitives, screenshot backends,
  coordinate conversion, semantic actions, synthesized input, and settling/refetch architecture
  are recovered in `native-algorithm-recovery-2026-08-09.md`.
- `[Unknown]` Which desktop process owns each part of every production session across the
  node-REPL and legacy-MCP variants?
- `[Unknown]` What final comparator ranks multiple valid matched windows for one app?
- `[Unknown]` What are the complete AX diff equality rules, line budgets, and full-tree fallbacks?
- `[Unknown]` What exact matrix selects ScreenCaptureKit versus SkyLight for every capture?
- `[Unknown]` What exact role/app conditions choose AX semantics versus synthesized input?
- `[Unknown]` What are the intervention debounce and cancellation semantics once an event is
  already being posted?
- `[Unknown]` Which actions require approval in the full production policy?
- `[Unknown]` How does browser control differ in its complete wire protocol?

## Suniye product questions

- Should the first model run locally, remotely, or through a user-selected provider?
- Does the local-first promise cover screenshots and AX text?
- `[Resolved for the current desktop prototype]` Suniye allows the agent to start from the active
  app or an optional picker selection, then switch apps during the run. Release policy remains
  open.
- Which action classes are safe without approval?
- Should persistent approvals exist in the first release?
- Should Suniye support locked-screen operation?
- Should the first release support browser-specific semantics?

## Implementation gates

- Do not choose a screenshot API until a macOS 14 test proves the required output.
- Do not add a helper process until the permission model proves that it is needed.
- Do not connect a model until the typed decision schema and safety policy are fixed.
- Do not enable persistent approval until audit and revocation behavior are specified.

## Phase 0 live validation

- Does `CGWindowListCreateImage` capture the selected window after Screen Recording grant?
- Does AX window geometry match CG window geometry for the target apps?
- Which target apps expose a complete enough AX tree for the first read-only preview?
- `[Resolved for the current desktop prototype]` The picker is optional starting context. The
  model can select another app during the run.
- Does running discovery and observation behind the Phase 1 actor boundary behave correctly for real AX targets?

## Phase 2 live validation

- Does the `CGEvent` event tap post click, key, and scroll events after the required macOS permissions are granted?
- Do AX window bounds and `CGEvent` screen coordinates use the same origin and display scale for each target app?
- Does a target remain safe to act on when its window moves, resizes, or changes key-window state after observation?
- Do target applications expose the observed element indexes consistently during semantic action resolution?
- Does the existing clipboard-preserving text insertion path protect clipboard state during an approved text action?
- Is a one-time approval card sufficient for the first local integration, or does the product need a separate persistent approval service later?

## Fresh phase 3 native-action follow-up

- `[Resolved in deterministic code]` Every action consumes a successful app/window observation;
  a failed refresh invalidates the previous observation and a newly selected action must follow a
  successful refresh.
- `[Resolved in deterministic code]` Coordinate input uses actual captured-image scale plus the
  current window origin, and synthesized events are process-scoped rather than globally posted.
- `[Unknown]` Which role/app/action conditions choose native AX semantics versus a synthesized
  event in the reference implementation?
- `[Unknown]` What exact loading or AX-change signals extend settling from about one second to at
  most about five seconds?
- `[Unknown]` What scroll page calibration, drag interpolation, key timing, and Unicode chunking
  does the native implementation use?
- `[Live required]` Verify click, drag, scroll, key, text, set-value, selection, and secondary AX
  actions against safe cross-process apps under the installed Preview's TCC identity.

### Corrective parity status

- `[Resolved for the current desktop prototype]` The target UI can select a specific visible
  window, and the user can explicitly bring it forward before control.
- `[Resolved for the current desktop prototype]` The typed action boundary covers click metadata,
  positioned scroll, drag, set value, and text selection.
- `[Resolved for the current desktop prototype]` Always-allowed approvals have visible revocation
  UX and refresh after persistence.
- `[Unknown]` The selected-window activation path still needs a live Accessibility test across
  multiple target applications.
- `[Resolved for the current desktop prototype]` Indexed clicks, dynamic secondary AX actions,
  and screenshot IDs are part of the typed action and policy contracts.
- `[Resolved for the current desktop prototype]` The model receives running and installed app
  candidates. A non-running resolved app launches through the application catalog before state
  capture.
- `[Unknown]` Reference-level transient screenshot caching and state diffs are not yet implemented
  in Suniye.

## Phase 3 integration gates

- `[Resolved for the fresh implementation]` The endpoint, model slug, and API key are selected by
  the user through Suniye's existing API Endpoint settings. The selected provider receives the AX
  text, screenshots, action results, and failure messages needed for the requested run.
- `[Product question]` Does the local-first promise require a fully local Computer Use model, or
  is a user-selected remote provider acceptable with explicit disclosure?
- `[Independent choice]` Provider requests use the existing 120-second timeout. There is no local
  agent-duration cap; task cancellation cancels an in-flight provider request.
- How should `ComputerUseAgentResult` events connect to the main-actor coordinator without allowing the model to mutate views?
- `[Resolved in deterministic code]` The model receives exactly the ten recovered function tools,
  and normal assistant text is terminal. The independent system prompt follows the recovered
  observable operating logic.
- `[Resolved in deterministic code]` Action failures return to the model as tool results so it can
  recover. The conversation UI may surface those retries without blocking them.

## Fresh phase 4 provider-loop follow-up

- `[Resolved in deterministic code]` Prior conversation precedes the current task; assistant tool
  calls, native tool results, and observation screenshots remain ordered for subsequent requests.
- `[Resolved in deterministic code]` No deterministic instruction matcher, frontmost fallback,
  target lock, completion tool, action cap, failure cap, or duration cap is present.
- `[Independent choice]` Suniye uses its OpenAI-compatible Chat Completions endpoint and exposes
  ten direct function tools. The inspected client uses a Responses/node-REPL route.
- `[Independent choice]` Screenshots are supplied as a follow-on user multimodal image after the
  corresponding tool result for broad provider compatibility.
- `[Unknown]` Does the user's selected live model support the exact tool-call and image-message
  combination reliably?
- `[Unknown]` What provider-private routing, inference, hidden instructions, or output repair occur
  beyond the inspected client boundary?
- `[Next]` Connect the actor agent to the main-actor coordinator and final conversation UX without
  allowing the model layer to mutate SwiftUI state.

## Phase 4 integration gates

- Which action risks may receive session or always approval in the product default policy?
- Which app policy settings need user-facing controls before persistent approval is enabled?
- What expiry duration and reset UX should always approvals use?
- Should policy and approval audit records remain local only, or may aggregate redacted telemetry leave the Mac?

## Phase 5B status and remaining gates

- `[Resolved for the desktop prototype]` The first provider is the user-selected explicit API Endpoint already used by Suniye's Magic Format settings.
- `[Resolved for the desktop prototype]` A model run reaches the main-actor coordinator through an actor-safe approval continuation. The model cannot mutate SwiftUI state directly.
- `[Resolved for the desktop prototype]` The response protocol is a strict Codable decision object with action, completed, ask-user, blocked, and retryable-failure outcomes.
- `[Resolved for the desktop prototype]` Screenshot upload is a separate session choice and defaults to disabled.
- `[Verified]` Deterministic validation covers the coordinator's approval, policy, cancellation,
  stale-operation, and terminal-result paths. The full suite reports 1,088 passed, 1 skipped,
  and 0 failed tests.
- `[Verified]` Gated coverage passes at 95.08% (14,455/15,203 lines) at the 95% floor.
- `[Verified]` The focused Computer Use regression classes pass with 0 failures.
- `[Unknown]` A live provider's actual multimodal support, prompt reliability, response latency, and cancellation behavior still need a manual test.
- `[Unknown]` The current Core Graphics screenshot adapter must still be compared with ScreenCaptureKit on macOS 14 and later.
- `[Verified]` The live `@Computer` E2E validates Suniye navigation, target/window selection,
  same-process activation, Accessibility-only capture, approval presentation, and denial.
- `[Unknown]` Screen Recording capture, cross-process activation, and native input delivery still
  need a safe live target with the required permissions.
- `[Deferred]` Browser-specific control needs its own tab, DOM, extension, download, and upload contract.
- `[Deferred]` A separate native helper is not needed by the current same-process Swift design. Revisit it only if live permission, blocking, crash-isolation, or entitlement tests show a requirement.

## Superseding resolutions — 2026-08-03

- `[Resolved for the current testing path]` Actions execute automatically after a task starts;
  the Preview surface does not ask for per-action approval. The policy actor remains for app
  policy, audit, and a future approval UX.
- `[Resolved for the current Mac surface]` There is no user-facing window picker, Bring Forward
  control, target lock, or frontmost intervention monitor. Native adapters still resolve and
  activate the concrete window required by macOS APIs.
- `[Resolved for the current Mac observation]` Screenshots are always captured and included. The
  user does not choose whether the model receives the observation screenshot in this path.
- `[Resolved for the current action boundary]` Indexed element and arbitrary Accessibility action
  names are sent to the native adapter without cached observation prevalidation.
- `[Resolved for the current agent loop]` Local action, failure, and duration caps are removed;
  explicit cancellation, model/provider termination, platform errors, and provider timeout remain
  terminal boundaries.
- `[Resolved]` Client-side model selection, request construction, static prompts, and context-role
  ordering are recovered in `runtime-request-and-model-selection-recovery-2026-08-08.md`.
- `[Unknown]` The complete helper IPC authentication contract, the five native branch details
  enumerated above, provider-private inference, and browser-extension behavior remain unknown.

## Direct voice follow-up — 2026-08-03

- `[Resolved for the current desktop surface]` The visible Computer Use page is the explicit
  routing context for the existing Suniye hold-to-talk shortcut; no phrase matcher or extra global
  voice mode is used.
- `[Resolved for the current desktop surface]` A spoken task is sent raw to the Computer Use
  coordinator and is not inserted into the focused app or passed through Magic Format.
- `[Unknown]` Does live local ASR produce reliable task boundaries for long Computer Use requests?
- `[Unknown]` How should microphone interruption, provider timeout, and page navigation be shown
  during a live voice task?
- `[Deferred]` Browser voice tasks should be validated through the separate browser extension path,
  not by extending the desktop routing seam.

## Fresh phase 5 status — 2026-08-09

- `[Resolved]` The fresh provider-backed agent is connected to a main-actor coordinator and the
  Computer Use conversation page.
- `[Resolved]` The composer clears on submission and assistant output is rendered only in the
  transcript. Working state has one Stop control and generic shimmering status text.
- `[Resolved]` Accessibility and Screen Recording are checked and requested at the feature
  boundary, with recovery links to the matching System Settings pane.
- `[Resolved]` Direct voice reuses local transcription and routes raw text only while the Computer
  Use page is visible. It does not use phrase matching or focused-app insertion.
- `[Unknown]` What exact physical-input debounce and self-generated-event suppression does the
  native reference helper apply before cancelling or re-observing?
- `[Unknown]` What exact lock-screen transition and recovery UX should Suniye expose?
- `[Unknown]` Which loading indicators and observation changes extend the reference settling
  window, and for how long?
- `[Live required]` Validate model routing, TCC permission identity, safe cross-process native
  actions, Stop behavior, direct voice, and the installed conversation UI.
