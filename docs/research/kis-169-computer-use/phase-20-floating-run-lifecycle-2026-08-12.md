# Phase 20: floating run lifecycle and direct session reset

Date: 2026-08-12

## Evidence boundary

- `[Verified]` The inspected native desktop runtime has explicit cursor and run lifecycle state,
  but the packaged tool contract does not expose the host application's exact floating progress
  surface.
- `[Unknown]` Exact progress copy, shimmer timing, stop placement, and menu-bar session controls
  are not recoverable from the artifact.
- `[User-directed]` Suniye should expose listening, generic working, one stop affordance, brief
  completion, and failure without requiring the Computer Use conversation to be open.

## Implementation

- `[Implemented]` The app-owned coordinator publishes run phase changes to `AppState`. Typed and
  spoken tasks therefore drive the same floating lifecycle outside the main window.
- `[Implemented]` The existing indicator shows the Computer Use listening meter while capturing
  speech, then a generic shimmering `Working` pill for the run. The pill contains one stop icon;
  tapping the pill cancels the coordinator run.
- `[Implemented]` Successful completion briefly shows `Done`, cancellation returns to idle, and a
  failed run uses the existing transient error presentation.
- `[Implemented]` Computer Use states stay on the screen where the task began and cannot be
  dragged while active. The software cursor remains independently owned by the run.
- `[Implemented]` The menu bar contains a direct `New Computer Use Conversation` action. It is
  enabled only when a stored conversation exists and no run is active, and it clears the same
  app-owned session without opening the Computer Use page.
- `[Implemented]` The indicator E2E smoke sequence now renders both Computer Use states.

## Scope boundary

- `[Not added]` No task matcher, app target lock, approval prompt, forced page navigation,
  physical-input cancellation, duplicate stop button, or task-specific progress copy was added.
- `[Independent choice]` Suniye uses its existing floating indicator and status-item menu rather
  than claiming an unrecovered host UX implementation from the artifact.

## Validation

- `[Verified]` Focused tests cover working, stop, completed, new-conversation reset, layout keys,
  log values, and screen anchoring behavior.
- `[Verified]` The full suite passes 1,131 tests with 2 skipped and zero failures.
- `[Verified]` Gated coverage is 87.00% (14,256/16,387 lines), above the 80% floor.
- `[Verified]` E2E preflight and smoke pass.
