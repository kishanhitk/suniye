# KIS-169 Computer Use research

This folder records the Computer Use research and the Phase 0 through the current desktop parity
implementation for Suniye.

The source artifact is `/Users/kishan/Downloads/ChatGPT (1).dmg`.

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
- `[Unknown]` The complete native helper, IPC, host model loop, exact prompt, and browser extension
  behavior remain unavailable from the inspected artifact.

## Final cleanup validation — 2026-08-03

- `[Verified]` The final full suite reports 1,080 tests executed, 1 skipped, and 0 failures;
  gated coverage is 95.02% (13,672/14,389 lines).
- `[Verified]` E2E preflight and smoke pass, and the installed Preview is
  `/Users/kishan/Applications/Suniye Preview.app`.
- `[Verified]` A fresh Preview process no longer exposes the removed target lock, window picker,
  Bring Forward control, screenshot choice, manual action surface, or approval card.
- `[Verified]` The configured model completed a safe read-only Calculator task and reported the
  existing result `323` for `17 × 19`.
- `[Unknown]` Helper IPC, the reference server/model loop and prompt, Screen Recording consent,
  cross-process third-party input, and browser control remain outside this validation.

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
