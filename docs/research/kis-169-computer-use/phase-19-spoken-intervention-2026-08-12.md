# Phase 19: spoken intervention during an active run

Date: 2026-08-12

## Reference boundary

- `[Verified]` The inspected desktop model loop preserves ordered user, model, tool-call, and
  tool-result items. Native tool work is awaited before the loop advances.
- `[Verified]` Suniye already executes one model-selected tool call at a time and requires a fresh
  observation before a later native action.
- `[Unknown]` The inspected artifact does not expose an exact voice-intervention queue, the precise
  checkpoint at which a spoken correction invalidates an in-flight model response, or a reusable
  native API for that behavior.

## Implementation

- `[Implemented]` A voice transcript received while Computer Use is running is appended to the
  same visible and persisted conversation as a user turn. It is not rejected, inserted into the
  frontmost app, copied to the clipboard, or started as a second session.
- `[Implemented]` Each run owns a small thread-safe intervention channel shared by the app-level
  coordinator and agent. Stop and run completion clear the channel with the rest of the active
  run state.
- `[Implemented]` The agent checks for intervention before every model request and again after each
  model response. A correction received while the model is deciding discards that stale response,
  including a proposed action, before it can execute.
- `[Implemented]` A correction received during an atomic native action does not cancel that action
  midway. The action completes, then the correction is applied before another model decision.
- `[Implemented]` When the run has an app target, intervention triggers a fresh `get_app_state`
  observation for that app. The synthetic observation uses the same native session, activity row,
  model-result cleanup, screenshot handling, and freshness rules as a model-requested observation.
- `[Implemented]` When no app target has been established, the correction is added to context and
  the model chooses the appropriate app or non-app path on its next turn.

## Closest-match choices

- `[Closest match]` Suniye checks the intervention channel at deterministic boundaries around the
  existing serial model/tool loop. This preserves atomic native calls and prevents stale model
  output from driving a later action without inventing process interruption inside macOS APIs.
- `[Closest match]` Fresh re-observation is automatic only for the last established app target.
  Suniye does not infer a new target from intervention text or add a deterministic app matcher.

## Scope boundary

- `[Not added]` No new session, page navigation, target lock, task matcher, approval prompt,
  physical-input cancellation, or concurrent action execution was introduced.
- `[Not changed]` The global Computer Use hotkey still uses local ASR and bypasses Magic Format,
  dictation history, clipboard output, and focused-app insertion.

## Validation

- `[Verified]` Tests cover active-run coordinator routing, same-session visible history, raw voice
  handoff, no text insertion, completion of the current native action, mandatory fresh
  observation, and stale model-action rejection.
- `[Verified]` The full suite passes 1,127 tests with 2 skipped and zero failures.
- `[Verified]` Gated coverage is 87.07% (14,191/16,299 lines), above the 80% floor.
- `[Verified]` E2E preflight and smoke pass.
