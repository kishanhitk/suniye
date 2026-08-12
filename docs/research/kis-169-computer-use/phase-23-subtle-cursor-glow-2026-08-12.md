# Phase 23: subtle cursor glow

Date: 2026-08-12

## Outcome

- `[Implemented]` The persistent software cursor's existing blue halo now breathes continuously
  while the cursor is visible, including while the model is reasoning between actions.
- `[Implemented]` The cursor icon does not pulse or move. Only the halo changes, over a 2.8-second
  cycle, between 0.98 and 1.02 scale and between 0.88 and 1.00 opacity.
- `[Implemented]` Reduce Motion replaces the cycle with a static halo.
- `[Implemented]` The animation timeline pauses whenever the cursor overlay is hidden.
- `[Not changed]` Pointer travel, click compression, drag behavior, run-scoped persistence,
  process-scoped input, and cursor teardown behavior are unchanged.

## Reference boundary

- `[Verified artifact]` The inspected desktop implementation has a dedicated software-cursor
  window and retained cursor state.
- `[Unknown]` The exact reference glow animation values are not recoverable from the inspected
  artifact.
- `[User-directed]` The subtle animated glow is an explicit Suniye UX refinement, not a claimed
  byte-for-byte reference value.

## Validation

- `[Verified]` Unit tests cover the cycle's minimum and maximum scale and opacity.
- `[Verified]` Unit tests cover the static Reduce Motion result.
- `[Verified]` The cursor presenter suite passes.
- `[Verified]` The complete suite passes 1,143 tests with 2 skipped and zero failures. Gated line
  coverage is 87.05% (14,469/16,622 lines), above the required 80% floor.
- `[Verified]` The updated Debug Preview is installed and restarted at
  `/Users/kishan/Applications/Suniye Preview.app`.
