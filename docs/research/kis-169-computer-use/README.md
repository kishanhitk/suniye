# KIS-169 Computer Use research

This folder records the Computer Use research and the Phase 0 through the current desktop parity
implementation for Suniye.

The source artifact is `<home>/Downloads/ChatGPT (1).dmg`.

## Current branch baseline

`kis-169-computer-use-parity` starts from `origin/main` at `aebdf680`. Research was moved onto this
branch without carrying over the prior prototype implementation. New Swift code is being written
from the recovered contract. The fresh implementation now contains the exact ten-tool domain
contract, app and window discovery, AX and screenshot observation, native actions with one-shot
fresh-observation enforcement, a provider-backed model/agent loop, a main-actor conversation
coordinator with permission, cancellation, and direct-voice UX, plus native lock and
loading-aware settling guards. Physical-input cancellation was removed after live parity
testing showed it incorrectly prevented concurrent Mac use. Older implementation entries
remain historical records from the preserved `kis-169-computer-use` branch unless a fresh-phase
note explicitly re-verifies them.

The fresh branch has completed installed live-provider runs. See the phase notes below for
successful cases, failed cases, verified boundaries, and independent choices.

See `fresh-implementation-baseline-2026-08-09.md` before beginning the new implementation.

The research uses read-only DMG inspection and Suniye source inspection.

Phase 0 adds a Swift observation service. Phase 1 adds app discovery, permissions, preview, and
cancellation. Phase 2 adds desktop actions with policy-backed grants. Phase 3 adds a typed agent
loop with re-observation and cancellation.
Phase 4 adds app policy, scoped approval storage, revocation, and redacted audit records.
Phase 5A adds an independent OpenAI-compatible model transport and strict decision parsing.
Phase 5B connects that transport to the coordinator and existing API settings, with automatic
action execution in the Preview surface. The current parity slice adds the reference action shapes
that fit the existing process boundary, window selection and activation, screenshot identity
checks, indexed clicks, dynamic Accessibility actions, and target switching without deterministic
instruction matching. The 2026-08-03 cleanup removes the temporary manual action panel and
interactive approval state; the task path is now model decision -> policy authorization -> native
action -> fresh observation.

The desktop path is connected. It requires a configured API Endpoint model, Accessibility, and
Screen Recording because every macOS observation includes a screenshot. The agent can resolve and
launch installed apps through the application catalog. It is not full runtime parity: browser
control, helper IPC, and transient screenshot caching remain open or deferred. Direct voice can
use the existing page-visible dictation route or the dedicated optional global Hold to Run Task
shortcut; its design history is recorded in `direct-voice-integration-plan.md` and Phase 16.
The page-visible dictation redirect was removed on 2026-08-14: plain dictation always inserts at
the cursor, and tasks enter only through the composer or the dedicated shortcut.

The evidence-ledger validation entries record the state at the revision they were written
against; later revisions (including the 2026-08-14 review-fix series) are validated by the unit
suite and coverage gate only. Provider behavior, Screen Recording capture, and cross-process
input still require separate live validation.

## Files

- `evidence-ledger.md` records findings in small updates.
- `source-inventory.md` maps findings to DMG and Suniye source locations.
- `architecture.md` explains the observed Computer Use design.
- `implementation-plan.md` proposes an independent Swift design for Suniye.
- `open-questions.md` records gaps that need a decision or a live test.
- `direct-voice-integration-plan.md` records the direct voice routing seam, lifecycle, UX, and
  manual validation plan.
- `always-listening-ux-plan.md` defines the proposed always-listening voice experience, including
  activation, wake-up, conversational intervention, session continuity, feedback, privacy, and
  failure behavior. It intentionally contains no implementation design.
- `e2e-computer.md` records the live `@Computer` run, failures, fixes, and remaining unknowns.
- `parity-audit.md` is the current reference-to-Suniye parity matrix and corrective-slice record.
- `target-scope-implementation.md` records the target-lock correction and its validation boundary.
- `parity-audit-dmg-agent.md` is the detailed raw DMG audit used as supporting evidence.
- `bootstrap-and-self-target-parity-2026-08-08.md` records the focused correction for initial app
  selection, frontmost state, conversational routing, and host-app policy enforcement.
- `runtime-request-and-model-selection-recovery-2026-08-08.md` records client-side model
  selection, exact request construction and role ordering, Computer Use prompt-variant selection,
  and a loopback-captured request serialized by the DMG binary.
- `native-algorithm-recovery-2026-08-09.md` records the live native MCP session, exact ten-tool
  schema, background observation behavior, AX rendering and revision pipeline, window discovery,
  screenshot backends, coordinate conversion, and process-scoped input paths.
- `fake-cursor-dmg-agent-report.md` records the native virtual-cursor subsystem, compiled cursor
  asset, host/PIP bridge, separate browser cursor overlay, live visual corroboration, and the
  remaining exact-build unknowns.
- `fresh-implementation-baseline-2026-08-09.md` records the clean-main branch reset, preserved old
  branch, and rules for distinguishing historical implementation notes from current code.
- `phase-0-tool-contract-2026-08-09.md` records the exact ten-tool domain contract and validation.
- `phase-1-app-window-discovery-2026-08-09.md` records app discovery, exact target resolution,
  background launch, CG/AX window correlation, independent choices, and validation.
- `phase-2-observation-2026-08-09.md` records AX rendering/revisions/diffs, background screenshot
  capture, closest-match choices, tests, and the permission-bound live result.
- `phase-3-native-actions-2026-08-09.md` records native semantic and synthesized actions,
  process-scoped delivery, fresh-observation enforcement, settling, strict-review corrections,
  independent choices, and remaining live gaps.
- `phase-4-provider-agent-loop-2026-08-09.md` records the exact model tool contract, ordered
  context loop, provider transport, strict-review corrections, independent choices, validation,
  and remaining coordinator/UX work.
- `phase-5-coordinator-chat-voice-2026-08-09.md` records the main-actor coordinator, permission and
  cancellation lifecycle, conversation UI, direct-voice route, strict-review corrections,
  validation, and remaining live/native work.
- `phase-6-runtime-guards-settling-2026-08-09.md` records lock-state handling, loading-aware
  settling, the superseded physical-input experiment, and its live parity correction.
- `phase-7-live-observation-launch-parity-2026-08-09.md` records dynamic-title window matching,
  launch-completion and primary-window waiting, privacy-bounded diagnostics, installed live model
  results, strict review, and validation.
- `phase-8-native-virtual-cursor-2026-08-11.md` records the passive desktop cursor overlay,
  action-coordinate integration, cancellation behavior, validation, and remaining compositor
  unknowns.
- `phase-9-debug-session-correlation-2026-08-11.md` records the copyable per-run debug identifier,
  end-to-end log correlation, privacy boundary, and installed-app validation.
- `phase-10-inline-agent-activity-2026-08-11.md` records the deliberately minimal conversation
  activity UI: raw tool names and arguments only, with no transport, lifecycle, result, or icon
  decoration.
- `phase-11-run-scoped-cursor-and-native-parity-2026-08-12.md` records persistent cursor lifecycle,
  process-scoped pointer delivery, per-action observation semantics, same-process replacement
  window reacquisition, and current live validation.
- `phase-12-background-space-observation-2026-08-12.md` records the recovered all-window and
  Accessibility fallback, ScreenCaptureKit's verified off-Space failure, the matching private
  WindowServer screenshot path, and natural read/action E2E validation.
- `phase-13-collapsed-tool-results-2026-08-12.md` records in-place tool-result updates and the
  collapsed raw-output disclosure added to each inline tool call.
- `phase-14-browser-link-click-2026-08-12.md` records the failed-run RCA, primary-click ordering
  correction, and natural-language browser-link E2E validation.
- `phase-15-app-runtime-session-2026-08-12.md` records the app-owned coordinator, durable current
  session, page-independent voice handoff, and storage validation.
- `phase-16-global-voice-hotkey-2026-08-12.md` records the optional global Hold to Run Task
  shortcut, raw local voice route, collision policy, and Escape cancellation.
- `phase-17-independent-model-settings-2026-08-12.md` records the dedicated provider, endpoint,
  model, Keychain credential, connection test, and Magic Format isolation.
- `phase-18-model-context-normalization-2026-08-12.md` records protocol-paired activity history,
  model-only output cleanup, the 50-message/token budgets, screenshot retention, and
  model-specific truncation.
- `phase-19-spoken-intervention-2026-08-12.md` records same-session voice correction, atomic-action
  completion, stale-response rejection, and fresh re-observation before continuation.
- `phase-20-floating-run-lifecycle-2026-08-12.md` records the page-independent floating working,
  stop, completion, failure, and direct session-reset UX.
- `phase-21-background-voice-resilience-and-e2e-2026-08-12.md` records startup permission refresh,
  durable queued speech, installed request/tool/cancellation/background E2E, and the remaining
  physical voice-test boundary.
- `deep-code-parity-audit-2026-08-12.md` consolidates three independent code-level audits of the
  model/runtime, native mechanics, and cursor/UX, with verified gaps kept explicit.

## Evidence labels

- `[Verified]` means direct evidence exists in the inspected artifact or source.
- `[Inferred]` means a design conclusion follows from verified evidence.
- `[Unknown]` means the evidence does not answer the question.

## Research boundary

This work does not copy source code from the inspected artifact.

This work does not add browser control or a native helper.

The Phase 0 through Phase 5B slices, the parity cleanup, and the post-E2E validation are recorded
as separate evidence entries. Git handoff status is reported with the final commit.

## Superseding parity correction — 2026-08-03

- `[Verified]` The inspected macOS contract is app-scoped. Suniye no longer exposes a macOS
  window picker, Bring Forward control, target lock, frontmost intervention monitor, or first-app
  fallback. Native window resolution remains internal because AX and screenshot APIs still need a
  concrete window.
- `[Verified]` Indexed element operations are delegated to the native Accessibility boundary.
  Suniye retains only transport-shape checks that protect native adapters: finite coordinates,
  positive scroll pages, and a positive click count for the local event loop.
- `[Verified]` The local action, failure, and duration caps, deterministic instruction matcher,
  manual action panel, interactive approval UI, and remote screenshot-upload toggle are removed.
  The default agent authorizer grants actions automatically; the hidden policy service remains the
  app-policy and audit seam.
- `[Verified]` macOS observations always capture and attach a screenshot. Windows-only screenshot
  identifiers and coordinate metadata are not part of Suniye's model contract.
- `[Verified]` The model prompt contains native Accessibility text and the screenshot, without a
  second serialized Accessibility-element table or internal window metadata.
- `[Verified]` Static GPT-5.6 base instructions and complete readable Computer Use operating
  instructions were recovered from the inspected artifact. See
  `prompt-recovery-2026-08-08.md` and `recovered-prompts/`.
- `[Verified]` Client-side model selection, the Responses request schema, context/message ordering,
  and Computer Use prompt injection are recovered and verified by a request serialized by the DMG
  binary.
- `[Unknown]` Provider-private inference, unrecovered native-helper details, exact IPC
  authentication, and browser-extension behavior remain unavailable from the inspected artifact.

## Final cleanup validation — 2026-08-03

- `[Verified]` The final full suite reports 1,080 tests executed, 1 skipped, and 0 failures;
  gated coverage is 95.02% (13,672/14,389 lines).
- `[Verified]` E2E preflight and smoke pass, and the installed Preview is
  `<home>/Applications/Suniye Preview.app`.
- `[Verified]` A fresh Preview process no longer exposes the removed target lock, window picker,
  Bring Forward control, screenshot choice, manual action surface, or approval card.
- `[Verified]` The configured model completed a safe read-only Calculator task and reported the
  existing result `323` for `17 × 19`.
- `[Unknown]` Helper IPC internals, provider-private inference, Screen Recording consent,
  cross-process third-party input, and browser control remain outside this validation. The client
  loop, prompts, request schema, and context ordering were recovered later and are no longer part
  of this unknown set.

## Direct voice implementation — 2026-08-03

Historical page-visible slice; Phase 16 adds the page-independent global shortcut.

- `[Verified]` The existing dictation pipeline routes a raw local transcript to Computer Use only
  while the Computer Use page is visible.
- `[Verified]` The route bypasses text insertion, Magic Format, clipboard output, and dictation
  history, and the coordinator can start, queue, or reject the task through a typed seam.
- `[Verified]` The final full suite reports 1,087 passed, 1 skipped, and 0 failed tests; gated
  coverage is 95.04% (13,769/14,487 lines).
- `[Verified]` E2E preflight and smoke pass.
- `[Unknown]` Live microphone capture and provider execution through this voice route still need a
  manual macOS test.

## App-level runtime and durable session — 2026-08-12

- `[Verified]` The Computer Use coordinator now belongs to `AppState`, so closing or navigating
  away from the Computer Use UI does not destroy the runtime or cancel a handed-off transcript.
- `[Verified]` The complete local conversation, including raw tool results, is restored from an
  atomically written per-bundle session file and is removed by New conversation.
- `[Verified]` The full suite passes 1,098 tests with 2 skipped and zero failures; gated coverage
  is 88.35% (13,558/15,346), and E2E preflight and smoke pass.
- `[Superseded by Phase 16]` The dedicated global voice hotkey is now implemented. Separate
  Computer Use model configuration remains intentionally outside Phase 15.

## Global voice-to-task hotkey — 2026-08-12

- `[Verified]` An optional global Hold to Run Task shortcut now captures speech locally and sends
  the raw transcript to the current app-owned Computer Use conversation without opening Suniye.
- `[Verified]` The route bypasses Magic Format, clipboard insertion, focused-app insertion, and
  dictation history. Escape cancels task recording without submitting a transcript.
- `[Verified]` Three-way shortcut collision handling is persisted and legacy settings default the
  new shortcut to disabled.
- `[Verified]` The full suite passes 1,106 tests with 2 skipped and zero failures; gated coverage
  is 88.41% (13,663/15,454), and E2E preflight and smoke pass.
- `[Superseded by Phase 17]` Dedicated Computer Use model configuration is now implemented.

## Independent Computer Use model settings — 2026-08-12

- `[Verified]` Computer Use now has its own provider, API endpoint, model ID, timeout, token limit,
  and separate macOS Keychain credential. Magic Format mutations no longer reconfigure it.
- `[Verified]` The bottom Computer Use settings disclosure exposes provider, model, endpoint,
  credential Save/Clear, connection testing, Accessibility, and Screen Recording controls.
- `[Verified]` The full suite passes 1,111 tests with 2 skipped and zero failures; gated coverage
  is 86.82% (13,789/15,882), and E2E preflight and smoke pass.
- `[Superseded by Phase 18]` Model-visible context normalization, cleanup, and bounded compaction
  are now implemented.

## Model context normalization — 2026-08-12

- `[Implemented]` Model history now preserves completed tool calls and results as protocol pairs,
  strips local screenshot URLs only from provider payloads, and retains raw local activity.
- `[Implemented]` Requests are bounded to the latest useful 50 messages under a model-aware token
  budget while retaining the current instruction, latest observation, and two newest readable
  images across user turns.
- `[Implemented]` Tool output uses the recovered UTF-8-safe middle truncation format and the
  selected model's known policy where metadata is available.
- `[Verified]` The full suite passes 1,124 tests with 2 skipped and zero failures; gated coverage
  is 87.00% (14,075/16,179 lines), and E2E preflight and smoke pass.

## Spoken intervention — 2026-08-12

- `[Implemented]` Voice during an active run becomes a user correction in the same durable
  conversation rather than an error or a new session.
- `[Implemented]` The current atomic native action may finish, stale in-flight model output is
  discarded, and the last established app target is freshly observed before the next decision.
- `[Unknown]` The artifact does not expose the exact internal spoken-intervention checkpoint, so
  this is a documented closest-match serial-loop implementation.
- `[Verified]` The full suite passes 1,127 tests with 2 skipped and zero failures; gated coverage
  is 87.07% (14,191/16,299 lines), and E2E preflight and smoke pass.

## Floating run lifecycle and direct session reset — 2026-08-12

- `[Implemented]` Typed and spoken tasks now share an app-level floating lifecycle: listening,
  generic shimmering `Working` with one stop affordance, brief `Done`, cancellation, and failure.
- `[Implemented]` The menu bar can clear the current Computer Use conversation directly without
  opening the Computer Use page, but cannot clear an active run.
- `[Unknown]` The artifact does not expose exact host progress copy, shimmer timing, stop
  placement, or menu-bar controls; these are explicitly user-directed Suniye UX choices.
- `[Verified]` The full suite passes 1,131 tests with 2 skipped and zero failures; gated coverage
  is 87.00% (14,256/16,387 lines), and E2E preflight and smoke pass.

## Running application window recovery — 2026-08-12

- `[Verified live]` Session `CU-C96C0E8AAC68` exposed an already-running Chrome process with no
  observable window. The missing lifecycle recovery caused a 321-second, 59-tool-call run.
- `[Implemented]` Observation now preserves the same-process replacement-window wait, then asks
  macOS to reopen the application once in the background if that wait expires, and observes the
  returned application before authorizing input.
- `[Unknown]` The inspected artifact does not reveal its exact already-running, zero-window branch;
  Suniye uses the closest narrow native lifecycle recovery and adds no task-specific routing.
- `[Verified]` Focused tests pass; the full suite passes 1,139 tests with 2 skipped and zero
  failures. Gated coverage is 87.05% (14,398/16,539 lines) against the 80% floor. E2E preflight
  and smoke pass.
- `[Verified live]` Restarted installed Preview session `CU-63BFC1495D24` recovered the existing
  zero-window Chrome process in about six seconds and reported `New Tab - Google Chrome` from a
  fresh Accessibility observation and screenshot.

## Subtle persistent cursor glow — 2026-08-12

- `[Implemented]` The retained software cursor's blue halo now breathes subtly while visible,
  including between tool calls. The cursor icon remains still.
- `[Implemented]` Reduce Motion uses a static halo, and hidden cursor panels pause the animation
  timeline.
- `[Verified]` Focused tests cover the animation bounds and reduced-motion behavior.

## Assistant Markdown rendering — 2026-08-12

- `[Implemented]` Assistant chat text now renders native Markdown for emphasis, inline code, and
  links while preserving line breaks and list layout.
- `[Not changed]` User text and raw tool calls/results remain verbatim.
- `[Verified live]` Restarted Preview renders `Clicked **7** in Calculator.` without showing the
  emphasis delimiters. The full suite passes 1,143 tests with 2 skipped and zero failures; gated
  coverage is 87.05% against the 80% floor.

## Browser feedback-loop correction — 2026-08-12

- `[Implemented]` Provider-qualified Luna IDs now receive the intended model context policy.
- `[Implemented]` Accessibility observations retain the focused element and unchanged trees return
  a compact no-change status instead of expanding back into the full tree.
- `[Verified live]` Installed Preview session `CU-66A245F07512` completed the original Gmail task
  from the inbox and reported the newest Apple email without reproducing the 41-click loop.
- `[Verified]` The full suite passes 1,145 tests with 2 skipped and zero failures; gated coverage
  is 87.08% against the 80% floor, and E2E preflight and smoke pass.
