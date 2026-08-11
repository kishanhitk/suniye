# KIS-169 Computer Use research

This folder records the Computer Use research and the Phase 0 through the current desktop parity
implementation for Suniye.

The source artifact is `/Users/kishan/Downloads/ChatGPT (1).dmg`.

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
control, helper IPC, and transient screenshot caching remain open or deferred. Direct voice
submission is now connected through the existing Suniye hold-to-talk flow while the Computer Use
page is visible; its design is recorded in `direct-voice-integration-plan.md`.

The current cleanup validation is recorded in the final evidence-ledger entry after the full test,
coverage, build, and live safe-target checks. Provider behavior, Screen Recording capture, and
cross-process input still require separate validation.

## Files

- `evidence-ledger.md` records findings in small updates.
- `source-inventory.md` maps findings to DMG and Suniye source locations.
- `architecture.md` explains the observed Computer Use design.
- `implementation-plan.md` proposes an independent Swift design for Suniye.
- `open-questions.md` records gaps that need a decision or a live test.
- `direct-voice-integration-plan.md` records the direct voice routing seam, lifecycle, UX, and
  manual validation plan.
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
  `/Users/kishan/Applications/Suniye Preview.app`.
- `[Verified]` A fresh Preview process no longer exposes the removed target lock, window picker,
  Bring Forward control, screenshot choice, manual action surface, or approval card.
- `[Verified]` The configured model completed a safe read-only Calculator task and reported the
  existing result `323` for `17 × 19`.
- `[Unknown]` Helper IPC internals, provider-private inference, Screen Recording consent,
  cross-process third-party input, and browser control remain outside this validation. The client
  loop, prompts, request schema, and context ordering were recovered later and are no longer part
  of this unknown set.

## Direct voice implementation — 2026-08-03

- `[Verified]` The existing dictation pipeline routes a raw local transcript to Computer Use only
  while the Computer Use page is visible.
- `[Verified]` The route bypasses text insertion, Magic Format, clipboard output, and dictation
  history, and the coordinator can start, queue, or reject the task through a typed seam.
- `[Verified]` The final full suite reports 1,087 passed, 1 skipped, and 0 failed tests; gated
  coverage is 95.04% (13,769/14,487 lines).
- `[Verified]` E2E preflight and smoke pass.
- `[Unknown]` Live microphone capture and provider execution through this voice route still need a
  manual macOS test.
